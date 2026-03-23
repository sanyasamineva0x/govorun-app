import XCTest
@testable import Govorun

final class LocalSTTClientTests: XCTestCase {

    // MARK: - parseResponse: успех

    func test_parseResponse_validText() throws {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        let result = try client.parseResponse(["text": "привет мир"])
        XCTAssertEqual(result.text, "привет мир")
        XCTAssertEqual(result.confidence, 1.0)
    }

    func test_parseResponse_emptyText() throws {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        let result = try client.parseResponse(["text": ""])
        XCTAssertEqual(result.text, "")
    }

    func test_parseResponse_unicodeText() throws {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        let text = "Здравствуйте, как дела? Всё хорошо!"
        let result = try client.parseResponse(["text": text])
        XCTAssertEqual(result.text, text)
    }

    // MARK: - parseResponse: ошибки worker

    func test_parseResponse_oomError() {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        XCTAssertThrowsError(try client.parseResponse([
            "error": "oom",
            "message": "Недостаточно памяти"
        ])) { error in
            guard let sttError = error as? STTError else {
                return XCTFail("Ожидался STTError, получен \(error)")
            }
            if case .recognitionFailed(let msg) = sttError {
                XCTAssertTrue(msg.contains("памяти"), "Сообщение: \(msg)")
            } else {
                XCTFail("Ожидался .recognitionFailed, получен \(sttError)")
            }
        }
    }

    func test_parseResponse_fileNotFoundError() {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        XCTAssertThrowsError(try client.parseResponse([
            "error": "file_not_found",
            "message": "Файл не найден: /tmp/govorun_xxx.wav"
        ])) { error in
            guard let sttError = error as? STTError,
                  case .recognitionFailed(let msg) = sttError else {
                return XCTFail("Ожидался STTError.recognitionFailed")
            }
            XCTAssertTrue(msg.contains("не найден"), "Сообщение: \(msg)")
        }
    }

    func test_parseResponse_internalError() {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        XCTAssertThrowsError(try client.parseResponse([
            "error": "internal",
            "message": "сегмент повреждён"
        ])) { error in
            guard let sttError = error as? STTError,
                  case .recognitionFailed(let msg) = sttError else {
                return XCTFail("Ожидался STTError.recognitionFailed")
            }
            XCTAssertEqual(msg, "сегмент повреждён")
        }
    }

    func test_parseResponse_unknownError() {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        XCTAssertThrowsError(try client.parseResponse([
            "error": "custom_error",
            "message": "что-то пошло не так"
        ])) { error in
            guard let sttError = error as? STTError,
                  case .recognitionFailed(let msg) = sttError else {
                return XCTFail("Ожидался STTError.recognitionFailed")
            }
            XCTAssertEqual(msg, "что-то пошло не так")
        }
    }

    func test_parseResponse_errorWithoutMessage() {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        XCTAssertThrowsError(try client.parseResponse([
            "error": "oom"
        ])) { error in
            // Должен использовать тип ошибки как fallback message
            guard let sttError = error as? STTError,
                  case .recognitionFailed = sttError else {
                return XCTFail("Ожидался STTError.recognitionFailed")
            }
        }
    }

    func test_parseResponse_missingText() {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        XCTAssertThrowsError(try client.parseResponse([
            "foo": "bar"
        ])) { error in
            guard let sttError = error as? STTError,
                  case .recognitionFailed(let msg) = sttError else {
                return XCTFail("Ожидался STTError.recognitionFailed")
            }
            XCTAssertTrue(msg.contains("text"), "Сообщение: \(msg)")
        }
    }

    // MARK: - saveWAVToTemp

    func test_saveWAVToTemp_createsFile() throws {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        let fakeWAV = Data(repeating: 0, count: 100)
        let path = try client.saveWAVToTemp(fakeWAV)

        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(path.hasSuffix(".wav"))
        XCTAssertTrue(path.contains("govorun_"))

        let saved = FileManager.default.contents(atPath: path)
        // saveWAVToTemp добавляет 44-байтный WAV заголовок
        XCTAssertEqual(saved?.count, fakeWAV.count + 44)
        // PCM данные идут после заголовка
        XCTAssertEqual(saved?.suffix(fakeWAV.count), fakeWAV)
    }

    func test_saveWAVToTemp_uniquePaths() throws {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        let data = Data(repeating: 0, count: 10)
        let path1 = try client.saveWAVToTemp(data)
        let path2 = try client.saveWAVToTemp(data)

        defer {
            try? FileManager.default.removeItem(atPath: path1)
            try? FileManager.default.removeItem(atPath: path2)
        }

        XCTAssertNotEqual(path1, path2, "Каждый вызов должен создавать уникальный файл")
    }

    // MARK: - estimateAudioDuration

