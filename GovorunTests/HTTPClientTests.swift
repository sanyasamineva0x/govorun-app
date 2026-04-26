@testable import Govorun
import XCTest

final class HTTPClientTests: XCTestCase {
    // MARK: - URLSession conformance

    func test_urlSession_conformsToHTTPClient() {
        let session: any HTTPClient = URLSession.shared
        XCTAssertNotNil(session)
    }

    // MARK: - MockHTTPClient

    func test_mock_returnsConfiguredResult() async throws {
        let mock = MockHTTPClient()
        let expectedData = Data("test".utf8)
        let expectedResponse = try XCTUnwrap(try HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://example.com")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        mock.result = (expectedData, expectedResponse)

        let request = try URLRequest(url: XCTUnwrap(URL(string: "https://example.com")))
        let (data, response) = try await mock.data(for: request)
        XCTAssertEqual(data, expectedData)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    func test_mock_throwsConfiguredError() async throws {
        let mock = MockHTTPClient()
        mock.error = URLError(.notConnectedToInternet)

        let request = try URLRequest(url: XCTUnwrap(URL(string: "https://example.com")))
        do {
            _ = try await mock.data(for: request)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func test_mock_tracksRequests() async throws {
        let mock = MockHTTPClient()
        let request1 = try URLRequest(url: XCTUnwrap(URL(string: "https://a.com")))
        let request2 = try URLRequest(url: XCTUnwrap(URL(string: "https://b.com")))

        _ = try await mock.data(for: request1)
        _ = try await mock.data(for: request2)

        XCTAssertEqual(mock.requests.count, 2)
        XCTAssertEqual(mock.requests[0].url?.absoluteString, "https://a.com")
        XCTAssertEqual(mock.requests[1].url?.absoluteString, "https://b.com")
    }

    func test_mock_defaultResult_returnsEmptyDataWith200() async throws {
        let mock = MockHTTPClient()
        let request = try URLRequest(url: XCTUnwrap(URL(string: "https://example.com")))
        let (data, response) = try await mock.data(for: request)
        XCTAssertTrue(data.isEmpty)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
