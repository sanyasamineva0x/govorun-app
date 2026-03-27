@testable import Govorun
import XCTest

final class LocalLLMClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func test_normalize_sendsHealthcheckAndChatCompletion() async throws {
        let requests = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            await requests.append(request)

            if request.url?.path == "/v1/models" {
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":[{"id":"gigachat-gguf"}]}"#
                )
            }

            if request.url?.path == "/v1/chat/completions" {
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"choices":[{"message":{"content":"Привет."}}]}"#
                )
            }

            return HTTPStubResponse(statusCode: 404, body: "{}")
        }

        let client = makeClient()
        let output = try await client.normalize(
            "  ну привет  ",
            mode: .universal,
            hints: NormalizationHints(currentDate: makeDate())
        )

        XCTAssertEqual(output, "Привет.")
        let captured = await requests.snapshot()
        XCTAssertEqual(captured.map(\.url?.path), ["/v1/models", "/v1/chat/completions"])

        let chatRequest = try XCTUnwrap(captured.last)
        XCTAssertEqual(chatRequest.httpMethod, "POST")
        let body = try requestBodyData(from: chatRequest)
        let payload = try JSONDecoder().decode(ChatPayload.self, from: body)
        XCTAssertEqual(payload.model, "gigachat-gguf")
        XCTAssertEqual(payload.maxTokens, 128)
        XCTAssertEqual(payload.stop, ["\n\n"])
        XCTAssertEqual(payload.messages.count, 2)
        XCTAssertEqual(payload.messages[0].role, "system")
        XCTAssertTrue(payload.messages[0].content.contains("Сегодня:"))
        XCTAssertEqual(payload.messages[1].role, "user")
        XCTAssertEqual(payload.messages[1].content, "ну привет")
    }

    func test_normalize_throwsWhenConfiguredModelMissing() async {
        let requests = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            await requests.append(request)
            return HTTPStubResponse(
                statusCode: 200,
                body: #"{"data":[{"id":"other-model"}]}"#
            )
        }

        let client = makeClient()

        do {
            _ = try await client.normalize(
                "тест",
                mode: .universal,
                hints: NormalizationHints(currentDate: makeDate())
            )
            XCTFail("Ожидалась ошибка отсутствующей модели")
        } catch let error as LLMError {
            guard case .networkError(let message) = error else {
                return XCTFail("Ожидался .networkError, получен \(error)")
            }
            XCTAssertTrue(message.contains("gigachat-gguf"))
            XCTAssertTrue(message.contains("other-model"))
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }

        let captured = await requests.snapshot()
        XCTAssertEqual(captured.map(\.url?.path), ["/v1/models"])
    }

    func test_normalize_chatCompletionServerError() async {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/v1/models" {
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":[{"id":"gigachat-gguf"}]}"#
                )
            }

            return HTTPStubResponse(statusCode: 503, body: "{}")
        }

        let client = makeClient()

        do {
            _ = try await client.normalize(
                "тест",
                mode: .universal,
                hints: NormalizationHints(currentDate: makeDate())
            )
            XCTFail("Ожидалась server error")
        } catch let error as LLMError {
            XCTAssertEqual(error, .serverError(statusCode: 503))
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }
    }

    func test_normalize_chatCompletionMalformedJSON() async {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/v1/models" {
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":[{"id":"gigachat-gguf"}]}"#
                )
            }

            return HTTPStubResponse(statusCode: 200, body: #"{"choices":[]}"#)
        }

        let client = makeClient()

        do {
            _ = try await client.normalize(
                "тест",
                mode: .universal,
                hints: NormalizationHints(currentDate: makeDate())
            )
            XCTFail("Ожидалась parsing error")
        } catch let error as LLMError {
            XCTAssertEqual(error, .parsingFailed)
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }
    }

    func test_normalize_healthcheckBackoffSkipsSecondProbe() async {
        let requests = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            await requests.append(request)
            throw URLError(.cannotConnectToHost)
        }

        let client = makeClient(
            configuration: LocalLLMConfiguration(
                baseURLString: LocalLLMConfiguration.defaultBaseURLString,
                model: LocalLLMConfiguration.defaultModel,
                requestTimeout: 5,
                healthcheckTimeout: 0.5,
                healthcheckSuccessTTL: 30,
                failureCooldown: 60,
                maxOutputTokens: 64,
                temperature: 0
            )
        )

        await assertNormalizeFails(client: client)
        await assertNormalizeFails(client: client)

        let captured = await requests.snapshot()
        XCTAssertEqual(captured.count, 1, "Второй вызов должен упасть fail-fast без нового probe")
        XCTAssertEqual(captured.first?.url?.path, "/v1/models")
    }

    func test_normalize_emptyStopSequencesOmitsStopField() async throws {
        let requests = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            await requests.append(request)

            if request.url?.path == "/v1/models" {
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":[{"id":"gigachat-gguf"}]}"#
                )
            }

            return HTTPStubResponse(
                statusCode: 200,
                body: #"{"choices":[{"message":{"content":"Ок"}}]}"#
            )
        }

        let client = makeClient(
            configuration: LocalLLMConfiguration(stopSequences: [])
        )
        _ = try await client.normalize(
            "ок",
            mode: .universal,
            hints: NormalizationHints(currentDate: makeDate())
        )

        let captured = await requests.snapshot()
        let chatRequest = try XCTUnwrap(captured.last)
        let body = try requestBodyData(from: chatRequest)
        let payload = try JSONDecoder().decode(ChatPayload.self, from: body)
        XCTAssertNil(payload.stop, "Пустой stopSequences не должен сериализовать stop в JSON")
    }

    func test_normalize_usesContentPartsResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/v1/models" {
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":[{"id":"gigachat-gguf"}]}"#
                )
            }

            return HTTPStubResponse(
                statusCode: 200,
                body: #"{"choices":[{"message":{"content":[{"type":"output_text","text":"Привет"},{"type":"output_text","text":"."}]}}]}"#
            )
        }

        let client = makeClient()
        let output = try await client.normalize(
            "привет",
            mode: .universal,
            hints: NormalizationHints(currentDate: makeDate())
        )

        XCTAssertEqual(output, "Привет.")
    }

    func test_normalize_emptyText_returnsTrimmedEmptyString() async throws {
        let client = makeClient()
        let output = try await client.normalize(
            "   \n  ",
            mode: .universal,
            hints: NormalizationHints(currentDate: makeDate())
        )

        XCTAssertEqual(output, "")
    }

    func test_normalize_cancellationDoesNotPoisonHealthState() async throws {
        let requests = RequestRecorder()
        let chatCallCounter = CallCounter()

        MockURLProtocol.requestHandler = { request in
            await requests.append(request)

            if request.url?.path == "/v1/models" {
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":[{"id":"gigachat-gguf"}]}"#
                )
            }

            if await chatCallCounter.increment() == 1 {
                throw CancellationError()
            }

            return HTTPStubResponse(
                statusCode: 200,
                body: #"{"choices":[{"message":{"content":"Привет."}}]}"#
            )
        }

        let client = makeClient()

        do {
            _ = try await client.normalize(
                "привет",
                mode: .universal,
                hints: NormalizationHints(currentDate: makeDate())
            )
            XCTFail("Ожидалась отмена")
        } catch is CancellationError {
        } catch {
            XCTFail("Ожидался CancellationError, получен \(error)")
        }

        let secondOutput = try await client.normalize(
            "привет",
            mode: .universal,
            hints: NormalizationHints(currentDate: makeDate())
        )

        XCTAssertEqual(secondOutput, "Привет.")

        let captured = await requests.snapshot()
        XCTAssertEqual(captured.map(\.url?.path), ["/v1/models", "/v1/chat/completions", "/v1/chat/completions"])
    }

    func test_localLLMConfiguration_allowsZeroOverridesForTemperatureAndCooldowns() {
        let config = LocalLLMConfiguration.resolved(
            environment: [
                "GOVORUN_LLM_TEMPERATURE": "0",
                "GOVORUN_LLM_HEALTHCHECK_TTL": "0",
                "GOVORUN_LLM_FAILURE_COOLDOWN": "0",
            ]
        )

        XCTAssertEqual(config.temperature, 0)
        XCTAssertEqual(config.healthcheckSuccessTTL, 0)
        XCTAssertEqual(config.failureCooldown, 0)
    }

    func test_localLLMConfiguration_normalizesBaseURLAndModel() {
        let config = LocalLLMConfiguration(
            baseURLString: " http://127.0.0.1:8080/v1/// ",
            model: " gigachat-gguf "
        )

        XCTAssertEqual(config.normalizedBaseURL?.absoluteString, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(config.normalizedModel, "gigachat-gguf")
    }

    func test_localLLMConfiguration_invalidBaseURLReturnsNil() {
        let config = LocalLLMConfiguration(baseURLString: " localhost:8080 ")
        XCTAssertNil(config.normalizedBaseURL)
    }

    private func assertNormalizeFails(client: LocalLLMClient) async {
        do {
            _ = try await client.normalize(
                "тест",
                mode: .universal,
                hints: NormalizationHints(currentDate: makeDate())
            )
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertTrue(error is LLMError)
        }
    }

    private func makeClient(
        configuration: LocalLLMConfiguration = .resolved(environment: [:])
    ) -> LocalLLMClient {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        return LocalLLMClient(configuration: configuration, session: session)
    }

    private func makeDate() -> Date {
        Date(timeIntervalSince1970: 1_711_633_600)
    }

    private func requestBodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            throw NSError(domain: "LocalLLMClientTests", code: 1)
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                throw stream.streamError ?? NSError(domain: "LocalLLMClientTests", code: 2)
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }

        guard !data.isEmpty else {
            throw NSError(domain: "LocalLLMClientTests", code: 3)
        }

        return data
    }
}

private actor RequestRecorder {
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }

    func snapshot() -> [URLRequest] {
        requests
    }
}

private actor CallCounter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

private struct HTTPStubResponse {
    let statusCode: Int
    let body: String
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) async throws -> HTTPStubResponse)?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Task {
            do {
                let stub = try await handler(request)
                let response = try XCTUnwrap(
                    HTTPURLResponse(
                        url: request.url ?? URL(string: "http://127.0.0.1")!,
                        statusCode: stub.statusCode,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )
                )
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private struct ChatPayload: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let stop: [String]?
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case stop
        case messages
    }
}
