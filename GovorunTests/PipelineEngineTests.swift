@testable import Govorun
import XCTest

// MARK: - Мок AudioRecording

final class MockAudioRecording: AudioRecording, @unchecked Sendable {
    var isRecording: Bool = false
    var duration: TimeInterval = 0
    var currentLevel: Float = 0
    weak var delegate: AudioCaptureDelegate?

    var audioData = Data(repeating: 0xab, count: 3_200)
    var startError: Error?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private let lock = NSLock()

    func startRecording() throws {
        lock.lock()
        startCallCount += 1
        lock.unlock()

        if let error = startError {
            throw error
        }
        isRecording = true
    }

    func stopRecording() -> Data {
        lock.lock()
        stopCallCount += 1
        lock.unlock()

        isRecording = false
        return audioData
    }
}

// MARK: - Мок SnippetMatching

final class MockSnippetEngine: SnippetMatching, @unchecked Sendable {
    var matchResults: [String: SnippetMatch] = [:]

    func configureStandalone(_ trigger: String, content: String) {
        matchResults[trigger.lowercased()] = SnippetMatch(
            trigger: trigger, content: content, kind: .standalone
        )
    }

    func configureEmbedded(_ trigger: String, content: String, forInput input: String) {
        matchResults[input.lowercased()] = SnippetMatch(
            trigger: trigger, content: content, kind: .embedded
        )
    }

    func match(_ text: String) -> SnippetMatch? {
        matchResults[text.lowercased()]
    }
}

// MARK: - Хелперы

private func makePipeline(
    audio: MockAudioRecording = MockAudioRecording(),
    stt: MockSTTClient = MockSTTClient(),
    llm: MockLLMClient = MockLLMClient(),
    snippets: MockSnippetEngine? = nil,
    saveAudioFile: (@Sendable (Data, UUID) throws -> String)? = nil
) -> (PipelineEngine, MockAudioRecording, MockSTTClient, MockLLMClient) {
    let engine = PipelineEngine(
        audioCapture: audio,
        sttClient: stt,
        llmClient: llm,
        snippetEngine: snippets,
        saveAudioFile: saveAudioFile
    )
    return (engine, audio, stt, llm)
}

// MARK: - Тесты PipelineEngine

final class PipelineEngineTests: XCTestCase {
    // MARK: - 1. start начинает запись

    func test_start_begins_audio_capture() throws {
        let audio = MockAudioRecording()
        let (engine, _, _, _) = makePipeline(audio: audio)

        try engine.startRecording(sessionId: UUID())

        XCTAssertEqual(audio.startCallCount, 1)
        XCTAssertTrue(audio.isRecording)
    }

    // MARK: - 2. stop → полный pipeline → result

    func test_stop_triggers_full_pipeline() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет марк ой точнее саша")

