@testable import Govorun
import XCTest

// MARK: - Мок с последовательными ответами

private final class SequentialMockHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    var responses: [(Data, URLResponse)] = []
    var errors: [Error?] = []
    private(set) var requests: [URLRequest] = []
    private var callIndex = 0

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        requests.append(request)
        let index = callIndex
        callIndex += 1
        lock.unlock()

        if index < errors.count, let error = errors[index] {
            throw error
        }
        guard index < responses.count else {
            fatalError("SequentialMockHTTPClient: нет ответа для вызова \(index)")
        }
        return responses[index]
    }
}

// MARK: - Тесты

final class CloudLLMClientTests: XCTestCase {
    private let testDate = Date(timeIntervalSince1970: 1_711_633_600)

    private func makeHints() -> NormalizationHints {
        NormalizationHints(currentDate: testDate)
    }

    private func makeUploadResponse(fileId: String = "test-file-id") -> (Data, URLResponse) {
        let json = """
        {"id":"\(fileId)","object":"file","bytes":1234,"created_at":1710000000,"filename":"audio.wav","purpose":"general"}
        """
        let response = HTTPURLResponse(
            url: URL(string: "https://gigachat.devices.sberbank.ru/api/v1/files")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(json.utf8), response as URLResponse)
    }

    private func makeCompletionResponse(content: String = "Normalized text") -> (Data, URLResponse) {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"\(content)"},"index":0,"finish_reason":"stop"}],"model":"GigaChat-2-Max","usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15},"object":"chat.completion"}
        """
        let response = HTTPURLResponse(
            url: URL(string: "https://gigachat.devices.sberbank.ru/api/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(json.utf8), response as URLResponse)
    }

    private func makeErrorResponse(statusCode: Int, url: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response as URLResponse)
    }

    private func makeClient(
        authService: AuthService? = nil,
        httpClient: HTTPClient? = nil,
        configuration: CloudLLMConfiguration = CloudLLMConfiguration()
    ) -> CloudLLMClient {
        let auth = authService ?? {
            let mock = MockAuthService()
            mock.tokenResult = "mock-token"
            return mock
        }()
        let http = httpClient ?? MockHTTPClient()
        return CloudLLMClient(
            authService: auth,
            httpClient: http,
            configuration: configuration
        )
    }

    // MARK: - CLOUD-01: WAV upload via /files

    func test_processAudio_uploadsWAVFile() async throws {
        let mockHTTP = SequentialMockHTTPClient()
        mockHTTP.responses = [
            makeUploadResponse(),
            makeCompletionResponse(),
        ]
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        let audioData = Data([0x52, 0x49, 0x46, 0x46])
        _ = try await client.processAudio(
            audioData: audioData,
            superStyle: .normal,
            hints: makeHints()
        )

        let uploadRequest = mockHTTP.requests[0]
        XCTAssertEqual(uploadRequest.url?.path, "/api/v1/files")
        XCTAssertEqual(uploadRequest.httpMethod, "POST")

        let contentType = try XCTUnwrap(uploadRequest.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))

        let auth = try XCTUnwrap(uploadRequest.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(auth, "Bearer mock-token")

        let body = try XCTUnwrap(uploadRequest.httpBody)
        // isoLatin1 всегда декодирует любые байты 1:1, не теряя ASCII-delimiters
        // из multipart (в отличие от .utf8, который вернёт nil на binary WAV-header).
        let bodyString = String(data: body, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(bodyString.contains("audio.wav"), "Body должен содержать filename audio.wav")
        XCTAssertTrue(bodyString.contains("purpose"), "Body должен содержать поле purpose")
        XCTAssertTrue(bodyString.contains("general"), "Body должен содержать значение general")

        // WAV-обёртка должна присутствовать: RIFF header + исходный PCM внутри data chunk.
        XCTAssertTrue(bodyString.contains("RIFF"), "Body должен содержать WAV RIFF header")
        XCTAssertTrue(bodyString.contains("WAVE"), "Body должен содержать WAV WAVE marker")
        let audioRange = body.range(of: audioData)
        XCTAssertNotNil(audioRange, "PCM байты должны присутствовать внутри WAV data chunk")
    }

    // MARK: - CLOUD-02: chat/completions с attachment

    func test_processAudio_callsCompletionsWithAttachment() async throws {
        let mockHTTP = SequentialMockHTTPClient()
        mockHTTP.responses = [
            makeUploadResponse(fileId: "test-file-id"),
            makeCompletionResponse(),
        ]
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        _ = try await client.processAudio(
            audioData: Data([0x00]),
            superStyle: .normal,
            hints: makeHints()
        )

        let completionRequest = mockHTTP.requests[1]
        XCTAssertEqual(completionRequest.url?.path, "/api/v1/chat/completions")
        XCTAssertEqual(completionRequest.httpMethod, "POST")
        XCTAssertEqual(
            completionRequest.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        XCTAssertEqual(
            completionRequest.value(forHTTPHeaderField: "Authorization"),
            "Bearer mock-token"
        )

        let body = try XCTUnwrap(completionRequest.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(json["model"] as? String, "GigaChat-2-Max")

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")

        let systemContent = try XCTUnwrap(messages[0]["content"] as? String)
        let expectedPrompt = SuperTextStyle.normal.systemPrompt(currentDate: testDate)
        XCTAssertEqual(systemContent, expectedPrompt)

        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "")

        let attachments = try XCTUnwrap(messages[1]["attachments"] as? [String])
        XCTAssertEqual(attachments, ["test-file-id"])
    }

    // MARK: - CLOUD-03: извлечение текста из ответа

    func test_processAudio_extractsResponseText() async throws {
        let mockHTTP = SequentialMockHTTPClient()
        mockHTTP.responses = [
            makeUploadResponse(fileId: "file-123"),
            makeCompletionResponse(content: "Normalized text"),
        ]
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        let result = try await client.processAudio(
            audioData: Data([0x00]),
            superStyle: .normal,
            hints: makeHints()
        )

        XCTAssertEqual(result, "Normalized text")
    }

    func test_processAudio_trimsResponseWhitespace() async throws {
        let mockHTTP = SequentialMockHTTPClient()
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"  Trimmed  "},"index":0,"finish_reason":"stop"}],"model":"GigaChat-2-Max","usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15},"object":"chat.completion"}
        """
        let response = try XCTUnwrap(try HTTPURLResponse(
            url: XCTUnwrap(URL(string: "https://gigachat.devices.sberbank.ru/api/v1/chat/completions")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        mockHTTP.responses = [
            makeUploadResponse(),
            (Data(json.utf8), response as URLResponse),
        ]
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        let result = try await client.processAudio(
            audioData: Data([0x00]),
            superStyle: .normal,
            hints: makeHints()
        )

        XCTAssertEqual(result, "Trimmed")
    }

    // MARK: - CLOUD-06: timeout + retry

    func test_processAudio_retriesOnServerError() async throws {
        let mockHTTP = SequentialMockHTTPClient()
        mockHTTP.responses = [
            makeUploadResponse(),
            makeErrorResponse(
                statusCode: 500,
                url: "https://gigachat.devices.sberbank.ru/api/v1/chat/completions"
            ),
            makeCompletionResponse(content: "Success after retry"),
        ]
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration(retryDelay: 0.01)
        )

        let result = try await client.processAudio(
            audioData: Data([0x00]),
            superStyle: .normal,
            hints: makeHints()
        )

        XCTAssertEqual(result, "Success after retry")
        XCTAssertEqual(mockHTTP.requests.count, 3, "1 upload + 1 failed completions + 1 retry completions")
    }

    func test_processAudio_retriesOnRateLimited() async throws {
        let mockHTTP = SequentialMockHTTPClient()
        mockHTTP.responses = [
            makeUploadResponse(),
            makeErrorResponse(
                statusCode: 429,
                url: "https://gigachat.devices.sberbank.ru/api/v1/chat/completions"
            ),
            makeCompletionResponse(content: "Success after 429"),
        ]
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration(retryDelay: 0.01)
        )

        let result = try await client.processAudio(
            audioData: Data([0x00]),
            superStyle: .normal,
            hints: makeHints()
        )

        XCTAssertEqual(result, "Success after 429")
        XCTAssertEqual(mockHTTP.requests.count, 3)
    }

    func test_processAudio_doesNotRetryUploadError() async throws {
        let mockHTTP = SequentialMockHTTPClient()
        mockHTTP.responses = [
            makeErrorResponse(
                statusCode: 500,
                url: "https://gigachat.devices.sberbank.ru/api/v1/files"
            ),
        ]
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        do {
            _ = try await client.processAudio(
                audioData: Data([0x00]),
                superStyle: .normal,
                hints: makeHints()
            )
            XCTFail("Ожидалась ошибка сервера")
        } catch let error as LLMError {
            XCTAssertEqual(error, .serverError(statusCode: 500))
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }

        XCTAssertEqual(mockHTTP.requests.count, 1, "Upload не должен retry")
    }

    func test_processAudio_doesNotRetryNonRetryableError() async throws {
        let mockHTTP = SequentialMockHTTPClient()
        mockHTTP.responses = [
            makeUploadResponse(),
            makeErrorResponse(
                statusCode: 400,
                url: "https://gigachat.devices.sberbank.ru/api/v1/chat/completions"
            ),
        ]
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        do {
            _ = try await client.processAudio(
                audioData: Data([0x00]),
                superStyle: .normal,
                hints: makeHints()
            )
            XCTFail("Ожидалась ошибка")
        } catch let error as LLMError {
            XCTAssertEqual(error, .invalidResponse(statusCode: 400))
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }

        XCTAssertEqual(mockHTTP.requests.count, 2, "Нет retry для 400")
    }

    // MARK: - D-07: маппинг AuthError

    func test_processAudio_mapsCredentialsNotFound() async throws {
        let mockAuth = MockAuthService()
        mockAuth.tokenError = AuthError.credentialsNotFound
        let mockHTTP = MockHTTPClient()

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        do {
            _ = try await client.processAudio(
                audioData: Data([0x00]),
                superStyle: .normal,
                hints: makeHints()
            )
            XCTFail("Ожидалась ошибка")
        } catch let error as LLMError {
            XCTAssertEqual(error, .networkError("Cloud credentials not configured"))
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }
    }

    func test_processAudio_mapsAuthNetworkError() async throws {
        let mockAuth = MockAuthService()
        mockAuth.tokenError = AuthError.networkError(urlError: nil, description: "timeout")
        let mockHTTP = MockHTTPClient()

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        do {
            _ = try await client.processAudio(
                audioData: Data([0x00]),
                superStyle: .normal,
                hints: makeHints()
            )
            XCTFail("Ожидалась ошибка")
        } catch let error as LLMError {
            XCTAssertEqual(error, .networkError("timeout"))
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }
    }

    func test_processAudio_mapsAuthInvalidResponse() async throws {
        let mockAuth = MockAuthService()
        mockAuth.tokenError = AuthError.invalidResponse(statusCode: 401)
        let mockHTTP = MockHTTPClient()

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        do {
            _ = try await client.processAudio(
                audioData: Data([0x00]),
                superStyle: .normal,
                hints: makeHints()
            )
            XCTFail("Ожидалась ошибка")
        } catch let error as LLMError {
            XCTAssertEqual(error, .invalidResponse(statusCode: 401))
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }
    }

    func test_processAudio_mapsTokenParsingFailed() async throws {
        let mockAuth = MockAuthService()
        mockAuth.tokenError = AuthError.tokenParsingFailed
        let mockHTTP = MockHTTPClient()

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        do {
            _ = try await client.processAudio(
                audioData: Data([0x00]),
                superStyle: .normal,
                hints: makeHints()
            )
            XCTFail("Ожидалась ошибка")
        } catch let error as LLMError {
            XCTAssertEqual(error, .parsingFailed)
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }
    }

    // MARK: - normalize (LLMClient conformance)

    func test_normalize_sendsTextOnlyChatCompletion() async throws {
        let mockHTTP = MockHTTPClient()
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"

        mockHTTP.result = makeCompletionResponse(content: "Привет")

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        let result = try await client.normalize(
            "  ну привет  ",
            superStyle: .normal,
            hints: makeHints()
        )

        XCTAssertEqual(result, "Привет")
        XCTAssertEqual(mockHTTP.requests.count, 1)

        let request = mockHTTP.requests[0]
        XCTAssertEqual(request.url?.path, "/api/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer mock-token"
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[1]["content"] as? String, "ну привет")
        XCTAssertNil(messages[1]["attachments"], "Text-only путь не должен иметь attachments")
    }

    func test_normalize_emptyTextReturnsEmpty() async throws {
        let mockAuth = MockAuthService()
        let mockHTTP = MockHTTPClient()

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        let result = try await client.normalize(
            "   \n  ",
            superStyle: .normal,
            hints: makeHints()
        )

        XCTAssertEqual(result, "")
        XCTAssertEqual(mockHTTP.requests.count, 0, "Пустой текст не должен вызывать HTTP запросы")
    }

    // MARK: - CancellationError

    func test_processAudio_propagatesCancellation() async throws {
        let mockHTTP = SequentialMockHTTPClient()
        mockHTTP.errors = [CancellationError()]
        mockHTTP.responses = [makeUploadResponse()]
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration()
        )

        do {
            _ = try await client.processAudio(
                audioData: Data([0x00]),
                superStyle: .normal,
                hints: makeHints()
            )
            XCTFail("Ожидалась отмена")
        } catch is CancellationError {
            // OK
        } catch {
            XCTFail("Ожидался CancellationError, получен \(error)")
        }
    }

    // MARK: - CloudLLMConfiguration

    func test_defaultConfiguration() {
        let config = CloudLLMConfiguration()
        XCTAssertEqual(config.baseURLString, "https://gigachat.devices.sberbank.ru/api/v1")
        XCTAssertEqual(config.model, "GigaChat-2-Max")
        XCTAssertEqual(config.temperature, 0.1)
        XCTAssertEqual(config.requestTimeout, 30.0)
        XCTAssertEqual(config.retryDelay, 0.5)
        XCTAssertEqual(config.maxOutputTokens, 128)
    }

    func test_configurationClampsNegativeTimeout() {
        let config = CloudLLMConfiguration(requestTimeout: -1)
        XCTAssertEqual(config.requestTimeout, 0.1)
    }

    // MARK: - isRetryable

    func test_isRetryable_rateLimited() {
        XCTAssertTrue(LLMError.rateLimited.isRetryable)
    }

    func test_isRetryable_serverError() {
        XCTAssertTrue(LLMError.serverError(statusCode: 500).isRetryable)
    }

    func test_isRetryable_timeout() {
        XCTAssertTrue(LLMError.timeout.isRetryable)
    }

    func test_isRetryable_networkError() {
        XCTAssertFalse(LLMError.networkError("x").isRetryable)
    }

    func test_isRetryable_parsingFailed() {
        XCTAssertFalse(LLMError.parsingFailed.isRetryable)
    }

    // MARK: - H-01: guard против некорректного baseURLString

    func test_processAudio_throwsNetworkError_whenBaseURLInvalid() async throws {
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"
        let mockHTTP = MockHTTPClient()

        // "http://[invalid" — незакрытая скобка IPv6, URL(string:) возвращает nil
        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration(baseURLString: "http://[invalid")
        )

        do {
            _ = try await client.processAudio(
                audioData: Data([0x00]),
                superStyle: .normal,
                hints: makeHints()
            )
            XCTFail("Ожидалась networkError при некорректном baseURLString")
        } catch let error as LLMError {
            guard case .networkError = error else {
                XCTFail("Ожидался .networkError, получен \(error)")
                return
            }
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }
    }

    func test_normalize_throwsNetworkError_whenBaseURLInvalid() async throws {
        let mockAuth = MockAuthService()
        mockAuth.tokenResult = "mock-token"
        let mockHTTP = MockHTTPClient()

        let client = CloudLLMClient(
            authService: mockAuth,
            httpClient: mockHTTP,
            configuration: CloudLLMConfiguration(baseURLString: "http://[invalid")
        )

        do {
            _ = try await client.normalize(
                "тест",
                superStyle: .normal,
                hints: makeHints()
            )
            XCTFail("Ожидалась networkError при некорректном baseURLString")
        } catch let error as LLMError {
            guard case .networkError = error else {
                XCTFail("Ожидался .networkError, получен \(error)")
                return
            }
        } catch {
            XCTFail("Ожидался LLMError, получен \(error)")
        }
    }
}
