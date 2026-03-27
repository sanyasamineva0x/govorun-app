import Foundation
import OSLog

private actor LocalLLMHealthState {
    private var lastHealthyAt: Date?
    private var unavailableUntil: Date?

    enum Decision {
        case failFast
        case probe
        case skipProbe
    }

    func decision(now: Date, successTTL: TimeInterval) -> Decision {
        if let unavailableUntil, unavailableUntil > now {
            return .failFast
        }
        if let lastHealthyAt, now.timeIntervalSince(lastHealthyAt) < successTTL {
            return .skipProbe
        }
        return .probe
    }

    func recordSuccess(now: Date) {
        lastHealthyAt = now
        unavailableUntil = nil
    }

    func recordFailure(now: Date, cooldown: TimeInterval) {
        lastHealthyAt = nil
        unavailableUntil = now.addingTimeInterval(cooldown)
    }
}

final class LocalLLMClient: LLMClient, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.govorun.app", category: "LocalLLMClient")

    private let configuration: LocalLLMConfiguration
    private let session: URLSession
    private let healthState = LocalLLMHealthState()

    init(
        configuration: LocalLLMConfiguration = .resolved(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func normalize(_ text: String, mode: TextMode, hints: NormalizationHints) async throws -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return trimmedText }

        let baseURL = try validatedBaseURL()
        let model = try validatedModel()

        try await ensureBackendReady(baseURL: baseURL, model: model)

        do {
            let output = try await sendChatCompletion(
                input: trimmedText,
                mode: mode,
                hints: hints,
                baseURL: baseURL,
                model: model
            )
            await healthState.recordSuccess(now: Date())
            return output
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await healthState.recordFailure(
                now: Date(),
                cooldown: configuration.failureCooldown
            )
            Self.logger.error("Local LLM request failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func ensureBackendReady(baseURL: URL, model: String) async throws {
        switch await healthState.decision(
            now: Date(),
            successTTL: configuration.healthcheckSuccessTTL
        ) {
        case .failFast:
            throw LLMError.networkError("Локальный GigaChat runtime временно недоступен")
        case .skipProbe:
            return
        case .probe:
            break
        }

        do {
            try await performHealthcheck(baseURL: baseURL, model: model)
            await healthState.recordSuccess(now: Date())
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await healthState.recordFailure(
                now: Date(),
                cooldown: configuration.failureCooldown
            )
            Self.logger.error("Local LLM healthcheck failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func performHealthcheck(baseURL: URL, model: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "models"))
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.healthcheckTimeout

        let (data, response) = try await perform(request)
        try validateStatus(response)

        let decoder = JSONDecoder()
        let modelsResponse: ModelsResponse
        do {
            modelsResponse = try decoder.decode(ModelsResponse.self, from: data)
        } catch {
            Self.logger.error("Healthcheck JSON decoding failed: \(String(describing: error), privacy: .public)")
            throw LLMError.parsingFailed
        }

        let availableModels = modelsResponse.data.map(\.id)
        guard availableModels.contains(model) else {
            let available = availableModels.isEmpty ? "пусто" : availableModels.joined(separator: ", ")
            throw LLMError.networkError(
                "Модель \(model) не найдена на локальном endpoint. Доступно: \(available)"
            )
        }
    }

    private func sendChatCompletion(
        input: String,
        mode: TextMode,
        hints: NormalizationHints,
        baseURL: URL,
        model: String
    ) async throws -> String {
        let systemPrompt = mode.systemPrompt(
            currentDate: hints.currentDate,
            personalDictionary: hints.personalDictionary,
            snippetContext: hints.snippetContext,
            appName: hints.appName
        )

        let stopSequences = configuration.stopSequences.isEmpty ? nil : configuration.stopSequences
        let requestBody = ChatCompletionRequest(
            model: model,
            temperature: configuration.temperature,
            maxTokens: configuration.maxOutputTokens,
            stop: stopSequences,
            stream: false,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: input),
            ]
        )

        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await perform(request)
        try validateStatus(response)

        let decoder = JSONDecoder()
        let completion: ChatCompletionResponse
        do {
            completion = try decoder.decode(ChatCompletionResponse.self, from: data)
        } catch {
            Self.logger.error("Completion JSON decoding failed: \(String(describing: error), privacy: .public)")
            throw LLMError.parsingFailed
        }

        guard let output = completion.choices.first?.message.content.textValue else {
            throw LLMError.parsingFailed
        }

        return output
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMError.networkError("Локальный endpoint не вернул HTTP-ответ")
            }
            return (data, httpResponse)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled {
                throw CancellationError()
            }
            throw mapTransportError(error)
        } catch let error as LLMError {
            throw error
        } catch {
            if isCancellation(error) {
                throw CancellationError()
            }
            throw LLMError.networkError(error.localizedDescription)
        }
    }

    private func validateStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 408:
            throw LLMError.timeout
        case 429:
            throw LLMError.rateLimited
        case 500..<600:
            throw LLMError.serverError(statusCode: response.statusCode)
        default:
            throw LLMError.invalidResponse(statusCode: response.statusCode)
        }
    }

    private func mapTransportError(_ error: URLError) -> LLMError {
        switch error.code {
        case .timedOut:
            .timeout
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            .networkError("Локальный GigaChat runtime недоступен")
        default:
            .networkError(error.localizedDescription)
        }
    }

    private func validatedBaseURL() throws -> URL {
        guard let url = configuration.normalizedBaseURL else {
            throw LLMError.networkError("Некорректный URL локального LLM endpoint")
        }
        return url
    }

    private func validatedModel() throws -> String {
        let model = configuration.normalizedModel
        guard !model.isEmpty else {
            throw LLMError.networkError("Не указана модель локального LLM runtime")
        }
        return model
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == URLError.cancelled.rawValue
        {
            return true
        }

        return nsError.domain == "Swift.CancellationError"
    }
}

private struct ModelsResponse: Decodable {
    let data: [ModelDescriptor]
}

private struct ModelDescriptor: Decodable {
    let id: String
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let temperature: Double
    let maxTokens: Int
    let stop: [String]?
    let stream: Bool
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case maxTokens = "max_tokens"
        case stop
        case stream
        case messages
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: AssistantMessage
    }

    struct AssistantMessage: Decodable {
        let content: AssistantContent
    }

    let choices: [Choice]
}

private enum AssistantContent: Decodable {
    case text(String)
    case parts([AssistantContentPart])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        if let parts = try? container.decode([AssistantContentPart].self) {
            self = .parts(parts)
            return
        }
        throw DecodingError.typeMismatch(
            AssistantContent.self,
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported assistant content"
            )
        )
    }

    var textValue: String? {
        switch self {
        case .text(let text):
            return text
        case .parts(let parts):
            let text = parts.compactMap(\.text).joined()
            return text.isEmpty ? nil : text
        }
    }
}

private struct AssistantContentPart: Decodable {
    let type: String?
    let text: String?
}