        let llm = MockLLMClient()
        llm.normalizeResult = "Привет, Саша"

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.rawTranscript, "привет марк ой точнее саша")
        XCTAssertEqual(result.normalizedText, "Привет, Саша")
        XCTAssertEqual(result.normalizationPath, .llm)
    }

    func test_updateLLMClient_switchesRuntimeForNextNormalization() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет саша")

        let initialLLM = MockLLMClient()
        initialLLM.normalizeResult = "Старый ответ"

        let nextLLM = MockLLMClient()
        nextLLM.normalizeResult = "Привет саша."

        let (engine, _, _, _) = makePipeline(stt: stt, llm: initialLLM)
        engine.updateLLMClient(nextLLM)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Привет саша.")
        XCTAssertEqual(initialLLM.normalizeCalls.count, 0)
        XCTAssertEqual(nextLLM.normalizeCalls.count, 1)
    }

    // MARK: - 3. cancel останавливает всё

    func test_cancel_stops_everything() throws {
        let audio = MockAudioRecording()
        let (engine, _, _, _) = makePipeline(audio: audio)

        try engine.startRecording(sessionId: UUID())
        engine.cancel()

        XCTAssertEqual(audio.stopCallCount, 1)
        XCTAssertFalse(audio.isRecording)
    }

    // MARK: - 4. STT ошибка → PipelineError

    func test_stt_failure_reports_error() async {
        let stt = MockSTTClient()
        stt.recognizeError = STTError.connectionFailed("timeout")

        let (engine, _, _, _) = makePipeline(stt: stt)

        try? engine.startRecording(sessionId: UUID())

        do {
            _ = try await engine.stopRecording()
            XCTFail("Должен был выбросить PipelineError")
        } catch let error as PipelineError {
            if case .sttFailed = error {
                // Ожидаемо
            } else {
                XCTFail("Ожидалась PipelineError.sttFailed, получили \(error)")
            }
        } catch {
            XCTFail("Ожидалась PipelineError, получили \(error)")
        }
    }

    // MARK: - 5. LLM ошибка → graceful degradation (возвращаем deterministicText)

    func test_llm_failure_returns_deterministic() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "ну короче давай завтра созвонимся")

        let llm = MockLLMClient()
        llm.normalizeError = LLMError.serverError(statusCode: 500)

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        // Graceful degradation: вернули deterministicText (без филлеров)
        XCTAssertEqual(result.normalizedText, "Давай завтра созвонимся.")
        XCTAssertEqual(result.rawTranscript, "ну короче давай завтра созвонимся")
        XCTAssertEqual(result.normalizationPath, .llmFailed)
    }

    // MARK: - 6. Latency tracking

    func test_latency_tracked() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "тестовый текст для проверки latency")

        let llm = MockLLMClient()
        llm.normalizeResult = "Тестовый текст для проверки latency."

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertGreaterThanOrEqual(result.sttLatencyMs, 0)
        XCTAssertGreaterThanOrEqual(result.llmLatencyMs, 0)
        XCTAssertGreaterThanOrEqual(result.totalLatencyMs, 0)
        XCTAssertEqual(result.insertionLatencyMs, 0) // заполняется позже
    }

    // MARK: - 7. Пустой транскрипт → не ходим в LLM

    func test_empty_transcript_skips_llm() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "")

        let llm = MockLLMClient()

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "")
        XCTAssertEqual(result.normalizationPath, .trivial)
        XCTAssertEqual(llm.normalizeCalls.count, 0)
    }

    func test_audio_history_save_failure_does_not_break_pipeline() async throws {
        struct SaveFailure: Error {}

        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "ок")

        let llm = MockLLMClient()

        let (engine, _, _, _) = makePipeline(
            stt: stt,
            llm: llm,
            saveAudioFile: { _, _ in
                throw SaveFailure()
            }
        )
        engine.saveAudioHistory = true

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Ок.")
        XCTAssertNil(result.audioFileName)
        XCTAssertEqual(result.normalizationPath, .trivial)
        XCTAssertEqual(llm.normalizeCalls.count, 0)
    }

    // MARK: - 8. Trivial text → DeterministicNormalizer, LLM НЕ вызван

    func test_trivial_text_skips_llm() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "ок")

        let llm = MockLLMClient()

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Ок.")
        XCTAssertEqual(result.normalizationPath, .trivial)
        XCTAssertEqual(llm.normalizeCalls.count, 0)
    }

    // MARK: - 9. Текст с числами → LLM вызван

    func test_text_with_numbers_goes_to_llm() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "в 3 часа")

        let llm = MockLLMClient()
        llm.normalizeResult = "В 3 часа."

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizationPath, .llm)
        XCTAssertEqual(llm.normalizeCalls.count, 1)
    }

    // MARK: - 10. Текст с коррекцией → LLM вызван

    func test_text_with_correction_goes_to_llm() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет ой точнее")

        let llm = MockLLMClient()
        llm.normalizeResult = "Привет."

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizationPath, .llm)
        XCTAssertEqual(llm.normalizeCalls.count, 1)
    }

    // MARK: - 11. LLM вернул пустоту → fallback на deterministicText

    func test_llm_returns_empty_falls_back_to_deterministic() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "давай сделаем это")

        let llm = MockLLMClient()
        llm.normalizeResult = "" // LLM выкинул всё

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        // Gate отклоняет пустой ответ и возвращает deterministicText
        XCTAssertEqual(result.normalizedText, "Давай сделаем это.")
        XCTAssertEqual(result.normalizationPath, .llmRejected)
        XCTAssertEqual(result.gateFailureReason, .empty)
    }

    /// 11b. LLM вернул safety refusal → fallback на deterministicText
    func test_llm_safety_refusal_falls_back_to_deterministic() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "федя ты дурачок")

        let llm = MockLLMClient()
        llm.normalizeResult = "К сожалению, иногда генеративные языковые модели могут создавать некорректные ответы"

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Федя ты дурачок.")
        XCTAssertEqual(result.normalizationPath, .llmRejected)
        XCTAssertEqual(result.gateFailureReason, .refusal)
    }

    // MARK: - 11d. Gate: пропажа защищённых токенов → fallback на deterministicText

    func test_llm_missing_protected_tokens_falls_back_to_deterministic() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "открой jira в 15:30")

        let llm = MockLLMClient()
        llm.normalizeResult = "Открой задачу."

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Открой jira в 15:30.")
        XCTAssertEqual(result.normalizationPath, .llmRejected)
        guard case .missingProtectedTokens(let tokens)? = result.gateFailureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.gateFailureReason))")
        }
        XCTAssertTrue(tokens.contains("jira"))
    }

    // MARK: - 11c. LLM бросает non-cancelled PipelineError → fallback на deterministicText

    func test_stopRecording_llmThrowsNonCancelledPipelineError_fallbackToDeterministic() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет мир как дела", confidence: 0.9)

        let llm = MockLLMClient()
        llm.normalizeError = PipelineError.sttFailed("test error")

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()
        XCTAssertEqual(result.normalizedText, "Привет мир как дела.")
        XCTAssertEqual(result.normalizationPath, .llmFailed)
    }

    // MARK: - 12. Snippet standalone match → LLM НЕ вызван

    func test_snippet_match_skips_llm() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "мой имейл")

        let llm = MockLLMClient()

        let snippets = MockSnippetEngine()
        snippets.configureStandalone("мой имейл", content: "sanya@example.com")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "sanya@example.com")
        XCTAssertEqual(result.normalizationPath, .snippet)
        XCTAssertEqual(result.matchedSnippetTrigger, "мой имейл")
        XCTAssertEqual(llm.normalizeCalls.count, 0)
        XCTAssertFalse(result.snippetFallbackUsed)
        XCTAssertNil(result.snippetFallbackReason)
    }

    // MARK: - 13. Snippet match → matchedSnippetTrigger содержит trigger

    func test_snippet_match_populates_trigger() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "мой телефон")

        let snippets = MockSnippetEngine()
        snippets.configureStandalone("мой телефон", content: "+7 999 123-45-67")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: MockLLMClient(),
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.matchedSnippetTrigger, "мой телефон")
        XCTAssertEqual(result.normalizedText, "+7 999 123-45-67")
        XCTAssertEqual(result.normalizationPath, .snippet)
    }

    // MARK: - 14. Non-snippet result → matchedSnippetTrigger nil

    func test_non_snippet_result_has_nil_trigger() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет марк ой точнее саша")

        let llm = MockLLMClient()
        llm.normalizeResult = "Привет, Саша"

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertNil(result.matchedSnippetTrigger)
    }

    // MARK: - 15. Standalone → LLM не вызывался, llmLatencyMs == 0

    func test_pipeline_standalone_returns_content_without_llm() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "мой адрес")

        let llm = MockLLMClient()

        let snippets = MockSnippetEngine()
        snippets.configureStandalone("мой адрес", content: "Аминева 9")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Аминева 9")
        XCTAssertEqual(result.normalizationPath, .snippet)
        XCTAssertEqual(result.llmLatencyMs, 0)
        XCTAssertEqual(llm.normalizeCalls.count, 0)
        XCTAssertFalse(result.snippetFallbackUsed)
        XCTAssertNil(result.snippetFallbackReason)
    }

    // MARK: - 16. Embedded happy path → placeholder → reinsertion

    func test_pipeline_embedded_sends_deterministic_baseline_to_llm_with_snippet_context() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет вот мой адрес")

        let llm = MockLLMClient()
        llm.normalizeResult = "Привет, мой адрес — [[[GOVORUN_SNIPPET]]]."

        let snippets = MockSnippetEngine()
        snippets.configureEmbedded("мой адрес", content: "Аминева 9", forInput: "привет вот мой адрес")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Привет, мой адрес — Аминева 9.")
        XCTAssertEqual(result.normalizationPath, .snippetPlusLLM)
        XCTAssertFalse(result.snippetFallbackUsed)
        XCTAssertEqual(result.matchedSnippetTrigger, "мой адрес")

        // LLM получил общий deterministic baseline, а не raw transcript / snippet content
        XCTAssertEqual(llm.normalizeCalls.count, 1)
        XCTAssertEqual(llm.normalizeCalls.first?.text, "Привет мой адрес.")
        XCTAssertNotNil(llm.normalizeCalls.first?.hints.snippetContext)
    }

    func test_pipeline_embedded_happy_path_respects_terminal_period_setting() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет вот мой адрес")

        let llm = MockLLMClient()
        llm.normalizeResult = "Привет, мой адрес — [[[GOVORUN_SNIPPET]]]."

        let snippets = MockSnippetEngine()
        snippets.configureEmbedded("мой адрес", content: "Аминева 9", forInput: "привет вот мой адрес")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )
        engine.terminalPeriodEnabled = false

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Привет, мой адрес — Аминева 9")
        XCTAssertEqual(result.normalizationPath, .snippetPlusLLM)
        XCTAssertFalse(result.snippetFallbackUsed)
    }

    // MARK: - 17. Embedded fallback: LLM не вернул placeholder

    func test_pipeline_embedded_fallback_when_no_placeholder() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет вот мой адрес")

        let llm = MockLLMClient()
        llm.normalizeResult = "Привет, мой адрес — Аминева 9." // без placeholder

        let snippets = MockSnippetEngine()
        snippets.configureEmbedded("мой адрес", content: "Аминева 9", forInput: "привет вот мой адрес")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Привет мой адрес: Аминева 9.")
        XCTAssertTrue(result.snippetFallbackUsed)
        XCTAssertEqual(result.normalizationPath, .snippetPlusLLM)
        XCTAssertEqual(result.snippetFallbackReason, .gateRejected)
    }

    // MARK: - 18. Embedded fallback: placeholder приклеен к слову

    func test_pipeline_embedded_fallback_when_placeholder_glued() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет вот мой адрес")

        let llm = MockLLMClient()
        llm.normalizeResult = "Привет вот мой адрес[[[GOVORUN_SNIPPET]]]."

        let snippets = MockSnippetEngine()
        snippets.configureEmbedded("мой адрес", content: "Аминева 9", forInput: "привет вот мой адрес")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Привет мой адрес: Аминева 9.")
        XCTAssertTrue(result.snippetFallbackUsed)
        XCTAssertEqual(result.snippetFallbackReason, .reinsertionFailed)
    }

    // MARK: - 19. Embedded fallback: LLM ошибка

    func test_pipeline_embedded_fallback_when_llm_fails() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "лена вот мой адрес")

        let llm = MockLLMClient()
        llm.normalizeError = LLMError.serverError(statusCode: 500)

        let snippets = MockSnippetEngine()
        snippets.configureEmbedded("мой адрес", content: "Аминева 9", forInput: "лена вот мой адрес")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Лена мой адрес: Аминева 9.")
        XCTAssertTrue(result.snippetFallbackUsed)
        XCTAssertEqual(result.normalizationPath, .snippetPlusLLM)
        XCTAssertEqual(result.snippetFallbackReason, .llmFailed)
    }

    // MARK: - 20. Embedded fallback: LLM refusal

    func test_pipeline_embedded_fallback_when_llm_returns_refusal() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет вот мой адрес")

        let llm = MockLLMClient()
        llm.normalizeResult = "К сожалению, я не могу обработать этот запрос. [[[GOVORUN_SNIPPET]]]"

        let snippets = MockSnippetEngine()
        snippets.configureEmbedded("мой адрес", content: "Аминева 9", forInput: "привет вот мой адрес")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Привет мой адрес: Аминева 9.")
        XCTAssertTrue(result.snippetFallbackUsed)
        XCTAssertEqual(result.gateFailureReason, .refusal)
        XCTAssertEqual(result.snippetFallbackReason, .gateRejected)
    }

    // MARK: - 20b. Embedded fallback: gate reject до reinsertion

    func test_pipeline_embedded_fallback_when_gate_rejects_output() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет вот мой адрес")

        let llm = MockLLMClient()
        llm.normalizeResult = "Вот [[[GOVORUN_SNIPPET]]]."

        let snippets = MockSnippetEngine()
        snippets.configureEmbedded("мой адрес", content: "Аминева 9", forInput: "привет вот мой адрес")

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Привет мой адрес: Аминева 9.")
        XCTAssertTrue(result.snippetFallbackUsed)
        XCTAssertEqual(result.snippetFallbackReason, .gateRejected)
        guard case .excessiveEdits? = result.gateFailureReason else {
            return XCTFail("Ожидалась excessiveEdits, получили \(String(describing: result.gateFailureReason))")
        }
    }

    // MARK: - 21. No snippet → no snippetContext in hints

    func test_pipeline_no_snippet_sends_no_context() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет мир как дела")

        let llm = MockLLMClient()
        llm.normalizeResult = "Привет, мир, как дела."

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        _ = try await engine.stopRecording()

        XCTAssertNil(llm.normalizeCalls.first?.hints.snippetContext)
    }

    // MARK: - Personal Dictionary hints

    func test_llm_receives_personal_dictionary() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "жира не отвечает")

        let llm = MockLLMClient()
        llm.normalizeResult = "Jira не отвечает."

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)
        engine.hints = NormalizationHints(
            personalDictionary: ["жира": "Jira"],
            appName: "Telegram",
            textMode: .chat
        )

        try engine.startRecording(sessionId: UUID())
        _ = try await engine.stopRecording()

        XCTAssertEqual(llm.normalizeCalls.first?.hints.personalDictionary, ["жира": "Jira"])
    }

    // MARK: - applyReplacements в pipeline

    func test_pipeline_applies_dictionary_replacements_before_llm() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "открой жира и слак")

        let llm = MockLLMClient()
        llm.normalizeResult = "Открой Jira и Slack."

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)
        engine.hints = NormalizationHints(
            personalDictionary: ["жира": "Jira", "слак": "Slack"],
            appName: nil,
            textMode: .chat
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        // LLM получил текст ПОСЛЕ замен
        let llmInput = llm.normalizeCalls.first?.text ?? ""
        XCTAssertTrue(
            llmInput.contains("Jira"),
            "LLM должен получить 'Jira' (после замены), а получил: \(llmInput)"
        )
        XCTAssertTrue(
            llmInput.contains("Slack"),
            "LLM должен получить 'Slack' (после замены), а получил: \(llmInput)"
        )
        XCTAssertFalse(
            llmInput.contains("жира"),
            "LLM НЕ должен получить 'жира' (до замены), а получил: \(llmInput)"
        )

        // rawTranscript сохраняет оригинал
        XCTAssertEqual(result.rawTranscript, "открой жира и слак")
    }

    func test_pipeline_regular_llm_receives_deterministic_numeric_baseline() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(
            text: "ну напомни про двадцать пять процентов и тысяча рублей в пять часов для двух дизайнеров"
        )

        let llm = MockLLMClient()
        llm.normalizeResult = "Напомни про 25% и 1 000 рублей в 5:00 для двух дизайнеров."

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)

        try engine.startRecording(sessionId: UUID())
        _ = try await engine.stopRecording()

        XCTAssertEqual(
            llm.normalizeCalls.first?.text,
            "Напомни про 25% и 1 000 рублей в 5:00 для двух дизайнеров."
        )
    }

    func test_pipeline_embedded_llm_receives_same_deterministic_numeric_baseline() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(
            text: "привет вот мой адрес и напомни про двадцать пять процентов и тысяча рублей в пять часов для двух дизайнеров"
        )

        let llm = MockLLMClient()
        llm.normalizeResult = "Привет, мой адрес — [[[GOVORUN_SNIPPET]]], и напомни про 25% и 1 000 рублей в 5:00 для двух дизайнеров."

        let snippets = MockSnippetEngine()
        snippets.configureEmbedded(
            "мой адрес",
            content: "Аминева 9",
            forInput: "привет вот мой адрес и напомни про двадцать пять процентов и тысяча рублей в пять часов для двух дизайнеров"
        )

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(
            llm.normalizeCalls.first?.text,
            "Привет мой адрес и напомни про 25% и 1 000 рублей в 5:00 для двух дизайнеров."
        )
        XCTAssertEqual(
            result.normalizedText,
            "Привет, мой адрес — Аминева 9, и напомни про 25% и 1 000 рублей в 5:00 для двух дизайнеров."
        )
    }

    func test_pipeline_embedded_fallback_uses_deterministic_numeric_baseline() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(
            text: "привет вот мой адрес и напомни про двадцать пять процентов и тысяча рублей в пять часов для двух дизайнеров"
        )

        let llm = MockLLMClient()
        llm.normalizeError = LLMError.serverError(statusCode: 500)

        let snippets = MockSnippetEngine()
        snippets.configureEmbedded(
            "мой адрес",
            content: "Аминева 9",
            forInput: "привет вот мой адрес и напомни про двадцать пять процентов и тысяча рублей в пять часов для двух дизайнеров"
        )

        let engine = PipelineEngine(
            audioCapture: MockAudioRecording(),
            sttClient: stt,
            llmClient: llm,
            snippetEngine: snippets
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(
            result.normalizedText,
            "Привет мой адрес: Аминева 9 и напомни про 25% и 1 000 рублей в 5:00 для двух дизайнеров."
        )
        XCTAssertEqual(result.snippetFallbackReason, .llmFailed)
    }

    func test_pipeline_replacements_applied_for_trivial_text() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "жира")

        let llm = MockLLMClient()
        // LLM не должен вызываться (trivial text)

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)
        engine.hints = NormalizationHints(
            personalDictionary: ["жира": "Jira"],
            appName: nil,
            textMode: .chat
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        // Замена применена, DeterministicNormalizer добавил точку и капитализацию
        XCTAssertEqual(result.normalizedText, "Jira.")
        XCTAssertEqual(result.rawTranscript, "жира")
        XCTAssertEqual(llm.normalizeCalls.count, 0, "Trivial text не должен вызывать LLM")
    }

    func test_pipeline_empty_dictionary_no_changes() async throws {
        let stt = MockSTTClient()
        stt.recognizeResult = STTResult(text: "привет")

        let llm = MockLLMClient()

        let (engine, _, _, _) = makePipeline(stt: stt, llm: llm)
        engine.hints = NormalizationHints(
            personalDictionary: [:],
            appName: nil,
            textMode: .chat
        )

        try engine.startRecording(sessionId: UUID())
        let result = try await engine.stopRecording()

        XCTAssertEqual(result.normalizedText, "Привет.")
    }
}

