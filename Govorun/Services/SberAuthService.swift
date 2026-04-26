import Foundation

// MARK: - Протокол

protocol AuthService: Sendable {
    func getAccessToken() async throws -> String
}

// MARK: - Ошибки

enum AuthError: Error, Equatable {
    case credentialsNotFound
    case networkError(urlError: URLError?, description: String)
    case invalidResponse(statusCode: Int)
    case tokenParsingFailed

    static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        switch (lhs, rhs) {
        case (.credentialsNotFound, .credentialsNotFound):
            true
        case (.networkError(let ua, let da), .networkError(let ub, let db)):
            ua?.code == ub?.code && da == db
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
        if let token = cachedToken, !isExpiringSoon(token) {
            return token.accessToken
        }

        if let task = inFlightTask {
            return try await task.value
        }

        let task = Task<String, Error> {
            defer { self.inFlightTask = nil }

            guard let credentials = self.credentialProvider() else {
                throw AuthError.credentialsNotFound
            }

            let request = self.buildTokenRequest(
                clientId: credentials.clientId,
                clientSecret: credentials.secret,
                scope: self.scope
            )

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await self.httpClient.data(for: request)
            } catch {
                let urlErr = error as? URLError
                throw AuthError.networkError(
                    urlError: urlErr,
                    description: error.localizedDescription
                )
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse(statusCode: -1)
            }

            guard httpResponse.statusCode == 200 else {
                throw AuthError.invalidResponse(statusCode: httpResponse.statusCode)
            }

            let token = try self.parseTokenResponse(data)
            self.cachedToken = token
            return token.accessToken
        }
        inFlightTask = task
        return try await task.value
    }

    // MARK: - Private

    private func buildTokenRequest(
        clientId: String,
        clientSecret: String,
        scope: String
    ) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "RqUID")

        let authString = "\(clientId):\(clientSecret)"
        if let authData = authString.data(using: .utf8) {
            request.setValue(
                "Basic \(authData.base64EncodedString())",
                forHTTPHeaderField: "Authorization"
            )
        }

        request.httpBody = "scope=\(scope)".data(using: .utf8)
        return request
    }

    private func parseTokenResponse(_ data: Data) throws -> OAuthToken {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresAt = json["expires_at"] as? TimeInterval
        else {
            throw AuthError.tokenParsingFailed
        }

        let expiryDate = Date(timeIntervalSince1970: expiresAt / 1000.0)
        return OAuthToken(accessToken: accessToken, expiresAt: expiryDate)
    }

    private func isExpiringSoon(_ token: OAuthToken) -> Bool {
        token.expiresAt.timeIntervalSinceNow < Self.refreshMargin
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
