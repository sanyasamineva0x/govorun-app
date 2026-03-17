import XCTest
@testable import Govorun

// MARK: - MockSoundPlayer

final class MockSoundPlayer: SoundPlaying {
    private(set) var playedEvents: [SoundEvent] = []

    func play(_ event: SoundEvent) {
        playedEvents.append(event)
    }
}

// MARK: - SoundManager Tests

final class SoundManagerTests: XCTestCase {

    func test_muteSoundPlayer_doesNotCrash() {
        let mute = MuteSoundPlayer()
        mute.play(.recordingStarted)
        mute.play(.recordingFinished)
        mute.play(.error)
    }

    func test_mockSoundPlayer_tracksEvents() {
        let mock = MockSoundPlayer()
        mock.play(.recordingStarted)
        mock.play(.recordingFinished)
        mock.play(.error)

        XCTAssertEqual(mock.playedEvents, [.recordingStarted, .recordingFinished, .error])
    }

    func test_soundEvent_rawValues() {
        XCTAssertEqual(SoundEvent.recordingStarted.rawValue, "recordingStarted")
        XCTAssertEqual(SoundEvent.recordingFinished.rawValue, "recordingFinished")
        XCTAssertEqual(SoundEvent.error.rawValue, "error")
    }
}

// MARK: - ErrorMessages Tests

final class ErrorMessagesTests: XCTestCase {

    // MARK: - URLError

    func test_urlError_noInternet_returnsRussianMessage() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Нет интернета")
    }

    func test_urlError_timeout_returnsRussianMessage() {
        let error = URLError(.timedOut)
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Сервер не отвечает")
    }

    func test_urlError_cannotConnect_returnsRussianMessage() {
        let error = URLError(.cannotConnectToHost)
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Сервер недоступен")
    }

    func test_urlError_connectionLost_returnsNoInternet() {
        let error = URLError(.networkConnectionLost)
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Нет интернета")
    }

    func test_urlError_sslFailed_returnsRussianMessage() {
        let error = URLError(.secureConnectionFailed)
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Ошибка SSL-соединения")
    }

    func test_urlError_other_returnsGenericNetwork() {
        let error = URLError(.badURL)
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Ошибка сети")
    }

    // MARK: - PipelineError

    func test_pipelineError_cancelled() {
        let error = PipelineError.cancelled
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Отменено")
    }

    func test_pipelineError_sttFailed() {
        let error = PipelineError.sttFailed("some detail")
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Ошибка распознавания: some detail")
    }

    func test_pipelineError_audioCaptureFailed() {
        let error = PipelineError.audioCaptureFailed("mic issue")
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Ошибка микрофона")
    }

    // MARK: - LLMError

    func test_llmError_rateLimited() {
        let error = LLMError.rateLimited
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Слишком много запросов")
    }

    func test_llmError_timeout() {
        let error = LLMError.timeout
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Сервер не отвечает")
    }

    func test_llmError_serverError() {
        let error = LLMError.serverError(statusCode: 503)
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Ошибка сервера")
    }

    // MARK: - AudioCaptureError

    func test_audioCaptureError_noMic() {
        let error = AudioCaptureError.microphoneNotAvailable
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Микрофон не найден")
    }

    func test_audioCaptureError_permissionDenied() {
        let error = AudioCaptureError.permissionDenied
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Нет доступа к микрофону")
    }

    // MARK: - TextInsertionError

    func test_textInsertionError_allStrategiesFailed() {
        let error = TextInsertionError.allStrategiesFailed
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Не удалось вставить текст")
    }

    // MARK: - Unknown error

    func test_unknownError_fallsBackToLocalizedDescription() {
        struct CustomError: LocalizedError {
            var errorDescription: String? { "custom message" }
        }
        let error = CustomError()
        XCTAssertEqual(ErrorMessages.userFacing(for: error), "Ошибка: custom message")
    }
}

// MARK: - BrandColors Tests

@MainActor
final class BrandColorsExtendedTests: XCTestCase {

    func test_alabasterGrey_isDefined() {
        let color = BrandColors.alabasterGrey
        XCTAssertNotNil(color)
        // #dedee0 → 222/255, 222/255, 224/255
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 222/255, accuracy: 0.01)
        XCTAssertEqual(g, 222/255, accuracy: 0.01)
        XCTAssertEqual(b, 224/255, accuracy: 0.01)
        XCTAssertEqual(a, 1.0, accuracy: 0.01)
    }

    func test_allFiveBrandColors_exist() {
        XCTAssertNotNil(BrandColors.cottonCandy)
        XCTAssertNotNil(BrandColors.skyAqua)
        XCTAssertNotNil(BrandColors.oceanMist)
        XCTAssertNotNil(BrandColors.petalFrost)
        XCTAssertNotNil(BrandColors.alabasterGrey)
    }
}