// MARK: - DeterministicNormalizer тесты (расширенный)

final class DeterministicNormalizerTests: XCTestCase {
    // MARK: - Базовые (одно слово)

    func test_capitalize_and_period() {
        XCTAssertEqual(DeterministicNormalizer.normalize("привет"), "Привет.")
    }

    func test_keeps_existing_punctuation() {
        XCTAssertEqual(DeterministicNormalizer.normalize("да!"), "Да!")
    }

    func test_solo_filler_returns_empty() {
        XCTAssertEqual(DeterministicNormalizer.normalize("ну"), "")
        XCTAssertEqual(DeterministicNormalizer.normalize("ээ"), "")
        XCTAssertEqual(DeterministicNormalizer.normalize("ммм"), "")
        XCTAssertEqual(DeterministicNormalizer.normalize("блин"), "")
        XCTAssertEqual(DeterministicNormalizer.normalize("типа"), "")
        XCTAssertEqual(DeterministicNormalizer.normalize("короче"), "")
    }

    func test_empty_input() {
        XCTAssertEqual(DeterministicNormalizer.normalize(""), "")
        XCTAssertEqual(DeterministicNormalizer.normalize("   "), "")
    }

    func test_case_insensitive_filler_check() {
        XCTAssertEqual(DeterministicNormalizer.normalize("Ну"), "")
        XCTAssertEqual(DeterministicNormalizer.normalize("НУ"), "")
    }

