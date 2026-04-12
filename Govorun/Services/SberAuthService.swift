import Foundation

// MARK: - Протокол

protocol AuthService: Sendable {
    func getAccessToken() async throws -> String
}

// MARK: - Ошибки

enum AuthError: Error, Equatable {
    case credentialsNotFound
    case networkError(String)
    case invalidResponse(statusCode: Int)
    case tokenParsingFailed

    static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        switch (lhs, rhs) {
        case (.credentialsNotFound, .credentialsNotFound):
            true
        case (.networkError(let a), .networkError(let b)):
            a == b
        case (.invalidResponse(let a), .invalidResponse(let b)):
            a == b
        case (.tokenParsingFailed, .tokenParsingFailed):
            true
        default:
            false
        }
    }
}

// MARK: - Модель токена

struct OAuthToken: Sendable {
    let accessToken: String
    let expiresAt: Date
}

// MARK: - Реализация

actor SberAuthService: AuthService {
    private let credentialProvider: @Sendable () -> (clientId: String, secret: String)?
    private let scope: String
    private let httpClient: HTTPClient
    private let tokenURL: URL

    private var cachedToken: OAuthToken?
    private var inFlightTask: Task<String, Error>?

    static let defaultTokenURL: URL = {
        guard let url = URL(string: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth") else {
            fatalError("Невалидный defaultTokenURL")
        }
        return url
    }()

    static let refreshMargin: TimeInterval = 5 * 60

    init(
        credentialProvider: @escaping @Sendable () -> (clientId: String, secret: String)?,
        scope: String = "GIGACHAT_API_PERS",
        httpClient: HTTPClient = URLSession.shared,
        tokenURL: URL? = nil
    ) {
        self.credentialProvider = credentialProvider
        self.scope = scope
        self.httpClient = httpClient
        self.tokenURL = tokenURL ?? Self.defaultTokenURL
    }

    func getAccessToken() async throws -> String {
        throw AuthError.credentialsNotFound
    }

    // MARK: - Private

    private func buildTokenRequest(
        clientId _: String,
        clientSecret _: String,
        scope _: String
    ) -> URLRequest {
        fatalError("Не реализовано")
    }

    private func parseTokenResponse(_: Data) throws -> OAuthToken {
        fatalError("Не реализовано")
    }

    private func isExpiringSoon(_: OAuthToken) -> Bool {
        fatalError("Не реализовано")
    }
}

// MARK: - Мок

final class MockAuthService: AuthService, @unchecked Sendable {
    private let lock = NSLock()
    var tokenResult: String?
    var tokenError: Error?
    private(set) var callCount = 0

    func getAccessToken() async throws -> String {
        lock.lock()
        callCount += 1
        lock.unlock()

        if let error = tokenError {
            throw error
        }
        return tokenResult ?? "mock-token"
    }
}
