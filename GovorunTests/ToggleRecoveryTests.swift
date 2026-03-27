@testable import Govorun
import XCTest

// MARK: - Helper для toggle recovery тестов

@MainActor
private func makeToggleAppState(
    mockAudio: MockAudioRecording = MockAudioRecording(),
    recordingMode: RecordingMode = .toggle,
    initialWorkerState: WorkerState = .ready,
    eventMonitor: MockEventMonitoring = MockEventMonitoring()
) -> (AppState, MockAudioRecording, MockEventMonitoring) {
    let stt = MockSTTClient()
    stt.recognizeResult = STTResult(text: "тест")
    let llm = MockLLMClient()
    llm.normalizeResult = "Тест."

    let pipeline = PipelineEngine(
        audioCapture: mockAudio,
        sttClient: stt,
        llmClient: llm
    )
    let inserter = TextInserterEngine(
        accessibility: MockAccessibility(),
        clipboard: MockClipboard()
    )

    let testDefaults = UserDefaults(suiteName: "com.govorun.toggle-recovery.\(UUID().uuidString)")!
    let settings = SettingsStore(defaults: testDefaults)
    settings.productMode = .superMode
    settings.recordingMode = recordingMode

    let appState = AppState(
        activationKeyMonitor: ActivationKeyMonitor(
            activationKey: .default,
            recordingMode: recordingMode,
            eventMonitor: eventMonitor
        ),
        sessionManager: SessionManager(),
        pipelineEngine: pipeline,
        textInserter: inserter,
        bottomBar: BottomBarController(),
        audioCapture: AudioCapture(),
        initialWorkerState: initialWorkerState,
        settings: settings,
        eventMonitor: eventMonitor
    )

    return (appState, mockAudio, eventMonitor)
}

// MARK: - ActivationKeyMonitor: resetState тесты

@MainActor
final class ActivationKeyMonitorResetStateTests: XCTestCase {
    private func waitMain(_ seconds: TimeInterval) {
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        waitForExpectations(timeout: seconds + 1)
    }

    // MARK: - resetState сбрасывает armed state

    func test_resetState_clears_armed_toggle() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activated = false
        sut.onActivated = { activated = true }
        sut.startMonitoring()

        // Arm (hold 200ms)
        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3)

        // Reset
        sut.resetState()

        // Release — не должен активировать (state сброшен)
        mock.simulateFlagsChanged(CGEventFlags())
        XCTAssertFalse(activated)
    }

    // MARK: - resetState сбрасывает activated state

    func test_resetState_clears_activated_toggle() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activatedCount = 0
        var deactivatedCount = 0
        sut.onActivated = { activatedCount += 1 }
        sut.onDeactivated = { deactivatedCount += 1 }
        sut.startMonitoring()

        // Активируем toggle
        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3)
        mock.simulateFlagsChanged(CGEventFlags()) // release → activate
        XCTAssertEqual(activatedCount, 1)

        // Reset (имитация cancel)
        sut.resetState()

        // Следующий tap — должен быть НОВАЯ активация, а не deactivate
        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3)
        mock.simulateFlagsChanged(CGEventFlags()) // release → activate
        XCTAssertEqual(activatedCount, 2)
        XCTAssertEqual(deactivatedCount, 0, "resetState не должен вызывать deactivated")
    }

    // MARK: - resetState не вызывает callbacks

    func test_resetState_does_not_fire_callbacks() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var callbackFired = false
        sut.onActivated = { callbackFired = true }
        sut.onDeactivated = { callbackFired = true }
        sut.onCancelled = { callbackFired = true }
        sut.startMonitoring()

        // Arm
        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3)
        mock.simulateFlagsChanged(CGEventFlags()) // activate
        callbackFired = false // reset counter

        sut.resetState()
        XCTAssertFalse(callbackFired, "resetState не должен вызывать никаких callbacks")
    }
}

// MARK: - Toggle cancel recovery тесты (AppState integration)

@MainActor
final class ToggleCancelRecoveryTests: XCTestCase {
    // MARK: - 1. Toggle → cancel (Esc) → следующий tap снова активирует

    func test_toggle_cancel_esc_then_reactivate() async throws {
        let (appState, _, _) = makeToggleAppState()

        // Toggle activate
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording)