    // MARK: - Замены слов

    func test_ok_replacement() {
        XCTAssertEqual(DeterministicNormalizer.normalize("ок"), "Ок.")
    }

    func test_okey_replacement() {
        XCTAssertEqual(DeterministicNormalizer.normalize("окей"), "Окей.")
    }

    func test_ok_in_sentence() {
        XCTAssertEqual(DeterministicNormalizer.normalize("ок понял"), "Ок понял.")
    }

    // MARK: - Удаление филлеров из многословного текста

    func test_remove_fillers_from_sentence() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("ну привет типа как дела"),
            "Привет как дела."
        )
    }

    func test_remove_filler_phrase_kak_by() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("это как бы важно"),
            "Это важно."
        )
    }

    func test_remove_filler_phrase_eto_samoe() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("это самое пойдём домой"),
            "Пойдём домой."
        )
    }

    func test_remove_multiple_fillers() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("ну вот короче давай"),
            "Давай."
        )
    }

    func test_all_fillers_returns_empty() {
        XCTAssertEqual(DeterministicNormalizer.normalize("ну эм вот"), "")
    }

    // MARK: - Капитализация после ./?/!

    func test_capitalize_after_period() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет. как дела"),
            "Привет. Как дела."
        )
    }

    func test_capitalize_after_question() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("да? конечно"),
            "Да? Конечно."
        )
    }

    func test_capitalize_after_exclamation() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет! рад видеть"),
            "Привет! Рад видеть."
        )
    }

    // MARK: - Двойные пробелы

    func test_remove_double_spaces() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет  мир"),
            "Привет мир."
        )
    }

    func test_remove_spaces_after_filler_removal() {
        // После удаления филлера "ну" остаётся двойной пробел
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет ну мир"),
            "Привет мир."
        )
    }

    // MARK: - Комбинированные случаи

    func test_fillers_removed_ok_stays() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("ну окей понял"),
            "Окей понял."
        )
    }

    func test_preserves_punctuation_in_middle() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет, мир"),
            "Привет, мир."
        )
    }

    // MARK: - Terminal period policy

    func test_period_on_plain_text() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет", terminalPeriodEnabled: true),
            "Привет."
        )
    }

    func test_period_on_existing_period() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет.", terminalPeriodEnabled: true),
            "Привет."
        )
    }

    func test_no_period_plain_text() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет", terminalPeriodEnabled: false),
            "Привет"
        )
    }

    func test_no_period_strips_existing() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет.", terminalPeriodEnabled: false),
            "Привет"
        )
    }

    func test_no_period_strips_multiple_dots() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет...", terminalPeriodEnabled: false),
            "Привет"
        )
    }

    func test_no_period_strips_after_percent() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("двадцать пять процентов.", terminalPeriodEnabled: false),
            "25%"
        )
    }

    func test_no_period_preserves_exclamation() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("да!", terminalPeriodEnabled: false),
            "Да!"
        )
    }

    func test_no_period_preserves_question() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("что делаешь?", terminalPeriodEnabled: false),
            "Что делаешь?"
        )
    }

    func test_no_period_preserves_ellipsis_char() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("тест\u{2026}", terminalPeriodEnabled: false),
            "Тест\u{2026}"
        )
    }

    func test_no_period_empty_text() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("", terminalPeriodEnabled: false),
            ""
        )
    }

    func test_no_period_multisentence_strips_only_trailing() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("привет. пока", terminalPeriodEnabled: false),
            "Привет. Пока"
        )
    }

    // MARK: - stripTrailingPeriods (post-LLM)

    func test_stripTrailingPeriods_removes_single_period() {
        XCTAssertEqual(DeterministicNormalizer.stripTrailingPeriods("Привет."), "Привет")
    }

    func test_stripTrailingPeriods_preserves_question() {
        XCTAssertEqual(DeterministicNormalizer.stripTrailingPeriods("Как дела?"), "Как дела?")
    }

    func test_stripTrailingPeriods_preserves_exclamation() {
        XCTAssertEqual(DeterministicNormalizer.stripTrailingPeriods("Да!"), "Да!")
    }

    func test_stripTrailingPeriods_noop_without_period() {
        XCTAssertEqual(DeterministicNormalizer.stripTrailingPeriods("Привет"), "Привет")
    }
}

