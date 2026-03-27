import Foundation

// MARK: - Протокол LLM

protocol LLMClient: Sendable {
    func normalize(_ text: String, mode: TextMode, hints: NormalizationHints) async throws -> String
}

// MARK: - Ошибки

enum LLMError: Error, Equatable {
    case networkError(String)
    case invalidResponse(statusCode: Int)
    case parsingFailed
    case rateLimited
    case serverError(statusCode: Int)
    case timeout

    static func == (lhs: LLMError, rhs: LLMError) -> Bool {
        switch (lhs, rhs) {
        case (.parsingFailed, .parsingFailed),
             (.rateLimited, .rateLimited),
             (.timeout, .timeout):
            true
        case (.networkError(let a), .networkError(let b)):
            a == b
        case (.invalidResponse(let a), .invalidResponse(let b)):
            a == b
        case (.serverError(let a), .serverError(let b)):
            a == b
        default:
            false
        }
    }
}

// MARK: - Конфиг локального LLM

struct LocalLLMConfiguration: Equatable {
    static let defaultBaseURLString = "http://127.0.0.1:8080/v1"
    static let defaultModel = "gigachat-gguf"
    static let defaultRequestTimeout: TimeInterval = 12.0
    static let defaultHealthcheckTimeout: TimeInterval = 1.5
    static let defaultHealthcheckTTL: TimeInterval = 30.0
    static let defaultFailureCooldown: TimeInterval = 5.0
    static let defaultMaxOutputTokens = 128
    static let defaultTemperature = 0.0
    static let defaultStopSequences = ["\n\n"]

    let baseURLString: String
    let model: String
    let requestTimeout: TimeInterval
    let healthcheckTimeout: TimeInterval
    let healthcheckSuccessTTL: TimeInterval
    let failureCooldown: TimeInterval
    let maxOutputTokens: Int
    let temperature: Double
    let stopSequences: [String]

    init(
        baseURLString: String = LocalLLMConfiguration.defaultBaseURLString,
        model: String = LocalLLMConfiguration.defaultModel,
        requestTimeout: TimeInterval = LocalLLMConfiguration.defaultRequestTimeout,
        healthcheckTimeout: TimeInterval = LocalLLMConfiguration.defaultHealthcheckTimeout,
        healthcheckSuccessTTL: TimeInterval = LocalLLMConfiguration.defaultHealthcheckTTL,
        failureCooldown: TimeInterval = LocalLLMConfiguration.defaultFailureCooldown,
        maxOutputTokens: Int = LocalLLMConfiguration.defaultMaxOutputTokens,
        temperature: Double = LocalLLMConfiguration.defaultTemperature,
        stopSequences: [String] = LocalLLMConfiguration.defaultStopSequences
    ) {
        self.baseURLString = baseURLString
        self.model = model
        self.requestTimeout = max(0.1, requestTimeout)
        self.healthcheckTimeout = max(0.1, healthcheckTimeout)
        self.healthcheckSuccessTTL = max(0, healthcheckSuccessTTL)
        self.failureCooldown = max(0, failureCooldown)
        self.maxOutputTokens = max(1, maxOutputTokens)
        self.temperature = temperature
        self.stopSequences = stopSequences
    }

    var normalizedBaseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = trimmed.replacingOccurrences(
            of: "/+$",
            with: "",
            options: .regularExpression
        )
        guard let url = URL(string: sanitized), url.scheme != nil, url.host != nil else {
            return nil
        }
        return url
    }

    var normalizedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resolved(
        baseURLString: String = LocalLLMConfiguration.defaultBaseURLString,
        model: String = LocalLLMConfiguration.defaultModel,
        requestTimeout: TimeInterval = LocalLLMConfiguration.defaultRequestTimeout,
        healthcheckTimeout: TimeInterval = LocalLLMConfiguration.defaultHealthcheckTimeout,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LocalLLMConfiguration {
        LocalLLMConfiguration(
            baseURLString: stringOverride(
                key: "GOVORUN_LLM_BASE_URL",
                fallback: baseURLString,
                environment: environment
            ),
            model: stringOverride(
                key: "GOVORUN_LLM_MODEL",
                fallback: model,
                environment: environment
            ),
            requestTimeout: doubleOverride(
                key: "GOVORUN_LLM_TIMEOUT",
                fallback: requestTimeout,
                environment: environment
            ),
            healthcheckTimeout: doubleOverride(
                key: "GOVORUN_LLM_HEALTHCHECK_TIMEOUT",
                fallback: healthcheckTimeout,
                environment: environment
            ),
            healthcheckSuccessTTL: nonNegativeDoubleOverride(
                key: "GOVORUN_LLM_HEALTHCHECK_TTL",
                fallback: defaultHealthcheckTTL,
                environment: environment
            ),
            failureCooldown: nonNegativeDoubleOverride(
                key: "GOVORUN_LLM_FAILURE_COOLDOWN",
                fallback: defaultFailureCooldown,
                environment: environment
            ),
            maxOutputTokens: intOverride(
                key: "GOVORUN_LLM_MAX_TOKENS",
                fallback: defaultMaxOutputTokens,
                environment: environment
            ),
            temperature: nonNegativeDoubleOverride(
                key: "GOVORUN_LLM_TEMPERATURE",
                fallback: defaultTemperature,
                environment: environment
            ),
            stopSequences: defaultStopSequences
        )
    }

    private static func stringOverride(
        key: String,
        fallback: String,
        environment: [String: String]
    ) -> String {
        let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

    private static func doubleOverride(
        key: String,
        fallback: TimeInterval,
        environment: [String: String]
    ) -> TimeInterval {
        guard let raw = environment[key],
              let value = TimeInterval(raw),
              value > 0
        else {
            return fallback
        }
        return value
    }

    private static func nonNegativeDoubleOverride(
        key: String,
        fallback: TimeInterval,
        environment: [String: String]
    ) -> TimeInterval {
        guard let raw = environment[key],
              let value = TimeInterval(raw),
              value >= 0
        else {
            return fallback
        }
        return value
    }

    private static func intOverride(
        key: String,
        fallback: Int,
        environment: [String: String]
    ) -> Int {
        guard let raw = environment[key],
              let value = Int(raw),
              value > 0
        else {
            return fallback
        }
        return value
    }
}

// MARK: - Плейсхолдер

final class PlaceholderLLMClient: LLMClient, Sendable {
    func normalize(_ text: String, mode: TextMode, hints: NormalizationHints) async throws -> String {
        throw LLMError.networkError("LLM не настроен — локальный worker ещё не реализован")
    }
}