        // Cancel (Esc path)
        appState.cancelProcessing()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .idle)

        // Следующий tap — должен снова активировать
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording,
                       "После cancel следующий tap должен стартовать новую запись")
    }

    // MARK: - 2. Toggle → worker not ready → следующий tap снова активирует

    func test_toggle_worker_not_ready_then_reactivate() async throws {
        let (appState, _, _) = makeToggleAppState(initialWorkerState: .loadingModel)

        // Попытка активации — worker не ready
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .idle,
                       "Запись не должна начаться пока worker не ready")

        // Worker готов
        appState.updateWorkerState(.ready)

        // Следующий tap — должен активировать, не деактивировать
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording,
                       "После rejected activation следующий tap должен быть новой активацией")
    }

    // MARK: - 3. Toggle → worker error → следующий tap снова активирует

    func test_toggle_worker_error_then_reactivate() async throws {
        let (appState, _, _) = makeToggleAppState(initialWorkerState: .error("модель не найдена"))

        // Попытка активации — worker в error
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .idle)

        // Worker восстановился
        appState.updateWorkerState(.ready)

        // Следующий tap — новая активация
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording)
    }

    // MARK: - 4. Toggle → cancel через onCancelled → monitor state сброшен

    func test_toggle_onCancelled_resets_monitor_state() async throws {
        let (appState, _, _) = makeToggleAppState()

        // Toggle activate
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording)

        // Cancel через onCancelled (Esc/sleep/tap reset)
        appState.activationKeyMonitor.onCancelled?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .idle)

        // Повторная активация — должна работать
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording)
    }

    // MARK: - 5. CGEventTap reset during toggle → safe reset

    func test_tap_reset_during_toggle_resets_and_allows_reactivation() async throws {
        let (appState, _, _) = makeToggleAppState()

        // Toggle activate
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording)

        // CGEventTap reset path (calls handleCancelled через onTapReset)
        appState.activationKeyMonitor.onCancelled?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .idle)

        // Следующий tap — новая активация
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording)
    }
}

// MARK: - Toggle combo modifier release тесты

@MainActor
final class ToggleComboModifierReleaseTests: XCTestCase {
    private func waitMain(_ seconds: TimeInterval) {
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        waitForExpectations(timeout: seconds + 1)
    }

    // MARK: - 6. Toggle combo: отпускание модификаторов после старта не ломает stop

    func test_toggle_combo_modifier_release_after_start_does_not_break_stop() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .combo(modifiers: .maskCommand, keyCode: 40), // ⌘K
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activatedCount = 0
        var deactivatedCount = 0
        sut.onActivated = { activatedCount += 1 }
        sut.onDeactivated = { deactivatedCount += 1 }
        sut.startMonitoring()

        // Первый combo tap → активация toggle
        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateKeyDown(keyCode: 40)
        waitMain(0.3)
        mock.simulateKeyUp(keyCode: 40)
        XCTAssertEqual(activatedCount, 1)

        // Отпускаем модификаторы (⌘ up) — НЕ должно завершать запись
        mock.simulateFlagsChanged(CGEventFlags())
        XCTAssertEqual(deactivatedCount, 0,
                       "Отпускание модификаторов после toggle start не должно деактивировать")

        // Второй combo tap → деактивация (модификаторы снова зажаты)
        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateKeyDown(keyCode: 40)
        mock.simulateKeyUp(keyCode: 40)
        XCTAssertEqual(deactivatedCount, 1,
                       "Второй combo tap должен деактивировать toggle")
    }

    // MARK: - 7. Toggle combo: modifier release + re-press + stop работает

    func test_toggle_combo_modifier_release_repress_then_stop() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .combo(modifiers: .maskCommand, keyCode: 40),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activatedCount = 0
        var deactivatedCount = 0
        sut.onActivated = { activatedCount += 1 }
        sut.onDeactivated = { deactivatedCount += 1 }
        sut.startMonitoring()

        // Start toggle
        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateKeyDown(keyCode: 40)
        waitMain(0.3)
        mock.simulateKeyUp(keyCode: 40)
        XCTAssertEqual(activatedCount, 1)

        // Release ⌘
        mock.simulateFlagsChanged(CGEventFlags())
        XCTAssertEqual(deactivatedCount, 0)

        // Re-press ⌘
        mock.simulateFlagsChanged(.maskCommand)

        // Stop toggle с combo
        mock.simulateKeyDown(keyCode: 40)
        mock.simulateKeyUp(keyCode: 40)
        XCTAssertEqual(deactivatedCount, 1)
    }

    // MARK: - 8. Push-to-talk combo: modifier release всё ещё деактивирует

    func test_ptt_combo_modifier_release_deactivates() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .combo(modifiers: .maskCommand, keyCode: 40),
            recordingMode: .pushToTalk,
            eventMonitor: mock
        )

        var activated = false
        var deactivated = false
        sut.onActivated = { activated = true }
        sut.onDeactivated = { deactivated = true }
        sut.startMonitoring()

        // Активация
        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateKeyDown(keyCode: 40)
        waitMain(0.3)
        XCTAssertTrue(activated)

        // Отпускание модификаторов — в PTT должно деактивировать
        mock.simulateFlagsChanged(CGEventFlags())
        XCTAssertTrue(deactivated)
    }
}