// MARK: - LLMResponseGuard тесты

final class LLMResponseGuardTests: XCTestCase {
    func test_firstIssue_returns_empty_for_blank_response() {
        XCTAssertEqual(
            LLMResponseGuard.firstIssue("   ", rawTranscript: "привет"),
            .empty
        )
    }

    func test_firstIssue_returns_refusal_for_safety_response() {
        XCTAssertEqual(
            LLMResponseGuard.firstIssue("К сожалению, не могу помочь.", rawTranscript: "привет"),
            .refusal
        )
    }

    func test_firstIssue_returns_disproportionate_length_for_explanation() {
        let input = "федя ты дурачок"
        let output = "Федя, ты дурачок. Однако хочу заметить что такие выражения не стоит использовать в деловой переписке потому что они могут обидеть собеседника"
        XCTAssertEqual(
            LLMResponseGuard.firstIssue(output, rawTranscript: input),
            .disproportionateLength
        )
    }

    func test_firstIssue_returns_nil_for_normal_response() {
        XCTAssertNil(
            LLMResponseGuard.firstIssue("Привет, Федя.", rawTranscript: "привет федя")
        )
    }

    func test_normal_response_is_usable() {
        XCTAssertTrue(LLMResponseGuard.isUsable("Привет, Федя.", rawTranscript: "привет федя"))
    }

