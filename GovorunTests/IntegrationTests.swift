import SwiftData
import XCTest
@testable import Govorun

// MARK: - Controlled STT Mock (ждёт resume для ответа)

final class ControlledSTTClient: STTClient, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<STTResult, Error>?

    func recognize(audioData: Data, hints: [String]) async throws -> STTResult {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            self.continuation = cont
            lock.unlock()
        }
    }

    func complete(with result: STTResult) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: result)
    }

    func fail(with error: Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}

// MARK: - Helper для создания AppState с моками

@MainActor
private func makeTestAppState(
    mockAudio: MockAudioRecording = MockAudioRecording(),
    sttClient: STTClient? = nil,
    llmClient: LLMClient? = nil,
    accessibility: MockAccessibility = MockAccessibility(),
    clipboard: MockClipboard = MockClipboard(),
    modelContainer: ModelContainer? = nil,
    recordingMode: RecordingMode = .pushToTalk
) -> (AppState, MockAudioRecording, MockEventMonitoring) {

    let eventMonitor = MockEventMonitoring()
    let stt = sttClient ?? {
        let m = MockSTTClient()
        m.recognizeResult = STTResult(text: "тест")
        return m
    }()
    let llm = llmClient ?? {
        let m = MockLLMClient()
        m.normalizeResult = "Тест."
        return m
    }()

    let pipeline = PipelineEngine(
        audioCapture: mockAudio,
        sttClient: stt,
        llmClient: llm
    )
    let inserter = TextInserterEngine(
        accessibility: accessibility,
        clipboard: clipboard
    )

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
        modelContainer: modelContainer
    )

    return (appState, mockAudio, eventMonitor)
}

// MARK: - Интеграционные тесты AppState

@MainActor
final class IntegrationTests: XCTestCase {

    // MARK: - 1. Полный pipeline: hotkey → STT → LLM → insert

    func test_full_pipeline_mock() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = "audio data".data(using: .utf8)!

        let mockSTT = MockSTTClient()
        mockSTT.recognizeResult = STTResult(text: "привет марк ой точнее саша")

        let mockLLM = MockLLMClient()
        mockLLM.normalizeResult = "Привет, Саша"