// MARK: - Toggle → pushToTalk transition тесты

@MainActor
final class ToggleToPushToTalkTransitionTests: XCTestCase {
    // MARK: - 9. Toggle → pushToTalk while recording → применяется после завершения сессии

    func test_toggle_to_ptt_while_recording_deferred() async throws {
        let eventMonitor = MockEventMonitoring()
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: "com.govorun.t2p.\(UUID().uuidString)"))
        let settings = SettingsStore(defaults: testDefaults)
        settings.productMode = .superMode
        settings.recordingMode = .toggle

        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "тест")
        let llm = MockLLMClient()
        let mockAudio = MockAudioRecording()

        let pipeline = PipelineEngine(
            audioCapture: mockAudio,
            sttClient: stt,
            llmClient: llm
        )
        let inserter = TextInserterEngine(
            accessibility: MockAccessibility(),
            clipboard: MockClipboard()
        )

        let appState = AppState(
            activationKeyMonitor: ActivationKeyMonitor(
                activationKey: .default,
                recordingMode: .toggle,
                eventMonitor: eventMonitor
            ),
            sessionManager: SessionManager(),
            pipelineEngine: pipeline,
            textInserter: inserter,
            bottomBar: BottomBarController(),
            audioCapture: AudioCapture(),
            settings: settings,
            eventMonitor: eventMonitor
        )

        appState.start()

        // Начинаем toggle запись
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording)
        XCTAssertEqual(appState.effectiveRecordingMode, .toggle)

        // Меняем режим на pushToTalk во время записи
        settings.recordingMode = .pushToTalk
        try await Task.sleep(nanoseconds: 50_000_000)

        // effectiveRecordingMode всё ещё toggle (pending)
        XCTAssertEqual(appState.effectiveRecordingMode, .toggle,
                       "Во время сессии effectiveRecordingMode должен оставаться toggle")

        // Отменяем запись → idle → pending применяется
        appState.activationKeyMonitor.onCancelled?()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertEqual(appState.effectiveRecordingMode, .pushToTalk,
                       "После завершения сессии режим должен стать pushToTalk")
        XCTAssertEqual(appState.activationKeyMonitor.recordingMode, .pushToTalk)

        appState.stop()
    }

    // MARK: - 10. Toggle → pushToTalk after error → режим реально становится pushToTalk

    func test_toggle_to_ptt_after_error_applies() async throws {
        let eventMonitor = MockEventMonitoring()
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: "com.govorun.t2pe.\(UUID().uuidString)"))
        let settings = SettingsStore(defaults: testDefaults)
        settings.productMode = .superMode
        settings.recordingMode = .toggle

        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "тест")
        let llm = MockLLMClient()

        let pipeline = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm
        )
        let inserter = TextInserterEngine(
            accessibility: MockAccessibility(),
            clipboard: MockClipboard()
        )

        let appState = AppState(
            activationKeyMonitor: ActivationKeyMonitor(
                activationKey: .default,
                recordingMode: .toggle,
                eventMonitor: eventMonitor
            ),
            sessionManager: SessionManager(),
            pipelineEngine: pipeline,
            textInserter: inserter,
            bottomBar: BottomBarController(),
            audioCapture: AudioCapture(),
            settings: settings,
            eventMonitor: eventMonitor
        )

        appState.start()

        // Симулируем error state
        appState.sessionManager.handleActivated()
        appState.sessionManager.handleError("тестовая ошибка")
        XCTAssertEqual(appState.effectiveRecordingMode, .toggle)

        // Меняем режим на pushToTalk
        settings.recordingMode = .pushToTalk
        try await Task.sleep(nanoseconds: 50_000_000)

        // Режим pending, потому что session не idle
        XCTAssertEqual(appState.effectiveRecordingMode, .toggle)

        // Error auto-dismiss → idle → pending применяется
        // Ждём 3.5 секунды (auto-dismiss через 3s)
        try await Task.sleep(nanoseconds: 3_500_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertEqual(appState.effectiveRecordingMode, .pushToTalk,
                       "После auto-dismiss error режим должен стать pushToTalk")
        XCTAssertEqual(appState.activationKeyMonitor.recordingMode, .pushToTalk)

        appState.stop()
    }

    // MARK: - 11. effectiveRecordingMode отражает runtime, а не settings

    func test_effectiveRecordingMode_reflects_runtime() async throws {
        let eventMonitor = MockEventMonitoring()
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: "com.govorun.erm.\(UUID().uuidString)"))
        let settings = SettingsStore(defaults: testDefaults)
        settings.productMode = .superMode

        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "тест")
        let llm = MockLLMClient()

        let pipeline = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm
        )
        let inserter = TextInserterEngine(
            accessibility: MockAccessibility(),
            clipboard: MockClipboard()
        )

        let appState = AppState(
            activationKeyMonitor: ActivationKeyMonitor(
                activationKey: .default,
                recordingMode: .pushToTalk,
                eventMonitor: eventMonitor
            ),
            sessionManager: SessionManager(),
            pipelineEngine: pipeline,
            textInserter: inserter,
            bottomBar: BottomBarController(),
            audioCapture: AudioCapture(),
            settings: settings,
            eventMonitor: eventMonitor
        )

        appState.start()

        // Исходно pushToTalk
        XCTAssertEqual(appState.effectiveRecordingMode, .pushToTalk)
        XCTAssertEqual(settings.recordingMode, .pushToTalk)

        // В idle — смена сразу применяется
        settings.recordingMode = .toggle
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.effectiveRecordingMode, .toggle)

        appState.stop()
    }
}

