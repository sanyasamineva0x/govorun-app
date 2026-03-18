import XCTest
@testable import Govorun

// MARK: - Тесты recreateMonitor / pendingActivationKey

@MainActor
final class RecreateMonitorTests: XCTestCase {

    private var defaults: UserDefaults!
    private var settings: SettingsStore!

    override func setUp() {
        super.setUp()
        let suiteName = "com.govorun.tests.recreate.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults = nil
        settings = nil
        super.tearDown()
    }

    /// Хелпер: создаём AppState с тестовыми зависимостями
    private func makeAppState(
        eventMonitor: MockEventMonitoring = MockEventMonitoring()
    ) -> (AppState, MockEventMonitoring) {
        let mockAudio = MockAudioRecording()
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "тест")
        let llm = MockLLMClient()

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
                activationKey: settings.activationKey,
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

        return (appState, eventMonitor)
    }

    // MARK: - 1. Смена activationKey в idle → монитор пересоздаётся немедленно

    func test_change_activationKey_while_idle_recreates_monitor() async throws {
        let (appState, eventMonitor) = makeAppState()
        appState.start()

        // Исходная клавиша — default (⌥)
        XCTAssertEqual(appState.activationKeyMonitor.activationKey, .default)

        // Меняем клавишу через settings
        settings.activationKey = .keyCode(96) // F5

        // objectWillChange → handleSettingsChanged вызывается через Combine sink в Task @MainActor
        // Даём runloop обработать
        try await Task.sleep(nanoseconds: 50_000_000)

        // Монитор должен быть пересоздан с новой клавишой
        XCTAssertEqual(appState.activationKeyMonitor.activationKey, .keyCode(96))
        XCTAssertEqual(eventMonitor.activationKey, .keyCode(96))
    }

    // MARK: - 2. Смена activationKey во время сессии → откладывается до idle

    func test_change_activationKey_while_recording_deferred_until_idle() async throws {
        let (appState, _) = makeAppState()
        appState.start()

        // Начинаем запись
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording)

        // Меняем клавишу — должна отложиться
        settings.activationKey = .keyCode(96)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Монитор НЕ пересоздан (сессия активна)
        XCTAssertEqual(appState.activationKeyMonitor.activationKey, .default)

        // Отменяем сессию → idle → pendingKey применяется
        appState.activationKeyMonitor.onCancelled?()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertEqual(appState.activationKeyMonitor.activationKey, .keyCode(96))
    }

    // MARK: - 3. Смена не-activationKey настройки → монитор НЕ пересоздаётся

    func test_change_non_activationKey_setting_does_not_recreate_monitor() async throws {
        let (appState, eventMonitor) = makeAppState()
        appState.start()

        let monitorBefore = appState.activationKeyMonitor

        // Меняем другую настройку
        settings.soundEnabled = false
        try await Task.sleep(nanoseconds: 50_000_000)

        // Монитор тот же самый объект (не пересоздан)
        XCTAssertTrue(appState.activationKeyMonitor === monitorBefore)
        XCTAssertEqual(eventMonitor.activationKey, .default)
    }

    // MARK: - 4. recreateMonitor без eventMonitor → монитор остаётся живым

    func test_recreateMonitor_without_eventMonitor_keeps_monitor_alive() async throws {
        let mockAudio = MockAudioRecording()
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "тест")
        let llm = MockLLMClient()

        let pipeline = PipelineEngine(
            audioCapture: mockAudio,
            sttClient: stt,
            llmClient: llm
        )
        let inserter = TextInserterEngine(
            accessibility: MockAccessibility(),
            clipboard: MockClipboard()
        )

        // eventMonitor = nil (guard должен сработать ДО stopMonitoring)
        let eventMonitor = MockEventMonitoring()
        let appState = AppState(
            activationKeyMonitor: ActivationKeyMonitor(
                activationKey: settings.activationKey,
                eventMonitor: eventMonitor
            ),
            sessionManager: SessionManager(),
            pipelineEngine: pipeline,
            textInserter: inserter,
            bottomBar: BottomBarController(),
            audioCapture: AudioCapture(),
            settings: settings,
            eventMonitor: nil  // нет eventMonitor
        )

        appState.start()

        let monitorBefore = appState.activationKeyMonitor

        // Меняем клавишу — recreateMonitor вызовется, но guard let eventMonitor сработает
        settings.activationKey = .keyCode(96)
        try await Task.sleep(nanoseconds: 50_000_000)

        // Монитор не пересоздан, но и не убит (guard ПЕРЕД stopMonitoring)
        XCTAssertTrue(appState.activationKeyMonitor === monitorBefore)
    }
}
