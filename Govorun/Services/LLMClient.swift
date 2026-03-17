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
            return true
        case (.networkError(let a), .networkError(let b)):
            return a == b
        case (.invalidResponse(let a), .invalidResponse(let b)):
            return a == b
        case (.serverError(let a), .serverError(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Плейсхолдер (до реализации LocalLLMClient)

final class PlaceholderLLMClient: LLMClient, Sendable {
    func normalize(_ text: String, mode: TextMode, hints: NormalizationHints) async throws -> String {
        throw LLMError.networkError("LLM не настроен — локальный worker ещё не реализован")
    }
}