// MARK: - Error auto-dismiss тесты

@MainActor
final class ErrorAutoDismissTests: XCTestCase {
    // MARK: - 12. Error auto-dismiss переводит в idle

    func test_error_auto_dismisses_to_idle() async throws {
        let (appState, _, _) = makeToggleAppState()

        // Переводим в error
        appState.sessionManager.handleActivated()
        appState.sessionManager.handleError("тест")
        XCTAssertEqual(appState.sessionState, .error("тест"))

        // Ждём auto-dismiss (3s + margin)
        try await Task.sleep(nanoseconds: 3_500_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle,
                       "Error state должен auto-dismiss в idle через 3 секунды")
    }

    // MARK: - 13. Error auto-dismiss → pending settings применяются

    func test_error_auto_dismiss_applies_pending_settings() async throws {
        let eventMonitor = MockEventMonitoring()
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: "com.govorun.ead.\(UUID().uuidString)"))
        let settings = SettingsStore(defaults: testDefaults)
        settings.productMode = .superMode

        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "тест")
        let llm = MockLLMClient()

        let pipeline = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm
        )
        let inserter = TextInserterEngine(
            accessibility: MockAccessibility(),
            clipboard: MockClipboard()
        )

        let appState = AppState(
            activationKeyMonitor: ActivationKeyMonitor(
                activationKey: .default,
                recordingMode: .pushToTalk,
                eventMonitor: eventMonitor
            ),
            sessionManager: SessionManager(),
            pipelineEngine: pipeline,
            textInserter: inserter,
            bottomBar: BottomBarController(),
            audioCapture: AudioCapture(),
            settings: settings,
            eventMonitor: eventMonitor
        )

        appState.start()

        // Переводим в error
        appState.sessionManager.handleActivated()
        appState.sessionManager.handleError("тест")

        // Меняем режим пока в error state
        settings.recordingMode = .toggle
        try await Task.sleep(nanoseconds: 50_000_000)

        // Pending — runtime всё ещё pushToTalk
        XCTAssertEqual(appState.effectiveRecordingMode, .pushToTalk)

        // Auto-dismiss → idle → pending применяется
        try await Task.sleep(nanoseconds: 3_500_000_000)

        XCTAssertEqual(appState.effectiveRecordingMode, .toggle,
                       "Pending recordingMode должен примениться после auto-dismiss error")

        appState.stop()
    }

    // MARK: - 14. Активация после auto-dismiss error работает

    func test_activation_works_after_error_auto_dismiss() async throws {
        let (appState, _, _) = makeToggleAppState()

        // Error state
        appState.sessionManager.handleActivated()
        appState.sessionManager.handleError("тест")

        // Auto-dismiss
        try await Task.sleep(nanoseconds: 3_500_000_000)
        XCTAssertEqual(appState.sessionManager.state, .idle)

        // Теперь активация должна работать
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording,
                       "Активация должна работать после auto-dismiss error")
    }
}