    func test_estimateAudioDuration_1second() {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        // 16kHz * 2 bytes/sample * 1 sec = 32000 bytes (raw PCM, без заголовка)
        let data = Data(repeating: 0, count: 32_000)
        let duration = client.estimateAudioDuration(data)
        XCTAssertEqual(duration, 1.0, accuracy: 0.001)
    }

    func test_estimateAudioDuration_2minutes() {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        // 16kHz * 2 bytes/sample * 120 sec = 3840000 bytes (raw PCM)
        let data = Data(repeating: 0, count: 3_840_000)
        let duration = client.estimateAudioDuration(data)
        XCTAssertEqual(duration, 120.0, accuracy: 0.001)
    }

    func test_estimateAudioDuration_emptyData() {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        let data = Data()
        let duration = client.estimateAudioDuration(data)
        XCTAssertEqual(duration, 0.0, accuracy: 0.001)
    }

    func test_estimateAudioDuration_smallData() {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        // 44 bytes raw PCM = 22 samples = 0.001375 sec
        let data = Data(repeating: 0, count: 44)
        let duration = client.estimateAudioDuration(data)
        XCTAssertEqual(duration, 0.001375, accuracy: 0.0001)
    }

    // MARK: - recognize: пустое аудио

    func test_recognize_emptyAudio_returnsEmptyText() async throws {
        let client = LocalSTTClient(socketPath: "/tmp/test.sock")
        let result = try await client.recognize(audioData: Data(), hints: [])
        XCTAssertEqual(result.text, "")
    }

    // MARK: - recognize: connection refused (socket не существует)

    func test_recognize_connectionRefused_throwsError() async {
        let client = LocalSTTClient(socketPath: "/tmp/govorun_nonexistent_test.sock")
        let fakeWAV = Data(repeating: 0, count: 100)

        do {
            _ = try await client.recognize(audioData: fakeWAV, hints: [])
            XCTFail("Должен бросить ошибку")
        } catch let error as STTError {
            if case .connectionFailed(let msg) = error {
                XCTAssertTrue(msg.contains("Worker"), "Сообщение: \(msg)")
            } else {
                XCTFail("Ожидался .connectionFailed, получен \(error)")
            }
        } catch {
            XCTFail("Ожидался STTError, получен \(error)")
        }
    }

    // MARK: - IPC через реальный unix socket

    /// Утилита: создать мини-сервер на unix socket, вернуть FD
    private func makeTestServer(
        socketPath: String,
        responseJSON: String
    ) -> (serverFD: Int32, serverReady: DispatchSemaphore) {
        let serverFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        precondition(serverFD >= 0, "socket() failed")

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, byte) in pathBytes.enumerated() { dest[i] = byte }
            }
        }
        _ = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        Darwin.listen(serverFD, 1)

        let serverReady = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            serverReady.signal()
            let clientFD = Darwin.accept(serverFD, nil, nil)
            guard clientFD >= 0 else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            _ = Darwin.recv(clientFD, &buf, buf.count, 0)
            _ = responseJSON.withCString { ptr in
                Darwin.send(clientFD, ptr, strlen(ptr), 0)
            }
            Darwin.close(clientFD)
        }

        return (serverFD, serverReady)
    }

    func test_sendRequest_realSocket_ping() async throws {
        let socketPath = "/tmp/gvr_ipc_\(Int.random(in: 100000...999999)).sock"
        let (serverFD, ready) = makeTestServer(socketPath: socketPath, responseJSON: #"{"text":"тест"}"#)

        defer {
            Darwin.close(serverFD)
            unlink(socketPath)
        }

        ready.wait()
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = LocalSTTClient(socketPath: socketPath, timeout: 5.0)
        let response = try await client.sendRequest(["wav_path": "/tmp/test.wav"], timeout: 5.0)
        XCTAssertEqual(response["text"] as? String, "тест")
    }

    func test_sendRequest_realSocket_errorResponse() async throws {
        let socketPath = "/tmp/gvr_err_\(Int.random(in: 100000...999999)).sock"
        let (serverFD, ready) = makeTestServer(
            socketPath: socketPath,
            responseJSON: #"{"error":"oom","message":"Недостаточно памяти"}"#
        )

        defer {
            Darwin.close(serverFD)
            unlink(socketPath)
        }

        ready.wait()
        try await Task.sleep(nanoseconds: 10_000_000)

        let client = LocalSTTClient(socketPath: socketPath)
        let response = try await client.sendRequest(["wav_path": "/tmp/test.wav"], timeout: 5.0)

        XCTAssertThrowsError(try client.parseResponse(response)) { error in
            guard let sttError = error as? STTError,
                  case .recognitionFailed(let msg) = sttError else {
                return XCTFail("Ожидался STTError.recognitionFailed")
            }
            XCTAssertTrue(msg.contains("памяти"))
        }
    }

}
