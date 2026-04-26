import Foundation

// MARK: - Протокол

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// MARK: - URLSession

extension URLSession: HTTPClient {}

// MARK: - Мок

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    var result: (Data, URLResponse)?
    var error: Error?
    private(set) var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        requests.append(request)
        lock.unlock()

        if let error {
            throw error
        }

        if let result {
            return result
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://localhost")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response as URLResponse)
    }
}