// MARK: - Toggle keyCode recovery тесты

@MainActor
final class ToggleKeyCodeRecoveryTests: XCTestCase {
    private func waitMain(_ seconds: TimeInterval) {
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        waitForExpectations(timeout: seconds + 1)
    }

    // MARK: - 15. Toggle keyCode: cancel → reactivate

    func test_toggle_keyCode_cancel_then_reactivate() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .keyCode(96),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activatedCount = 0
        var deactivatedCount = 0
        sut.onActivated = { activatedCount += 1 }
        sut.onDeactivated = { deactivatedCount += 1 }
        sut.startMonitoring()

        // Activate toggle
        mock.simulateKeyDown(keyCode: 96)
        waitMain(0.3)
        mock.simulateKeyUp(keyCode: 96)
        XCTAssertEqual(activatedCount, 1)

        // Reset (simulate cancel)
        sut.resetState()

        // Next tap — должна быть новая активация
        mock.simulateKeyDown(keyCode: 96)
        waitMain(0.3)
        mock.simulateKeyUp(keyCode: 96)
        XCTAssertEqual(activatedCount, 2, "После resetState следующий tap должен активировать")
        XCTAssertEqual(deactivatedCount, 0, "resetState не должен порождать deactivated")
    }

    // MARK: - 16. Toggle combo: cancel → reactivate

    func test_toggle_combo_cancel_then_reactivate() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .combo(modifiers: .maskCommand, keyCode: 40),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activatedCount = 0
        sut.onActivated = { activatedCount += 1 }
        sut.startMonitoring()

        // Activate
        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateKeyDown(keyCode: 40)
        waitMain(0.3)
        mock.simulateKeyUp(keyCode: 40)
        XCTAssertEqual(activatedCount, 1)

        // Reset
        sut.resetState()

        // New activation
        mock.simulateFlagsChanged(.maskCommand)
        mock.simulateKeyDown(keyCode: 40)
        waitMain(0.3)
        mock.simulateKeyUp(keyCode: 40)
        XCTAssertEqual(activatedCount, 2)
    }
}

// MARK: - Toggle modifier: другие модификаторы во время записи

@MainActor
final class ToggleModifierOtherKeysTests: XCTestCase {
    private func waitMain(_ seconds: TimeInterval) {
        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        waitForExpectations(timeout: seconds + 1)
    }

    // MARK: - 17. Toggle modifier: ⌘ во время записи не ломает toggle

    func test_toggle_modifier_other_modifier_during_recording_does_not_break() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        var activatedCount = 0
        var deactivatedCount = 0
        var cancelledCount = 0
        sut.onActivated = { activatedCount += 1 }
        sut.onDeactivated = { deactivatedCount += 1 }
        sut.onCancelled = { cancelledCount += 1 }
        sut.startMonitoring()

        // Activate toggle: hold ⌥ 200ms, release
        mock.simulateFlagsChanged(.maskAlternate)
        waitMain(0.3)
        mock.simulateFlagsChanged(CGEventFlags()) // release → activate
        XCTAssertEqual(activatedCount, 1)

        // Во время записи нажимаем ⌘ (для шортката)
        mock.simulateFlagsChanged(.maskCommand)
        XCTAssertEqual(deactivatedCount, 0, "⌘ не должен деактивировать toggle запись")
        XCTAssertEqual(cancelledCount, 0, "⌘ не должен отменять toggle запись")

        // Отпускаем ⌘
        mock.simulateFlagsChanged(CGEventFlags())