        let mockAccessibility = MockAccessibility()
        let mockElement = MockAXElement()
        mockElement.settableAttributes = ["AXSelectedText"]
        mockAccessibility.focusedElement = mockElement

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: mockSTT,
            llmClient: mockLLM,
            accessibility: mockAccessibility
        )

        // ⌥ зажат 200ms+ → onActivated
        appState.activationKeyMonitor.onActivated?()
        // Task wrapper: sleep чтобы @MainActor Task выполнился
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        XCTAssertEqual(appState.sessionManager.state, .recording)
        XCTAssertTrue(mockAudio.startCallCount > 0)

        // ⌥ отпущен → onDeactivated → pipeline runs
        appState.activationKeyMonitor.onDeactivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Ждём завершения async pipeline
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertNotNil(appState.lastResult)
        XCTAssertEqual(appState.lastResult?.normalizedText, "Привет, Саша")
        XCTAssertEqual(appState.lastResult?.rawTranscript, "привет марк ой точнее саша")
    }

    // MARK: - 2. Cancel во время записи

    func test_cancel_during_recording() async throws {
        let mockAudio = MockAudioRecording()

        let (appState, _, _) = makeTestAppState(mockAudio: mockAudio)

        // Активация
        appState.activationKeyMonitor.onActivated?()
        await Task.yield()

        XCTAssertEqual(appState.sessionManager.state, .recording)
        XCTAssertTrue(mockAudio.startCallCount > 0)

        // Esc / другая клавиша → cancel
        appState.activationKeyMonitor.onCancelled?()
        await Task.yield()

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertNil(appState.lastResult)
    }

    // MARK: - 3. Cancel во время обработки (LLM)

    func test_cancel_during_processing() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = Data([0x01])

        let controlledSTT = ControlledSTTClient()

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: controlledSTT
        )

        // Активация → запись
        appState.activationKeyMonitor.onActivated?()
        await Task.yield()

        XCTAssertEqual(appState.sessionManager.state, .recording)

        // Деактивация → обработка начинается
        appState.activationKeyMonitor.onDeactivated?()
        await Task.yield()

        XCTAssertEqual(appState.sessionManager.state, .processing)

        // STT сейчас ждёт... отменяем
        await Task.yield() // дать pipeline Task дойти до recognize()
        appState.cancelProcessing()

        XCTAssertEqual(appState.sessionManager.state, .idle)

        // Завершаем STT чтобы Task мог корректно закончиться
        controlledSTT.complete(with: STTResult(text: "test"))
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Результат НЕ сохранён (cancel)
        XCTAssertNil(appState.lastResult)
    }

    // MARK: - 4. Пустой STT → ничего не вставляем

    func test_empty_stt_result() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = Data([0x01])

        let mockSTT = MockSTTClient()
        mockSTT.recognizeResult = STTResult(text: "")

        let mockClipboard = MockClipboard()

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: mockSTT,
            clipboard: mockClipboard
        )

        appState.activationKeyMonitor.onActivated?()
        await Task.yield()

        appState.activationKeyMonitor.onDeactivated?()
        await Task.yield()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertNil(appState.lastResult)
        XCTAssertEqual(mockClipboard.saveCallCount, 0) // clipboard не трогали
    }

    // MARK: - 5. Trivial текст → DeterministicNormalizer (без LLM)

    func test_trivial_text_skips_llm() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = Data([0x01])

        // "привет" — 1 слово, без коррекции, без чисел → trivial
        let mockSTT = MockSTTClient()
        mockSTT.recognizeResult = STTResult(text: "привет")

        let mockLLM = MockLLMClient()
        mockLLM.normalizeResult = "SHOULD NOT BE CALLED"

        let mockAccessibility = MockAccessibility()
        let mockElement = MockAXElement()
        mockElement.settableAttributes = ["AXSelectedText"]
        mockAccessibility.focusedElement = mockElement

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: mockSTT,
            llmClient: mockLLM,
            accessibility: mockAccessibility
        )

        appState.activationKeyMonitor.onActivated?()
        await Task.yield()
        appState.activationKeyMonitor.onDeactivated?()
        await Task.yield()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(appState.lastResult)
        XCTAssertEqual(appState.lastResult?.normalizedText, "Привет.")
        XCTAssertEqual(appState.lastResult?.normalizationPath, .trivial)
        XCTAssertEqual(mockLLM.normalizeCalls.count, 0) // LLM не вызвали
    }

    // MARK: - 6. Pipeline error → bottomBar показывает ошибку

    func test_pipeline_error_shows_in_bottom_bar() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = Data([0x01])

        let mockSTT = MockSTTClient()
        mockSTT.recognizeError = STTError.connectionFailed("connection refused")

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: mockSTT
        )

        appState.activationKeyMonitor.onActivated?()
        await Task.yield()
        appState.activationKeyMonitor.onDeactivated?()
        await Task.yield()

        try await Task.sleep(nanoseconds: 200_000_000)

        // State machine перешла в error
        if case .error = appState.sessionManager.state {
            // OK
        } else {
            XCTFail("Expected error state, got \(appState.sessionManager.state)")
        }
        XCTAssertNil(appState.lastResult)
    }

    // MARK: - 7. Start/stop lifecycle

    func test_start_stop_lifecycle() async throws {
        let (appState, _, _) = makeTestAppState()

        XCTAssertFalse(appState.isReady)

        appState.start()
        XCTAssertTrue(appState.isReady)

        appState.stop()
        XCTAssertFalse(appState.isReady)
    }

    // MARK: - 8. Clipboard fallback работает через pipeline

    func test_clipboard_fallback_through_pipeline() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = Data([0x01])

        let mockSTT = MockSTTClient()
        mockSTT.recognizeResult = STTResult(text: "привет марк ой точнее саша")

        let mockLLM = MockLLMClient()
        mockLLM.normalizeResult = "Привет, Саша"

        // Нет focused element → fallback к clipboard
        let mockAccessibility = MockAccessibility()
        mockAccessibility.focusedElement = nil

        let mockClipboard = MockClipboard()
        mockClipboard.savedItems = []

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: mockSTT,
            llmClient: mockLLM,
            accessibility: mockAccessibility,
            clipboard: mockClipboard
        )

        appState.activationKeyMonitor.onActivated?()
        await Task.yield()
        appState.activationKeyMonitor.onDeactivated?()
        await Task.yield()

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(appState.lastResult)
        XCTAssertEqual(appState.lastResult?.normalizedText, "Привет, Саша")
        XCTAssertEqual(mockClipboard.setStringValue, "Привет, Саша")
        XCTAssertEqual(mockClipboard.simulatePasteCallCount, 1)
    }

    // MARK: - 9. Toggle mode: полный pipeline

    func test_toggle_full_pipeline() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = "audio data".data(using: .utf8)!

        let mockSTT = MockSTTClient()
        mockSTT.recognizeResult = STTResult(text: "привет")

        let mockAccessibility = MockAccessibility()
        let mockElement = MockAXElement()
        mockElement.settableAttributes = ["AXSelectedText"]
        mockAccessibility.focusedElement = mockElement

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: mockSTT,
            accessibility: mockAccessibility,
            recordingMode: .toggle
        )

        // Toggle: первое нажатие → onActivated
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.sessionManager.state, .recording)
        XCTAssertTrue(mockAudio.startCallCount > 0)

        // Toggle: второе нажатие → onDeactivated → pipeline runs
        appState.activationKeyMonitor.onDeactivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertNotNil(appState.lastResult)
        XCTAssertEqual(appState.lastResult?.normalizedText, "Привет.")
    }

    // MARK: - 10. Toggle mode: cancel через onCancelled

    func test_toggle_cancel_during_recording() async throws {
        let mockAudio = MockAudioRecording()

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            recordingMode: .toggle
        )

        // Toggle activate
        appState.activationKeyMonitor.onActivated?()
        await Task.yield()
        XCTAssertEqual(appState.sessionManager.state, .recording)

        // Esc → cancel
        appState.activationKeyMonitor.onCancelled?()
        await Task.yield()

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertNil(appState.lastResult)
    }
}

