@testable import Govorun
import XCTest

final class CloudSettingsErrorMessageTests: XCTestCase {
    // MARK: - AuthError.credentialsNotFound

    func test_credentialsNotFound() {
        XCTAssertEqual(
            cloudErrorMessage(for: AuthError.credentialsNotFound),
            "Введите ключи API. Без них Cloud недоступен."
        )
    }

    // MARK: - AuthError.invalidResponse statusCode

    func test_invalidResponse_401() {
        XCTAssertEqual(
            cloudErrorMessage(for: AuthError.invalidResponse(statusCode: 401)),
            "Ключи отклонены Сбером. Проверьте Client ID и Secret."
        )
    }

    func test_invalidResponse_429() {
        XCTAssertEqual(
            cloudErrorMessage(for: AuthError.invalidResponse(statusCode: 429)),
            "Слишком много запросов. Попробуйте через минуту."
        )
    }

    func test_invalidResponse_5xx() {
        let expected = "Ошибка на стороне Сбера. Попробуйте позже."
        XCTAssertEqual(cloudErrorMessage(for: AuthError.invalidResponse(statusCode: 500)), expected)
        XCTAssertEqual(cloudErrorMessage(for: AuthError.invalidResponse(statusCode: 503)), expected)
        XCTAssertEqual(cloudErrorMessage(for: AuthError.invalidResponse(statusCode: 599)), expected)
    }

    func test_invalidResponse_other_and_parsingFailed() {
        let generic = "Сбой Cloud. Попробуйте позже."
        XCTAssertEqual(cloudErrorMessage(for: AuthError.invalidResponse(statusCode: 418)), generic)
        XCTAssertEqual(cloudErrorMessage(for: AuthError.invalidResponse(statusCode: -1)), generic)
        XCTAssertEqual(cloudErrorMessage(for: AuthError.tokenParsingFailed), generic)
    }

    // MARK: - AuthError.networkError URLError inspection

    func test_networkError_offline() {
        let expected = "Нет интернета. Cloud временно недоступен."
        XCTAssertEqual(
            cloudErrorMessage(for: AuthError.networkError(
                urlError: URLError(.notConnectedToInternet),
                description: "no internet"
            )),
            expected
        )
        XCTAssertEqual(
            cloudErrorMessage(for: AuthError.networkError(
                urlError: URLError(.networkConnectionLost),
                description: "connection lost"
            )),
            expected
        )
    }

    func test_networkError_timeout() {
        XCTAssertEqual(
            cloudErrorMessage(for: AuthError.networkError(
                urlError: URLError(.timedOut),
                description: "timed out"
            )),
            "Сбер не ответил за 30 секунд. Проверьте сеть."
        )
    }

    func test_networkError_generic() {
        let expected = "Сервис Сбера недоступен. Попробуйте позже."
        XCTAssertEqual(
            cloudErrorMessage(for: AuthError.networkError(
                urlError: URLError(.cannotFindHost),
                description: "cannot find host"
            )),
            expected
        )
        XCTAssertEqual(
            cloudErrorMessage(for: AuthError.networkError(
                urlError: nil,
                description: "unknown"
            )),
            expected
        )
    }

    // MARK: - Non-AuthError fallback

    func test_nonAuthError_fallback() {
        struct OtherError: Error {}
        XCTAssertEqual(
            cloudErrorMessage(for: OtherError()),
            "Сбой Cloud. Попробуйте позже."
        )
    }
}
