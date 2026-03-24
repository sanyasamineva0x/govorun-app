import AVFoundation
@testable import Govorun
import XCTest

// MARK: - Мок AudioCapture для юнит-тестов

/// AVAudioEngine требует реальный микрофон — мокаем AudioRecording протокол
final class MockAudioCapture: AudioRecording {
    weak var delegate: AudioCaptureDelegate?

    private(set) var _isRecording = false
    private var _duration: TimeInterval = 0
    var _currentLevel: Float = 0
    private var _buffer = Data()
    private var recordingStartTime: Date?

    var startError: AudioCaptureError?
    var simulatedBufferData: Data?

    var isRecording: Bool {
        _isRecording
    }

    var duration: TimeInterval {
        guard let start = recordingStartTime else { return _duration }
        return Date().timeIntervalSince(start)
    }

    var currentLevel: Float {
        _currentLevel
    }

    func startRecording() throws {
        if let error = startError {
            throw error
        }
        _isRecording = true
        _buffer = Data()
        recordingStartTime = Date()
    }

    func stopRecording() -> Data {
        _isRecording = false
        let result = simulatedBufferData ?? _buffer
        recordingStartTime = nil
        delegate?.audioCaptureDidStop(self)
        return result
    }

    // Хелперы для симуляции

    func simulateLevelUpdate(_ level: Float) {
        _currentLevel = level
        delegate?.audioCapture(self, didUpdateLevel: level)
    }

    func simulateBufferGrowth(_ data: Data) {
        _buffer.append(data)
    }
}

// MARK: - Мок Delegate

final class MockAudioCaptureDelegate: AudioCaptureDelegate {
    var levels: [Float] = []
    var chunks: [Data] = []
    var didStopCalled = false
    var errors: [Error] = []

    func audioCapture(_ capture: any AudioRecording, didUpdateLevel level: Float) {
        levels.append(level)
    }

    func audioCapture(_ capture: any AudioRecording, didCaptureChunk chunk: Data) {
        chunks.append(chunk)
    }

    func audioCaptureDidStop(_ capture: any AudioRecording) {
        didStopCalled = true
    }

    func audioCapture(_ capture: any AudioRecording, didFailWithError error: Error) {
        errors.append(error)
    }
}

// MARK: - Тесты

final class AudioCaptureTests: XCTestCase {
    // MARK: - 1. Формат 16kHz mono

    func test_audio_format_16khz_mono() {
        let format = AudioCapture.outputFormat
        XCTAssertEqual(format.sampleRate, 16_000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.commonFormat, .pcmFormatInt16)
        XCTAssertTrue(format.isInterleaved)
    }

    // MARK: - 2. Metering обновляет delegate

    func test_metering_updates_delegate() {
        let capture = MockAudioCapture()
        let mockDelegate = MockAudioCaptureDelegate()
        capture.delegate = mockDelegate

        XCTAssertEqual(mockDelegate.levels.count, 0)

        capture.simulateLevelUpdate(0.5)
        XCTAssertEqual(mockDelegate.levels.count, 1)
        XCTAssertEqual(mockDelegate.levels.last, 0.5)

        capture.simulateLevelUpdate(0.8)
        XCTAssertEqual(mockDelegate.levels.count, 2)
        XCTAssertEqual(mockDelegate.levels.last, 0.8)
    }

    // MARK: - 3. Stop возвращает полный буфер

    func test_stop_returns_full_buffer() throws {
        let capture = MockAudioCapture()
        let testData = Data(repeating: 0xab, count: 1_600)
        capture.simulatedBufferData = testData

        try capture.startRecording()
        XCTAssertTrue(capture.isRecording)

        let result = capture.stopRecording()
        XCTAssertFalse(capture.isRecording)
        XCTAssertEqual(result.count, 1_600)
        XCTAssertEqual(result, testData)
    }

    // MARK: - 4. Start без разрешения выбрасывает ошибку

    func test_start_without_permission_throws() {
        let capture = MockAudioCapture()
        capture.startError = .permissionDenied

        XCTAssertThrowsError(try capture.startRecording()) { error in
            XCTAssertEqual(error as? AudioCaptureError, .permissionDenied)
        }
        XCTAssertFalse(capture.isRecording)
    }

    // MARK: - 5. Duration отслеживает время записи

    func test_duration_tracks_recording_time() throws {
        let capture = MockAudioCapture()
        XCTAssertEqual(capture.duration, 0)

        try capture.startRecording()
        // Небольшая пауза чтобы duration стал > 0
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertGreaterThan(capture.duration, 0)

        _ = capture.stopRecording()
        // После остановки duration сбрасывается (recordingStartTime = nil)
        XCTAssertEqual(capture.duration, 0)
    }

    // MARK: - 6. Буфер растёт во время записи

    func test_buffer_grows_during_recording() throws {
        let capture = MockAudioCapture()
        capture.simulatedBufferData = nil // не используем готовый буфер

        try capture.startRecording()

        // Симулируем добавление данных
        capture.simulateBufferGrowth(Data(repeating: 0x01, count: 100))
        capture.simulateBufferGrowth(Data(repeating: 0x02, count: 200))
        capture.simulateBufferGrowth(Data(repeating: 0x03, count: 300))

        let result = capture.stopRecording()
        // simulatedBufferData = nil, поэтому stopRecording вернёт _buffer
        XCTAssertEqual(result.count, 600)
    }

    // MARK: - Доп: RMS level вычисляется корректно

    func test_rms_level_normalization() throws {
        // Тишина → уровень ~0
        let silentFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let silentBuffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: silentFormat, frameCapacity: 100))
        silentBuffer.frameLength = 100
        // Заполняем нулями (тишина)
        try memset(XCTUnwrap(silentBuffer.floatChannelData?.pointee), 0, Int(silentBuffer.frameLength) * MemoryLayout<Float>.size)

        let silentLevel = silentBuffer.rmsLevel()
        XCTAssertEqual(silentLevel, 0, accuracy: 0.01)
    }

    // MARK: - Доп: AudioCaptureError equatable

    func test_outputFormat_isValid() {
        let format = AudioCapture.outputFormat
        XCTAssertEqual(format.sampleRate, 16_000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.commonFormat, .pcmFormatInt16)
        XCTAssertTrue(format.isInterleaved)
        // static let — тот же объект при повторном обращении
        XCTAssertTrue(format === AudioCapture.outputFormat)
    }

    func test_toData_emptyBuffer_returnsEmptyData() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 0))
        buffer.frameLength = 0
        let data = buffer.toData()
        XCTAssertTrue(data.isEmpty)
    }

    func test_error_types_are_distinct() {
        XCTAssertEqual(AudioCaptureError.microphoneNotAvailable, .microphoneNotAvailable)
        XCTAssertEqual(AudioCaptureError.permissionDenied, .permissionDenied)
        XCTAssertEqual(AudioCaptureError.alreadyRecording, .alreadyRecording)
        XCTAssertNotEqual(AudioCaptureError.microphoneNotAvailable, .permissionDenied)
        XCTAssertEqual(AudioCaptureError.engineStartFailed(underlying: "test"), .engineStartFailed(underlying: "test"))
        XCTAssertNotEqual(AudioCaptureError.engineStartFailed(underlying: "a"), .engineStartFailed(underlying: "b"))
    }
}