    func test_empty_response_not_usable() {
        XCTAssertFalse(LLMResponseGuard.isUsable("", rawTranscript: "привет"))
        XCTAssertFalse(LLMResponseGuard.isUsable("   ", rawTranscript: "привет"))
    }

    func test_safety_refusal_not_usable() {
        let refusal = "К сожалению, иногда генеративные языковые модели могут создавать некорректные ответы"
        XCTAssertFalse(LLMResponseGuard.isUsable(refusal, rawTranscript: "федя ты дурачок"))
    }

    func test_refusal_case_insensitive() {
        XCTAssertFalse(LLMResponseGuard.isUsable("к сожалению, не могу", rawTranscript: "тест"))
        XCTAssertFalse(LLMResponseGuard.isUsable("Извините, я не могу обработать", rawTranscript: "тест"))
        XCTAssertFalse(LLMResponseGuard.isUsable("Я не могу выполнить запрос", rawTranscript: "тест"))
    }

    func test_disproportionate_length_not_usable() {
        let input = "федя ты дурачок" // 3 слова
        let longOutput = "Федя, ты дурачок. Однако хочу заметить что такие выражения не стоит использовать в деловой переписке потому что они могут обидеть собеседника"
        XCTAssertFalse(LLMResponseGuard.isUsable(longOutput, rawTranscript: input))
    }

