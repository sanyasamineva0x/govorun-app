import AVFoundation

// MARK: - Ошибки

enum AudioCaptureError: Error, Equatable {
    case microphoneNotAvailable
    case permissionDenied
    case engineStartFailed(underlying: String)
    case alreadyRecording
    case notRecording

    static func == (lhs: AudioCaptureError, rhs: AudioCaptureError) -> Bool {
        switch (lhs, rhs) {
        case (.microphoneNotAvailable, .microphoneNotAvailable),
             (.permissionDenied, .permissionDenied),
             (.alreadyRecording, .alreadyRecording),
             (.notRecording, .notRecording):
            return true
        case (.engineStartFailed(let a), .engineStartFailed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Delegate

protocol AudioCaptureDelegate: AnyObject {
    func audioCapture(_ capture: any AudioRecording, didUpdateLevel level: Float)
    func audioCapture(_ capture: any AudioRecording, didCaptureChunk chunk: Data)
    func audioCaptureDidStop(_ capture: any AudioRecording)
    func audioCapture(_ capture: any AudioRecording, didFailWithError error: Error)
}

// MARK: - Протокол для DI

protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    var duration: TimeInterval { get }
    var currentLevel: Float { get }
    var delegate: AudioCaptureDelegate? { get set }
    func startRecording() throws
    func stopRecording() -> Data
}

// MARK: - Реализация

final class AudioCapture: AudioRecording {

    // Формат для ASR: PCM 16-bit, 16kHz, mono
    static let sampleRate: Double = 16_000
    static let channels: AVAudioChannelCount = 1
    static let bufferSize: AVAudioFrameCount = 1_600 // 100ms при 16kHz

    nonisolated(unsafe) static let outputFormat: AVAudioFormat = {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        ) else {
            fatalError("[AudioCapture] Не удалось создать AVAudioFormat PCM16/16kHz/mono — это баг")
        }
        return format
    }()

    weak var delegate: AudioCaptureDelegate?

    private let engine: AVAudioEngine
    private var audioBuffer = Data()
    private var recordingStartTime: Date?
    private var _isRecording = false
    private var _currentLevel: Float = 0
    private let lock = NSLock()

    var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRecording
    }

    var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let start = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var currentLevel: Float {
        lock.lock()
        defer { lock.unlock() }
        return _currentLevel
    }

    init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
    }

    func startRecording() throws {
        lock.lock()
        guard !_isRecording else {
            lock.unlock()
            throw AudioCaptureError.alreadyRecording
        }
        lock.unlock()

        // Проверяем наличие input node (микрофон)
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioCaptureError.microphoneNotAvailable
        }

        let outputFormat = Self.outputFormat

        // Конвертер если микрофон не в нужном формате
        let converter: AVAudioConverter?
        if inputFormat.sampleRate != outputFormat.sampleRate ||
           inputFormat.channelCount != outputFormat.channelCount {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        } else {
            converter = nil
        }

        lock.lock()
        audioBuffer = Data()
        recordingStartTime = Date()
        _isRecording = true
        lock.unlock()

        // Устанавливаем tap на input node
        inputNode.installTap(onBus: 0, bufferSize: Self.bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processBuffer(buffer, converter: converter, outputFormat: outputFormat)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            lock.lock()
            _isRecording = false
            recordingStartTime = nil
            lock.unlock()
            throw AudioCaptureError.engineStartFailed(underlying: error.localizedDescription)
        }
    }

    func stopRecording() -> Data {
        lock.lock()
        guard _isRecording else {
            lock.unlock()
            return Data()
        }
        // Сразу помечаем как не recording — предотвращает повторный вызов (TOCTOU)
        _isRecording = false
        let result = audioBuffer
        audioBuffer = Data()
        recordingStartTime = nil
        lock.unlock()

        // AVAudioEngine not thread-safe — вызываем после выхода из lock
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        delegate?.audioCaptureDidStop(self)
        return result
    }

    // MARK: - Private

    private func processBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, outputFormat: AVAudioFormat) {
        let pcmData: Data

        if let converter {
            // Конвертация в 16kHz mono
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
                return
            }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else {
                delegate?.audioCapture(self, didFailWithError: error ?? AudioCaptureError.microphoneNotAvailable)
                return
            }

            pcmData = convertedBuffer.toData()
        } else {
            pcmData = buffer.toData()
        }

        // RMS уровень для визуализации
        let level = buffer.rmsLevel()

        lock.lock()
        audioBuffer.append(pcmData)
        _currentLevel = level
        lock.unlock()

        delegate?.audioCapture(self, didCaptureChunk: pcmData)
        delegate?.audioCapture(self, didUpdateLevel: level)
    }
}

// MARK: - AVAudioPCMBuffer extensions

extension AVAudioPCMBuffer {
    func toData() -> Data {
        let audioBuffer = self.audioBufferList.pointee.mBuffers
        guard let mData = audioBuffer.mData else {
            print("[AudioCapture] mData is nil — повреждённый буфер, пропускаем")
            return Data()
        }
        return Data(bytes: mData, count: Int(audioBuffer.mDataByteSize))
    }

    func rmsLevel() -> Float {
        guard let channelData = floatChannelData else { return 0 }
        let channelDataValue = channelData.pointee
        let count = Int(frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<count {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(count))
        // Конвертируем в dB, нормализуем в 0...1
        let db = 20 * log10(max(rms, 0.000_001))
        // -60 dB → 0.0, 0 dB → 1.0
        return max(0, min(1, (db + 60) / 60))
    }
}
