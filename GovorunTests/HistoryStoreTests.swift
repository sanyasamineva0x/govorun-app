@testable import Govorun
import SwiftData
import XCTest

final class HistoryStoreTests: XCTestCase {
    private func makeStore() throws -> HistoryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: HistoryItem.self,
            configurations: config
        )
        let context = ModelContext(container)
        return HistoryStore(modelContext: context)
    }

    private func makePipelineResult(
        rawTranscript: String = "тест",
        normalizedText: String = "Тест.",
        textMode: TextMode = .universal,
        normalizationPath: PipelineResult.NormalizationPath = .trivial,
        sttLatencyMs: Int = 100,
        llmLatencyMs: Int = 0,
        insertionLatencyMs: Int = 10,
        totalLatencyMs: Int = 150
    ) -> PipelineResult {
        PipelineResult(
            sessionId: UUID(),
            rawTranscript: rawTranscript,
            normalizedText: normalizedText,
            textMode: textMode,
            normalizationPath: normalizationPath,
            sttLatencyMs: sttLatencyMs,
            llmLatencyMs: llmLatencyMs,
            insertionLatencyMs: insertionLatencyMs,
            totalLatencyMs: totalLatencyMs
        )
    }

    private func makeAppContext(
        appName: String = "Telegram",
        bundleId: String = "ru.keepcoder.Telegram"
    ) -> AppContext {
        AppContext(bundleId: bundleId, appName: appName, textMode: .chat)
    }

    // MARK: - 1. Сохранение и чтение

    func test_save_and_retrieve() throws {
        let store = try makeStore()
        let result = makePipelineResult(
            rawTranscript: "привет марк ой точнее саша",
            normalizedText: "Привет, Саша.",
            normalizationPath: .llm,
            sttLatencyMs: 120,
            llmLatencyMs: 200,
            totalLatencyMs: 350
        )
        let context = makeAppContext()

        try store.save(result, appContext: context)

        let items = try store.recent()
        XCTAssertEqual(items.count, 1)

        let item = items[0]
        XCTAssertEqual(item.rawTranscript, "привет марк ой точнее саша")
        XCTAssertEqual(item.normalizedText, "Привет, Саша.")
        XCTAssertEqual(item.textMode, "universal")
        XCTAssertEqual(item.appName, "Telegram")
        XCTAssertEqual(item.normalizationPath, "llm")
        XCTAssertEqual(item.sttLatencyMs, 120)
        XCTAssertEqual(item.normalizationLatencyMs, 200)
        XCTAssertEqual(item.totalLatencyMs, 350)
    }

    // MARK: - 2. Автоочистка при превышении лимита

    func test_max_items_enforced() throws {
        let store = try makeStore()
        let context = makeAppContext()

        for i in 0..<105 {
            let result = makePipelineResult(normalizedText: "Item \(i)")
            try store.save(result, appContext: context)
        }

        let items = try store.recent(limit: 200)
        XCTAssertEqual(items.count, HistoryStore.maxItems)
    }

    // MARK: - 3. Очистка всей истории

    func test_clear_removes_all() throws {
        let store = try makeStore()
        let context = makeAppContext()

        for _ in 0..<5 {
            try store.save(makePipelineResult(), appContext: context)
        }

        try store.clear()

        let items = try store.recent()
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - 4. recent возвращает по убыванию даты

    func test_recent_ordered_newest_first() throws {
        let store = try makeStore()
        let context = makeAppContext()

        try store.save(makePipelineResult(normalizedText: "Первый"), appContext: context)
        try store.save(makePipelineResult(normalizedText: "Второй"), appContext: context)
        try store.save(makePipelineResult(normalizedText: "Третий"), appContext: context)

        let items = try store.recent()
        XCTAssertEqual(items[0].normalizedText, "Третий")
        XCTAssertEqual(items[1].normalizedText, "Второй")
        XCTAssertEqual(items[2].normalizedText, "Первый")
    }

    // MARK: - 5. recent с лимитом

    func test_recent_respects_limit() throws {
        let store = try makeStore()
        let context = makeAppContext()

        for _ in 0..<10 {
            try store.save(makePipelineResult(), appContext: context)
        }

        let items = try store.recent(limit: 3)
        XCTAssertEqual(items.count, 3)
    }

    // MARK: - 6. Пустой normalizedText не сохраняется

    func test_empty_normalized_text_ignored() throws {
        let store = try makeStore()
        let context = makeAppContext()

        try store.save(makePipelineResult(normalizedText: ""), appContext: context)

        let items = try store.recent()
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - 7. wordCount считается при сохранении

    func test_word_count_calculated() throws {
        let store = try makeStore()
        let context = makeAppContext()

        try store.save(
            makePipelineResult(normalizedText: "Привет мир как дела"),
            appContext: context
        )

        let items = try store.recent()
        XCTAssertEqual(items[0].wordCount, 4)
    }

    // MARK: - 7b. wordCount с \n и \t

    func test_save_countsWordsWithNewlines() throws {
        let store = try makeStore()
        let result = PipelineResult(
            sessionId: UUID(),
            rawTranscript: "привет\nмир\tтри",
            normalizedText: "привет\nмир\tтри",
            textMode: .universal,
            normalizationPath: .trivial,
            sttLatencyMs: 0,
            llmLatencyMs: 0,
            insertionLatencyMs: 0,
            totalLatencyMs: 0
        )
        try store.save(result, appContext: AppContext(bundleId: "", appName: "", textMode: .universal))
        let items = try store.recent()
        XCTAssertEqual(items.first?.wordCount, 3)
    }

    // MARK: - 8. sessionId сохраняется

    func test_session_id_preserved() throws {
        let store = try makeStore()
        let result = makePipelineResult()
        let context = makeAppContext()

        try store.save(result, appContext: context)

        let items = try store.recent()
        XCTAssertEqual(items[0].sessionId, result.sessionId)
    }

    // MARK: - 9. Snippet path сохраняется

    func test_snippet_path_saved() throws {
        let store = try makeStore()
        let context = makeAppContext()

        try store.save(
            makePipelineResult(normalizationPath: .snippet),
            appContext: context
        )

        let items = try store.recent()
        XCTAssertEqual(items[0].normalizationPath, "snippet")
    }

    // MARK: - 10. Автоочистка удаляет самые старые

    func test_auto_cleanup_removes_oldest() throws {
        let store = try makeStore()
        let context = makeAppContext()

        // Добавляем maxItems + 5
        for i in 0..<(HistoryStore.maxItems + 5) {
            let result = makePipelineResult(normalizedText: "Item \(i)")
            try store.save(result, appContext: context)
        }

        let items = try store.recent(limit: 200)
        XCTAssertEqual(items.count, HistoryStore.maxItems)

        // Самый новый = "Item 104", самый старый сохранённый = "Item 5"
        XCTAssertEqual(items.first?.normalizedText, "Item 104")
        XCTAssertEqual(items.last?.normalizedText, "Item 5")
    }

    // MARK: - 11. audioFileName сохраняется

    func test_audio_file_name_saved() throws {
        let store = try makeStore()
        let context = makeAppContext()

        var result = makePipelineResult()
        result.audioFileName = "test-session.wav"
        try store.save(result, appContext: context)

        let items = try store.recent()
        XCTAssertEqual(items[0].audioFileName, "test-session.wav")
    }

    // MARK: - 12. audioFileName nil когда не задан

    func test_audio_file_name_nil_by_default() throws {
        let store = try makeStore()
        let context = makeAppContext()

        try store.save(makePipelineResult(), appContext: context)

        let items = try store.recent()
        XCTAssertNil(items[0].audioFileName)
    }
}
