import Foundation
import OSLog

// MARK: - Конфиг облачного LLM

struct CloudLLMConfiguration: Equatable {
    static let defaultBaseURLString = "https://gigachat.devices.sberbank.ru/api/v1"
    static let defaultModel = "GigaChat-2-Max"
    static let defaultTemperature = 0.1
    static let defaultRequestTimeout: TimeInterval = 30.0
    static let defaultRetryDelay: TimeInterval = 0.5
    static let defaultMaxOutputTokens = 128

    let baseURLString: String
    let model: String
    let temperature: Double
    let requestTimeout: TimeInterval
    let retryDelay: TimeInterval
    let maxOutputTokens: Int

    init(
        baseURLString: String = CloudLLMConfiguration.defaultBaseURLString,
        model: String = CloudLLMConfiguration.defaultModel,
        temperature: Double = CloudLLMConfiguration.defaultTemperature,
        requestTimeout: TimeInterval = CloudLLMConfiguration.defaultRequestTimeout,
        retryDelay: TimeInterval = CloudLLMConfiguration.defaultRetryDelay,
        maxOutputTokens: Int = CloudLLMConfiguration.defaultMaxOutputTokens
    ) {
        self.baseURLString = baseURLString
        self.model = model
        self.temperature = temperature
        self.requestTimeout = max(0.1, requestTimeout)
        self.retryDelay = max(0, retryDelay)
        self.maxOutputTokens = max(1, maxOutputTokens)
    }
}

// MARK: - isRetryable

extension LLMError {
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .timeout:
            true
        default:
            false
        }
    }
}

// MARK: - Облачный LLM клиент

final class CloudLLMClient: LLMClient, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.govorun.app", category: "CloudLLMClient")

    private let authService: AuthService
    private let httpClient: HTTPClient
    private let configuration: CloudLLMConfiguration

    init(
        authService: AuthService,
        httpClient: HTTPClient,
        configuration: CloudLLMConfiguration = CloudLLMConfiguration()
    ) {
        self.authService = authService
        self.httpClient = httpClient
        self.configuration = configuration
    }

    // MARK: - LLMClient

    func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let token = try await obtainToken()

        let systemPrompt = superStyle.systemPrompt(
            currentDate: hints.currentDate,
            personalDictionary: hints.personalDictionary,
            snippetContext: hints.snippetContext,
            appName: hints.appName
        )

        do {
            return try await sendChatCompletion(
                systemPrompt: systemPrompt,
                userContent: trimmed,
                attachments: nil,
                token: token
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LLMError where error.isRetryable {
            try await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
            return try await sendChatCompletion(
                systemPrompt: systemPrompt,
                userContent: trimmed,
                attachments: nil,
                token: token
            )
        }
    }

    // MARK: - Cloud audio

    func processAudio(audioData: Data, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
        let token = try await obtainToken()

        let fileID = try await uploadAudio(audioData, token: token)

        let systemPrompt = superStyle.systemPrompt(
            currentDate: hints.currentDate,
            personalDictionary: hints.personalDictionary,
            snippetContext: hints.snippetContext,
            appName: hints.appName
        )

        do {
            return try await sendChatCompletion(
                systemPrompt: systemPrompt,
                userContent: "",
                attachments: [fileID],
                token: token
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LLMError where error.isRetryable {
            Self.logger.info("Retry chat/completions через \(self.configuration.retryDelay, privacy: .public)s")
            try await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
            return try await sendChatCompletion(
                systemPrompt: systemPrompt,
                userContent: "",
                attachments: [fileID],
                token: token
            )
        }
    }

    // MARK: - Private

    private func obtainToken() async throws -> String {
        do {
            return try await authService.getAccessToken()
        } catch let error as AuthError {
            throw mapAuthError(error)
        } catch {
            if isCancellation(error) { throw CancellationError() }
            throw LLMError.networkError(error.localizedDescription)
        }
    }

    private func uploadAudio(_ audioData: Data, token: String) async throws -> String {
        let boundary = UUID().uuidString
        let body = buildMultipartBody(audioData: audioData, boundary: boundary)

        var request = URLRequest(url: URL(string: configuration.baseURLString + "/files")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = configuration.requestTimeout
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            if isCancellation(error) { throw CancellationError() }
            if let urlError = error as? URLError {
                throw mapTransportError(urlError)
            }
            throw LLMError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("GigaChat API не вернул HTTP-ответ")
        }
        try validateStatus(httpResponse)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileID = json["id"] as? String
        else {
            throw LLMError.parsingFailed
        }

        return fileID
    }

    private func buildMultipartBody(audioData: Data, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
        body.append("general\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }

    private func sendChatCompletion(
        systemPrompt: String,
        userContent: String,
        attachments: [String]?,
        token: String
    ) async throws -> String {
        var userMessage: [String: Any] = ["role": "user", "content": userContent]
        if let attachments {
            userMessage["attachments"] = attachments
        }

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            userMessage,
        ]

        let requestBody: [String: Any] = [
            "model": configuration.model,
            "temperature": configuration.temperature,
            "max_tokens": configuration.maxOutputTokens,
            "messages": messages,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: URL(string: configuration.baseURLString + "/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = configuration.requestTimeout
        request.httpBody = jsonData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            if isCancellation(error) { throw CancellationError() }
            if let urlError = error as? URLError {
                if urlError.code == .timedOut { throw LLMError.timeout }
                if urlError.code == .cancelled { throw CancellationError() }
                throw mapTransportError(urlError)
            }
            throw LLMError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("GigaChat API не вернул HTTP-ответ")
        }
        try validateStatus(httpResponse)

        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw LLMError.parsingFailed
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 408:
            throw LLMError.timeout
        case 429:
            throw LLMError.rateLimited
        case 500 ..< 600:
            throw LLMError.serverError(statusCode: response.statusCode)
        default:
            throw LLMError.invalidResponse(statusCode: response.statusCode)
        }
    }

    private func mapAuthError(_ error: AuthError) -> LLMError {
        switch error {
        case .credentialsNotFound:
            .networkError("Cloud credentials not configured")
        case .networkError(let msg):
            .networkError(msg)
        case .invalidResponse(let code):
            .invalidResponse(statusCode: code)
        case .tokenParsingFailed:
            .parsingFailed
        }
    }

    private func mapTransportError(_ error: URLError) -> LLMError {
        switch error.code {
        case .timedOut:
            .timeout
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            .networkError("GigaChat API недоступен")
        default:
            .networkError(error.localizedDescription)
        }
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

// MARK: - Data extension

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