    func test_proportionate_response_usable() {
        let input = "ну привет саня давай встретимся" // 5 слов
        let output = "Привет, Саня, давай встретимся." // 4 слова
        XCTAssertTrue(LLMResponseGuard.isUsable(output, rawTranscript: input))
    }

    func test_slightly_longer_response_usable() {
        // Нормализация может добавить пару слов (даты, пунктуация) — это ОК
        let input = "встретимся завтра в пять" // 4 слова
        let output = "Встретимся завтра, 12 марта, в 17:00." // 6 слов — допустимо
        XCTAssertTrue(LLMResponseGuard.isUsable(output, rawTranscript: input))
    }

    func test_short_response_under_threshold_always_usable() {
        // Даже если ratio > 3x, но outputWords ≤ 10 — это нормально
        let input = "да" // 1 слово
        let output = "Да." // 1 слово
        XCTAssertTrue(LLMResponseGuard.isUsable(output, rawTranscript: input))
    }

    /// Пользователь диктует фразу, начинающуюся с refusal-префикса — НЕ блокируем
    func test_user_dictates_k_sozhaleniyu_not_blocked() {
        let input = "к сожалению встреча отменяется"
        let output = "К сожалению, встреча отменяется."
        XCTAssertTrue(LLMResponseGuard.isUsable(output, rawTranscript: input))
    }