        // Второй tap ⌥ — штатный stop
        mock.simulateFlagsChanged(.maskAlternate)
        mock.simulateFlagsChanged(CGEventFlags()) // release → deactivate
        XCTAssertEqual(deactivatedCount, 1, "Второй ⌥ tap должен деактивировать")
    }

    // MARK: - 18. PTT modifier: ⌘ до активации отменяет (не затронуто)

    func test_ptt_modifier_other_modifier_before_activation_cancels() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .pushToTalk,
            eventMonitor: mock
        )

        var activated = false
        var cancelled = false
        sut.onActivated = { activated = true }
        sut.onCancelled = { cancelled = true }
        sut.startMonitoring()

        // ⌥ down
        mock.simulateFlagsChanged(.maskAlternate)
        // ⌥+⌘ (шорткат до 200ms)
        mock.simulateKeyDown(keyCode: 8)

        waitMain(0.3)
        XCTAssertFalse(activated)
        XCTAssertTrue(cancelled, "PTT: ⌥+клавиша до активации = cancel")
    }
}

// MARK: - Fix 6: startRecording error recovery

@MainActor
final class StartRecordingErrorRecoveryTests: XCTestCase {
    func test_toggle_startRecording_error_then_reactivate() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.startError = AudioCaptureError.microphoneNotAvailable

        let (appState, _, _) = makeToggleAppState(mockAudio: mockAudio)

        // Активация — startRecording бросит ошибку
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Session в error (startRecording failed)
        if case .error = appState.sessionManager.state {
            // OK
        } else {
            XCTFail("Ожидался .error, получено \(appState.sessionManager.state)")
        }

        // Ждём auto-dismiss error
        try await Task.sleep(nanoseconds: 3_500_000_000)
        XCTAssertEqual(appState.sessionManager.state, .idle)

        // "Чиним" audio
        mockAudio.startError = nil

        // Повторная активация — должна работать
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording,
                       "После починки audio повторная активация должна работать")
    }
}

// MARK: - Fix 7: resetTapState вызывается через mock

@MainActor
final class ResetTapStateTests: XCTestCase {
    func test_resetState_calls_resetTapState_on_eventMonitor() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            recordingMode: .toggle,
            eventMonitor: mock
        )

        XCTAssertEqual(mock.resetTapStateCallCount, 0)
        sut.resetState()
        XCTAssertEqual(mock.resetTapStateCallCount, 1,
                       "resetState() должен вызывать resetTapState() на eventMonitor")
    }

    func test_stopMonitoring_calls_resetTapState() {
        let mock = MockEventMonitoring()
        let sut = ActivationKeyMonitor(
            activationKey: .modifier(.maskAlternate),
            eventMonitor: mock
        )
        sut.startMonitoring()

        XCTAssertEqual(mock.resetTapStateCallCount, 0)
        sut.stopMonitoring()
        XCTAssertEqual(mock.resetTapStateCallCount, 1)
    }

    func test_handleCancelled_resets_tap_state() async throws {
        let eventMonitor = MockEventMonitoring()
        let (appState, _, _) = makeToggleAppState(eventMonitor: eventMonitor)

        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        let before = eventMonitor.resetTapStateCallCount
        appState.activationKeyMonitor.onCancelled?()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertGreaterThan(eventMonitor.resetTapStateCallCount, before,
                             "handleCancelled должен сбрасывать tap state")
    }
}

// MARK: - Fix 3: Cancellable error dismiss

@MainActor
final class CancellableErrorDismissTests: XCTestCase {
    func test_second_error_gets_full_3_seconds() async throws {
        let (appState, _, _) = makeToggleAppState()

        // Первый error
        appState.sessionManager.handleActivated()
        appState.sessionManager.handleError("ошибка 1")

        // Через 2 секунды — второй error
        try await Task.sleep(nanoseconds: 2_000_000_000)
        appState.sessionManager.handleErrorDismissed()
        appState.sessionManager.handleActivated()
        appState.sessionManager.handleError("ошибка 2")

        // Через 2 секунды после второго error — ещё не dismiss
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(appState.sessionState, .error("ошибка 2"),
                       "Второй error не должен быть dismiss'нут преждевременно")

        // Через ещё 1.5s — dismiss
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(appState.sessionManager.state, .idle)
    }
}
