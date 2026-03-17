import Foundation

/// STTClient через unix socket к Python worker.
///
/// Протокол IPC:
///   Запрос:  {"wav_path": "/tmp/govorun_xxx.wav"}
///   Ответ:   {"text": "распознанный текст"}
///   Ошибка:  {"error": "oom|file_not_found|internal", "message": "..."}
///
/// Один request за connection. Streaming не поддерживается.
final class LocalSTTClient: STTClient, Sendable {

    private let socketPath: String
    private let baseTimeoutSec: TimeInterval
    private let secsPerAudioChunk: TimeInterval

    /// - Parameters:
    ///   - socketPath: путь к unix socket worker'а
    ///   - baseTimeoutSec: базовый таймаут (5 сек)
    ///   - secsPerAudioChunk: доп. время на каждые 30 сек аудио (1 сек)
    init(
        socketPath: String? = nil,
        baseTimeoutSec: TimeInterval = 5.0,
        secsPerAudioChunk: TimeInterval = 1.0
    ) {
        self.socketPath = socketPath
            ?? NSString("~/.govorun/worker.sock").expandingTildeInPath
        self.baseTimeoutSec = baseTimeoutSec
        self.secsPerAudioChunk = secsPerAudioChunk
    }

    func recognize(audioData: Data, hints: [String]) async throws -> STTResult {
        guard !audioData.isEmpty else {
            return STTResult(text: "", confidence: 1.0)
        }

        // 1. Сохранить audioData как WAV в tmp
        let wavPath = try saveWAVToTemp(audioData)

        defer {
            try? FileManager.default.removeItem(atPath: wavPath)
        }

        // 2. Рассчитать таймаут: 5 сек + 1 сек на каждые 30 сек аудио
        let audioDurationSec = estimateAudioDuration(audioData)
        let timeout = baseTimeoutSec + (audioDurationSec / 30.0) * secsPerAudioChunk

        // 3. Отправить запрос worker'у через unix socket
        let request: [String: Any] = ["wav_path": wavPath]
        let response = try await sendRequest(request, timeout: timeout)

        // 4. Парсить ответ
        return try parseResponse(response)
    }

    // MARK: - IPC

    /// Отправить JSON через unix socket и получить ответ
    func sendRequest(_ request: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        let requestData = try JSONSerialization.data(withJSONObject: request)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { [socketPath] in
                // Создать unix socket
                let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    continuation.resume(throwing: STTError.connectionFailed("Worker не запущен"))
                    return
                }

                defer { Darwin.close(fd) }

                // Установить таймаут на send/recv
                var tv = timeval(
                    tv_sec: Int(timeout),
                    tv_usec: Int32((timeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
                )
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                // Подключиться к unix socket
                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                let pathBytes = socketPath.utf8CString
                guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
                    continuation.resume(throwing: STTError.connectionFailed("Socket path слишком длинный"))
                    return
                }
                withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                        for (i, byte) in pathBytes.enumerated() {
                            dest[i] = byte
                        }
                    }
                }

                let connectResult = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }

                guard connectResult == 0 else {
                    let errMsg = String(cString: strerror(errno))
                    continuation.resume(throwing: STTError.connectionFailed("Worker не доступен: \(errMsg)"))
                    return
                }

                // Отправить запрос
                let sent = requestData.withUnsafeBytes { buf in
                    Darwin.send(fd, buf.baseAddress!, buf.count, 0)
                }
                guard sent == requestData.count else {
                    continuation.resume(throwing: STTError.connectionFailed("Ошибка отправки запроса"))
                    return
                }

                // Сигнал worker'у что отправка завершена (recv loop увидит EOF)
                Darwin.shutdown(fd, SHUT_WR)

                // Прочитать ответ
                var responseData = Data()
                let bufferSize = 65536
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }

                while true {
                    let bytesRead = Darwin.recv(fd, buffer, bufferSize, 0)
                    if bytesRead > 0 {
                        responseData.append(buffer, count: bytesRead)
                    } else if bytesRead == 0 {
                        break // connection closed
                    } else {
                        if errno == EAGAIN || errno == EWOULDBLOCK {
                            continuation.resume(throwing: STTError.connectionFailed("Worker не отвечает (таймаут)"))
                        } else {
                            let errMsg = String(cString: strerror(errno))
                            continuation.resume(throwing: STTError.connectionFailed("Ошибка чтения: \(errMsg)"))
                        }
                        return
                    }
                }

                guard !responseData.isEmpty else {
                    continuation.resume(throwing: STTError.connectionFailed("Пустой ответ от worker"))
                    return
                }

                // Парсить JSON
                do {
                    guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                        continuation.resume(throwing: STTError.recognitionFailed("Неверный формат ответа"))
                        return
                    }
                    continuation.resume(returning: json)
                } catch {
                    continuation.resume(throwing: STTError.recognitionFailed("Ошибка парсинга JSON: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - Parsing

    /// Парсить ответ worker'а: {"text": "..."} или {"error": "..."}
    func parseResponse(_ response: [String: Any]) throws -> STTResult {
        // Ошибка от worker
        if let errorType = response["error"] as? String {
            let message = response["message"] as? String ?? errorType
            switch errorType {
            case "oom":
                throw STTError.recognitionFailed("Недостаточно памяти для распознавания")
            case "file_not_found":
                throw STTError.recognitionFailed("WAV файл не найден")
            default:
                throw STTError.recognitionFailed(message)
            }
        }

        // Успех
        guard let text = response["text"] as? String else {
            throw STTError.recognitionFailed("Ответ worker не содержит text")
        }

        return STTResult(text: text, confidence: 1.0)
    }

    // MARK: - WAV

    /// Сохранить сырые PCM данные как WAV во временный файл
    /// AudioCapture отдаёт raw PCM Int16 16kHz mono — нужен WAV-заголовок
    func saveWAVToTemp(_ audioData: Data) throws -> String {
        let tmpDir = NSTemporaryDirectory()
        let fileName = "govorun_\(UUID().uuidString).wav"
        let path = (tmpDir as NSString).appendingPathComponent(fileName)

        let wavData = Self.addWAVHeader(to: audioData)
        guard FileManager.default.createFile(atPath: path, contents: wavData) else {
            throw STTError.recognitionFailed("Не удалось создать временный WAV файл")
        }

        return path
    }

    /// Добавить 44-байтный WAV-заголовок к сырым PCM данным
    /// Формат: PCM 16-bit, 16kHz, mono (совпадает с AudioCapture.outputFormat)
    static func addWAVHeader(to pcmData: Data, sampleRate: Int = 16000, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        let dataSize = UInt32(pcmData.count)
        let fileSize = dataSize + 36
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        let blockAlign = UInt16(channels * bitsPerSample / 8)

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        header.append(pcmData)
        return header
    }

    /// Оценить длительность аудио (16kHz, 16-bit, mono)
    /// audioData — сырой PCM из AudioCapture, без WAV-заголовка
    func estimateAudioDuration(_ audioData: Data) -> TimeInterval {
        let bytesPerSample = 2
        let sampleRate = 16000
        let samples = audioData.count / bytesPerSample
        return TimeInterval(samples) / TimeInterval(sampleRate)
    }
}