    func test_user_dictates_izvinite_not_blocked() {
        let input = "извините я опоздаю на полчаса"
        let output = "Извините, я опоздаю на 30 минут."
        XCTAssertTrue(LLMResponseGuard.isUsable(output, rawTranscript: input))
    }

    func test_refusal_when_raw_differs() {
        // raw НЕ начинается с «к сожалению» → это refusal от LLM
        let input = "федя ты дурачок"
        let output = "К сожалению, я не могу обработать данный запрос."
        XCTAssertFalse(LLMResponseGuard.isUsable(output, rawTranscript: input))
    }
}

// MARK: - isTrivial тесты

final class IsTrivialTests: XCTestCase {
    func test_single_word_is_trivial() {
        XCTAssertTrue(NormalizationPipeline.isTrivial("ок"))
        XCTAssertTrue(NormalizationPipeline.isTrivial("привет"))
    }

    func test_two_words_not_trivial() {
        XCTAssertFalse(NormalizationPipeline.isTrivial("да конечно"))
        XCTAssertFalse(NormalizationPipeline.isTrivial("привет мир"))
    }

    func test_long_text_not_trivial() {
        XCTAssertFalse(NormalizationPipeline.isTrivial("это длинный текст с множеством слов"))
    }

    func test_numbers_not_trivial() {
        XCTAssertFalse(NormalizationPipeline.isTrivial("в 3 часа"))
    }

    func test_correction_marker_not_trivial() {
        XCTAssertFalse(NormalizationPipeline.isTrivial("привет точнее"))
    }
}