// MARK: - Dictionary wiring тесты

@MainActor
final class DictionaryWiringTests: XCTestCase {

    func test_dictionary_is_wired_into_runtime_pipeline() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DictionaryEntry.self, Snippet.self, HistoryItem.self,
            configurations: config
        )
        let ctx = ModelContext(container)
        let store = DictionaryStore(modelContext: ctx)
        try store.addWord("Jira", alternatives: ["жира"])

        let mockAudio = MockAudioRecording()
        mockAudio.audioData = "audio".data(using: .utf8)!

        let mockSTT = MockSTTClient()
        mockSTT.recognizeResult = STTResult(text: "жира не отвечает")

        let mockLLM = MockLLMClient()
        mockLLM.normalizeResult = "Jira не отвечает."

        let mockAccessibility = MockAccessibility()
        let mockElement = MockAXElement()
        mockElement.settableAttributes = ["AXSelectedText"]
        mockAccessibility.focusedElement = mockElement

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: mockSTT,
            llmClient: mockLLM,
            accessibility: mockAccessibility,
            modelContainer: container
        )

        appState.activationKeyMonitor.onActivated?()
        await Task.yield()

        appState.activationKeyMonitor.onDeactivated?()
        await Task.yield()

        try await Task.sleep(nanoseconds: 200_000_000)

        // GigaAM не поддерживает hints — всегда пустой массив
        XCTAssertEqual(mockSTT.recognizeCalls.first?.hints, [])
        XCTAssertEqual(
            mockLLM.normalizeCalls.first?.hints.personalDictionary,
            ["жира": "Jira"]
        )
    }
}

// MARK: - StatusBarController тесты

@MainActor
final class StatusBarControllerTests: XCTestCase {

    func test_status_bar_creates_with_app_state() throws {
        let (appState, _, _) = makeTestAppState()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DictionaryEntry.self, Snippet.self, HistoryItem.self,
            configurations: config
        )
        let settingsWC = SettingsWindowController(modelContainer: container, appState: appState)
        let sut = StatusBarController(appState: appState, settingsWindowController: settingsWC)
        // Просто проверяем что не крашится
        XCTAssertNotNil(sut)
    }
}
