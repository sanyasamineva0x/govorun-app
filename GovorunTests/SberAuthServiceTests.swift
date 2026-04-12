import XCTest
@testable import Govorun

// MARK: - Хелпер

private func makeValidTokenResponse(
    token: String = "test-token",
    expiresInSeconds: TimeInterval = 1800
) -> (Data, URLResponse) {
    let expiresAtMs = (Date().timeIntervalSince1970 + expiresInSeconds) * 1000.0
    let json = """
    {"access_token": "\(token)", "expires_at": \(Int64(expiresAtMs))}
    """
    let data = Data(json.utf8)
    let response = HTTPURLResponse(
        url: URL(string: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    return (data, response as URLResponse)
}

// MARK: - Мок с задержкой (для теста coalescing)

private final class DelayMockHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    let wrapped: MockHTTPClient

    init(wrapped: MockHTTPClient) {
        self.wrapped = wrapped
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return wrapped.requests
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await Task.sleep(nanoseconds: 100_000_000)
        return try await wrapped.data(for: request)
    }
}

// MARK: - Тесты

final class SberAuthServiceTests: XCTestCase {
    private var mockHTTP: MockHTTPClient!
    private var sut: SberAuthService!

    private let testCredentials: (clientId: String, secret: String) = ("test-id", "test-secret")

    override func setUp() {
        super.setUp()
        mockHTTP = MockHTTPClient()
        sut = SberAuthService(
            credentialProvider: { [testCredentials] in testCredentials },
            httpClient: mockHTTP
        )
    }

    // MARK: - Успех

    func test_getAccessToken_success() async throws {
        mockHTTP.result = makeValidTokenResponse(token: "abc-123")
        let token = try await sut.getAccessToken()
        XCTAssertEqual(token, "abc-123")
    }

    // MARK: - Ошибки

    func test_getAccessToken_credentialsNotFound() async {
        let service = SberAuthService(
            credentialProvider: { nil },
            httpClient: mockHTTP
        )
        do {
            _ = try await service.getAccessToken()
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? AuthError, .credentialsNotFound)
        }
    }

    func test_getAccessToken_networkError() async {
        mockHTTP.error = URLError(.notConnectedToInternet)
        do {
            _ = try await sut.getAccessToken()
            XCTFail("Ожидалась ошибка")
        } catch {
            guard case .networkError = error as? AuthError else {
                XCTFail("Ожидался networkError, получен \(error)")
                return
            }
        }
    }

    func test_getAccessToken_invalidResponse_401() async {
        let response = HTTPURLResponse(
            url: URL(string: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        mockHTTP.result = (Data(), response as URLResponse)
        do {
            _ = try await sut.getAccessToken()
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidResponse(statusCode: 401))
        }
    }

    func test_getAccessToken_tokenParsingFailed() async {
        let badJSON = Data("not json".utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        mockHTTP.result = (badJSON, response as URLResponse)
        do {
            _ = try await sut.getAccessToken()
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? AuthError, .tokenParsingFailed)
        }
    }

    // MARK: - Кэш

    func test_cachedToken_returnedWithoutHTTPCall() async throws {
        mockHTTP.result = makeValidTokenResponse(token: "cached")
        _ = try await sut.getAccessToken()
        let second = try await sut.getAccessToken()
        XCTAssertEqual(second, "cached")
        XCTAssertEqual(mockHTTP.requests.count, 1)
    }

    func test_expiredToken_triggersNewFetch() async throws {
        mockHTTP.result = makeValidTokenResponse(token: "old", expiresInSeconds: -10)
        _ = try await sut.getAccessToken()

        mockHTTP.result = makeValidTokenResponse(token: "new", expiresInSeconds: 1800)
        let second = try await sut.getAccessToken()
        XCTAssertEqual(second, "new")
        XCTAssertEqual(mockHTTP.requests.count, 2)
    }

    // MARK: - Формат запроса

    func test_request_containsRqUIDHeader() async throws {
        mockHTTP.result = makeValidTokenResponse()
        _ = try await sut.getAccessToken()
        let rquid = mockHTTP.requests[0].value(forHTTPHeaderField: "RqUID")
        XCTAssertNotNil(rquid)
        // UUID формат: 8-4-4-4-12
        let uuidRegex = try NSRegularExpression(
            pattern: "^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$",
            options: .caseInsensitive
        )
        let range = NSRange(rquid!.startIndex ..< rquid!.endIndex, in: rquid!)
        XCTAssertNotNil(uuidRegex.firstMatch(in: rquid!, range: range))
    }

    func test_request_containsBasicAuth() async throws {
        mockHTTP.result = makeValidTokenResponse()
        _ = try await sut.getAccessToken()
        let auth = mockHTTP.requests[0].value(forHTTPHeaderField: "Authorization")
        XCTAssertNotNil(auth)
        XCTAssertTrue(auth!.hasPrefix("Basic "))
    }

    func test_request_containsCorrectBody() async throws {
        mockHTTP.result = makeValidTokenResponse()
        _ = try await sut.getAccessToken()
        let body = mockHTTP.requests[0].httpBody.flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(body, "scope=GIGACHAT_API_PERS")
    }

    func test_request_method_isPOST() async throws {
        mockHTTP.result = makeValidTokenResponse()
        _ = try await sut.getAccessToken()
        XCTAssertEqual(mockHTTP.requests[0].httpMethod, "POST")
    }

    func test_request_contentType() async throws {
        mockHTTP.result = makeValidTokenResponse()
        _ = try await sut.getAccessToken()
        let contentType = mockHTTP.requests[0].value(forHTTPHeaderField: "Content-Type")
        XCTAssertEqual(contentType, "application/x-www-form-urlencoded")
    }

    // MARK: - Coalescing

    func test_concurrent_calls_coalesce() async throws {
        let innerMock = MockHTTPClient()
        innerMock.result = makeValidTokenResponse(token: "shared")
        let delayMock = DelayMockHTTPClient(wrapped: innerMock)

        let service = SberAuthService(
            credentialProvider: { [testCredentials] in testCredentials },
            httpClient: delayMock
        )

        async let t1 = service.getAccessToken()
        async let t2 = service.getAccessToken()
        async let t3 = service.getAccessToken()

        let results = try await [t1, t2, t3]
        XCTAssertTrue(results.allSatisfy { $0 == "shared" })
        XCTAssertEqual(delayMock.requests.count, 1)
    }

    // MARK: - Equatable

    func test_authError_equatable() {
        XCTAssertEqual(AuthError.credentialsNotFound, AuthError.credentialsNotFound)
        XCTAssertEqual(AuthError.networkError("a"), AuthError.networkError("a"))
        XCTAssertNotEqual(AuthError.networkError("a"), AuthError.networkError("b"))
        XCTAssertEqual(AuthError.invalidResponse(statusCode: 401), AuthError.invalidResponse(statusCode: 401))
        XCTAssertNotEqual(AuthError.invalidResponse(statusCode: 401), AuthError.invalidResponse(statusCode: 500))
        XCTAssertEqual(AuthError.tokenParsingFailed, AuthError.tokenParsingFailed)
        XCTAssertNotEqual(AuthError.credentialsNotFound, AuthError.tokenParsingFailed)
    }

    // MARK: - Кастомные параметры

    func test_customTokenURL() async throws {
        let customURL = URL(string: "https://custom.api.example.com/oauth")!
        let service = SberAuthService(
            credentialProvider: { [testCredentials] in testCredentials },
            httpClient: mockHTTP,
            tokenURL: customURL
        )
        mockHTTP.result = makeValidTokenResponse()
        _ = try await service.getAccessToken()
        XCTAssertEqual(mockHTTP.requests[0].url, customURL)
    }

    func test_customScope() async throws {
        let service = SberAuthService(
            credentialProvider: { [testCredentials] in testCredentials },
            scope: "CUSTOM_SCOPE",
            httpClient: mockHTTP
        )
        mockHTTP.result = makeValidTokenResponse()
        _ = try await service.getAccessToken()
        let body = mockHTTP.requests[0].httpBody.flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(body, "scope=CUSTOM_SCOPE")
    }
}
