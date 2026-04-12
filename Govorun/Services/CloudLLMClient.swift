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

// MARK: - Облачный LLM клиент (stub)

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
        throw LLMError.networkError("Not implemented")
    }

    // MARK: - Cloud audio

    func processAudio(audioData: Data, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
        throw LLMError.networkError("Not implemented")
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
