@testable import Govorun
import SwiftData
import XCTest

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
    snippetEngine: SnippetMatching? = nil,
    accessibility: MockAccessibility = MockAccessibility(),
    clipboard: MockClipboard = MockClipboard(),
    modelContainer: ModelContainer? = nil,
    recordingMode: RecordingMode = .pushToTalk,
    analytics: AnalyticsEmitting = NoOpAnalyticsService(),
    productMode: ProductMode = .superMode
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
        llmClient: llm,
        snippetEngine: snippetEngine
    )
    pipeline.productMode = productMode

    let inserter = TextInserterEngine(
        accessibility: accessibility,
        clipboard: clipboard
    )

    // Изолированный SettingsStore — тесты не зависят от UserDefaults.standard
    let testDefaults = UserDefaults(suiteName: "com.govorun.integration-test.\(UUID().uuidString)")!
    let settings = SettingsStore(defaults: testDefaults)
    settings.productMode = productMode

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
        modelContainer: modelContainer,
        analytics: analytics,
        superAssetsManager: MockSuperAssetsManager(),
        settings: settings
    )

    // handleActivated проверяет superAssetsState — в тестах ассеты «установлены»
    if productMode.usesLLM {
        appState.superAssetsState = .installed
    }

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
        try await Task.sleep(nanoseconds: 800_000_000) // 800ms (600ms min processing + margin)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertNotNil(appState.lastResult)
        XCTAssertEqual(appState.lastResult?.normalizedText, "Привет, Саша")
        XCTAssertEqual(appState.lastResult?.rawTranscript, "привет марк ой точнее саша")
    }

    func test_llm_failure_emits_normalization_failed_event() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = "audio data".data(using: .utf8)!

        let mockSTT = MockSTTClient()
        mockSTT.recognizeResult = STTResult(text: "ну короче давай завтра созвонимся")

        let mockLLM = MockLLMClient()
        mockLLM.normalizeError = LLMError.serverError(statusCode: 500)

        let mockAccessibility = MockAccessibility()
        let mockElement = MockAXElement()
        mockElement.settableAttributes = ["AXSelectedText"]
        mockAccessibility.focusedElement = mockElement

        let analytics = MockAnalyticsCollector()

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: mockSTT,
            llmClient: mockLLM,
            accessibility: mockAccessibility,
            analytics: analytics
        )

        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        appState.activationKeyMonitor.onDeactivated?()
        try await Task.sleep(nanoseconds: 850_000_000)

        let failedEvent = analytics.events.first { $0.0 == .normalizationFailed }
        XCTAssertNotNil(failedEvent)
        XCTAssertEqual(failedEvent?.2[AnalyticsMetadataKey.normalizationPath], "llmFailed")
        XCTAssertEqual(
            failedEvent?.2[AnalyticsMetadataKey.errorType],
            AnalyticsErrorType.normalizationApi.rawValue
        )
        XCTAssertFalse(analytics.events.contains { $0.0 == .normalizationCompleted })
    }

    func test_embedded_snippet_llm_failure_emits_failed_event_and_fallback_reason() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = "audio data".data(using: .utf8)!

        let mockSTT = MockSTTClient()
        mockSTT.recognizeResult = STTResult(text: "лена вот мой адрес")

        let mockLLM = MockLLMClient()
        mockLLM.normalizeError = LLMError.serverError(statusCode: 500)

        let snippets = MockSnippetEngine()
        snippets.configureEmbedded("мой адрес", content: "Аминева 9", forInput: "лена вот мой адрес")

        let mockAccessibility = MockAccessibility()
        let mockElement = MockAXElement()
        mockElement.settableAttributes = ["AXSelectedText"]
        mockAccessibility.focusedElement = mockElement

        let analytics = MockAnalyticsCollector()

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: mockSTT,
            llmClient: mockLLM,
            snippetEngine: snippets,
            accessibility: mockAccessibility,
            analytics: analytics
        )

        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        appState.activationKeyMonitor.onDeactivated?()
        try await Task.sleep(nanoseconds: 850_000_000)

        let failedEvent = analytics.events.first { $0.0 == .normalizationFailed }
        XCTAssertNotNil(failedEvent)
        XCTAssertEqual(failedEvent?.2[AnalyticsMetadataKey.normalizationPath], "snippetPlusLLM")
        XCTAssertEqual(
            failedEvent?.2[AnalyticsMetadataKey.fallbackUsed],
            PipelineResult.SnippetFallbackReason.llmFailed.analyticsValue
        )
        XCTAssertFalse(analytics.events.contains { $0.0 == .normalizationCompleted })

        let fallbackEvent = analytics.events.first { $0.0 == .snippetFallbackUsed }
        XCTAssertNotNil(fallbackEvent)
        XCTAssertEqual(
            fallbackEvent?.2[AnalyticsMetadataKey.fallbackUsed],
            PipelineResult.SnippetFallbackReason.llmFailed.analyticsValue
        )
    }

    // MARK: - 2. Cancel во время записи

    func test_cancel_during_recording() async {
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

    // MARK: - 3. Спам хоткея: повторная активация во время processing

    func test_reactivation_during_processing_ignored() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = Data([0x01])

        let controlledSTT = ControlledSTTClient()

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: controlledSTT
        )

        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .recording)

        appState.activationKeyMonitor.onDeactivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .processing)

        // Спам: повторная активация во время processing
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Должен остаться в processing, не крашить на alreadyRecording
        XCTAssertEqual(appState.sessionManager.state, .processing)

        controlledSTT.complete(with: STTResult(text: "test"))
        try await Task.sleep(nanoseconds: 800_000_000)
    }

    // MARK: - 4. Cancel во время обработки (LLM)

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

        try await Task.sleep(nanoseconds: 800_000_000)

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

        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertNotNil(appState.lastResult)
        XCTAssertEqual(appState.lastResult?.normalizedText, "Привет")
        XCTAssertEqual(appState.lastResult?.normalizationPath, .trivial)
        XCTAssertEqual(mockLLM.normalizeCalls.count, 0) // LLM не вызвали
    }

    func test_standard_mode_uses_deterministic_path_without_normalization_events() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = Data([0x01])

        let mockSTT = MockSTTClient()
        mockSTT.recognizeResult = STTResult(text: "привет марк ой точнее саша")

        let mockLLM = MockLLMClient()
        mockLLM.normalizeResult = "LLM не должен вызываться"

        let mockAccessibility = MockAccessibility()
        let mockElement = MockAXElement()
        mockElement.settableAttributes = ["AXSelectedText"]
        mockAccessibility.focusedElement = mockElement

        let analytics = MockAnalyticsCollector()

        let (appState, _, _) = makeTestAppState(
            mockAudio: mockAudio,
            sttClient: mockSTT,
            llmClient: mockLLM,
            accessibility: mockAccessibility,
            analytics: analytics,
            productMode: .standard
        )

        appState.activationKeyMonitor.onActivated?()
        await Task.yield()
        appState.activationKeyMonitor.onDeactivated?()
        await Task.yield()

        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(appState.lastResult?.normalizedText, "Привет марк ой точнее саша")
        XCTAssertEqual(appState.lastResult?.normalizationPath, .trivial)
        XCTAssertEqual(mockLLM.normalizeCalls.count, 0)
        XCTAssertFalse(analytics.events.contains { $0.0 == .normalizationCompleted })
        XCTAssertFalse(analytics.events.contains { $0.0 == .normalizationFailed })
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

        try await Task.sleep(nanoseconds: 800_000_000)

        // State machine перешла в error
        if case .error = appState.sessionManager.state {
            // OK
        } else {
            XCTFail("Expected error state, got \(appState.sessionManager.state)")
        }
        XCTAssertNil(appState.lastResult)
    }

    // MARK: - 7. Start/stop lifecycle

    func test_start_stop_lifecycle() {
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

        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertNotNil(appState.lastResult)
        XCTAssertEqual(appState.lastResult?.normalizedText, "Привет, Саша")
        XCTAssertEqual(mockClipboard.setStringValue, "Привет, Саша")
        XCTAssertEqual(mockClipboard.simulatePasteCallCount, 1)
    }

    // MARK: - 9. Cancel во время minProcessingDisplay

    func test_cancel_during_minProcessingDisplay_prevents_insertion() async throws {
        let mockAudio = MockAudioRecording()
        mockAudio.audioData = Data([0x01])

        let mockSTT = MockSTTClient()
        mockSTT.recognizeResult = STTResult(text: "тест")

        let mockLLM = MockLLMClient()
        mockLLM.normalizeResult = "Тест."

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
        try await Task.sleep(nanoseconds: 50_000_000)

        appState.activationKeyMonitor.onDeactivated?()
        // STT мгновенный → pipeline входит в minProcessingDisplay sleep (600ms)
        try await Task.sleep(nanoseconds: 200_000_000)

        appState.cancelProcessing()

        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertNil(appState.lastResult, "После Esc текст не должен вставляться")
    }

    // MARK: - 10. Toggle mode: полный pipeline

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

        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertNotNil(appState.lastResult)
        XCTAssertEqual(appState.lastResult?.normalizedText, "Привет")
    }

    // MARK: - 10. Toggle mode: cancel через onCancelled

    func test_toggle_cancel_during_recording() async {
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

        try await Task.sleep(nanoseconds: 800_000_000)

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
