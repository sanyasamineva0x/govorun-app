import XCTest
import SwiftData
@testable import Govorun

final class DictionaryStoreTests: XCTestCase {

    private func makeStore() throws -> DictionaryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DictionaryEntry.self,
            configurations: config
        )
        let context = ModelContext(container)
        return DictionaryStore(modelContext: context)
    }

    // MARK: - 1. Добавление слова

    func test_add_word() throws {
        let store = try makeStore()

        try store.addWord("Jira", alternatives: ["жира", "джира"])

        let entries = try store.allEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.word, "Jira")
        XCTAssertEqual(entries.first?.alternatives, ["жира", "джира"])
        XCTAssertFalse(entries.first?.isAutoLearned ?? true)
    }

    // MARK: - 2. Удаление слова

    func test_remove_word() throws {
        let store = try makeStore()

        try store.addWord("Jira", alternatives: ["жира"])
        try store.removeWord("Jira")

        let entries = try store.allEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - 3. STT hints формат

    func test_stt_hints_format() throws {
        let store = try makeStore()

        try store.addWord("Jira", alternatives: ["жира"])
        try store.addWord("Slack", alternatives: ["слак"])

        let hints = try store.sttHints()
        XCTAssertEqual(Set(hints), Set(["Jira", "Slack"]))
    }

    // MARK: - 4. LLM replacements формат

    func test_llm_replacements_format() throws {
        let store = try makeStore()

        try store.addWord("Jira", alternatives: ["жира", "джира"])

        let replacements = try store.llmReplacements()
        XCTAssertEqual(replacements["жира"], "Jira")
        XCTAssertEqual(replacements["джира"], "Jira")
    }

    // MARK: - 5. Дубликат → мерж alternatives

    func test_duplicate_word_merged() throws {
        let store = try makeStore()

        try store.addWord("Jira", alternatives: ["жира"])
        try store.addWord("Jira", alternatives: ["джира"])

        let entries = try store.allEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(Set(entries.first?.alternatives ?? []), Set(["жира", "джира"]))
    }

    // MARK: - 6. Пустое слово не добавляется

    func test_empty_word_ignored() throws {
        let store = try makeStore()

        try store.addWord("", alternatives: ["foo"])
        try store.addWord("   ", alternatives: ["bar"])

        let entries = try store.allEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - 7. Удаление несуществующего → ошибка

    func test_remove_nonexistent_throws() throws {
        let store = try makeStore()

        XCTAssertThrowsError(try store.removeWord("НеСуществует")) { error in
            guard case DictionaryStoreError.wordNotFound = error else {
                XCTFail("Ожидалась DictionaryStoreError.wordNotFound")
                return
            }
        }
    }

    // MARK: - 8. Несколько слов → allEntries сортирован

    func test_all_entries_sorted() throws {
        let store = try makeStore()

        try store.addWord("Zoom", alternatives: ["зум"])
        try store.addWord("Asana", alternatives: ["асана"])
        try store.addWord("Jira", alternatives: ["жира"])

        let entries = try store.allEntries()
        let words = entries.map(\.word)
        XCTAssertEqual(words, ["Asana", "Jira", "Zoom"])
    }

    // MARK: - 9. LLM replacements с несколькими словами

    func test_llm_replacements_multiple_words() throws {
        let store = try makeStore()

        try store.addWord("Jira", alternatives: ["жира"])
        try store.addWord("Slack", alternatives: ["слак", "слэк"])

        let replacements = try store.llmReplacements()
        XCTAssertEqual(replacements.count, 3)
        XCTAssertEqual(replacements["жира"], "Jira")
        XCTAssertEqual(replacements["слак"], "Slack")
        XCTAssertEqual(replacements["слэк"], "Slack")
    }

    // MARK: - 10. applyReplacements

    func test_applyReplacements_basic() throws {
        let store = try makeStore()
        try store.addWord("Jira", alternatives: ["жира", "джира"])

        let result = try store.applyReplacements(to: "открой жира и посмотри")
        XCTAssertEqual(result, "открой Jira и посмотри")
    }

    func test_applyReplacements_caseInsensitive() throws {
        let store = try makeStore()
        try store.addWord("Jira", alternatives: ["жира"])

        let result = try store.applyReplacements(to: "Жира не работает")
        XCTAssertEqual(result, "Jira не работает")
    }

    func test_applyReplacements_multipleAlternatives() throws {
        let store = try makeStore()
        try store.addWord("Jira", alternatives: ["жира", "джира"])

        let result = try store.applyReplacements(to: "жира и джира")
        XCTAssertEqual(result, "Jira и Jira")
    }

    func test_applyReplacements_wordBoundary() throws {
        let store = try makeStore()
        try store.addWord("Jira", alternatives: ["жира"])

        // "жирафы" не должно замениться
        let result = try store.applyReplacements(to: "жирафы в зоопарке")
        XCTAssertEqual(result, "жирафы в зоопарке")
    }

    func test_applyReplacements_emptyText() throws {
        let store = try makeStore()
        try store.addWord("Jira", alternatives: ["жира"])

        let result = try store.applyReplacements(to: "")
        XCTAssertEqual(result, "")
    }

    func test_applyReplacements_noMatch() throws {
        let store = try makeStore()
        try store.addWord("Jira", alternatives: ["жира"])

        let result = try store.applyReplacements(to: "привет мир")
        XCTAssertEqual(result, "привет мир")
    }

    func test_applyReplacements_multipleWords() throws {
        let store = try makeStore()
        try store.addWord("Jira", alternatives: ["жира"])
        try store.addWord("Slack", alternatives: ["слак"])

        let result = try store.applyReplacements(to: "открой слак и жира")
        XCTAssertEqual(result, "открой Slack и Jira")
    }

    // MARK: - 10b. applyReplacements static (с dictionary)

    func test_applyReplacements_static_basic() {
        let replacements = ["жира": "Jira", "слак": "Slack"]
        let result = DictionaryStore.applyReplacements(
            to: "открой жира и слак",
            replacements: replacements
        )
        XCTAssertEqual(result, "открой Jira и Slack")
    }

    func test_applyReplacements_static_emptyDict() {
        let result = DictionaryStore.applyReplacements(
            to: "привет мир",
            replacements: [:]
        )
        XCTAssertEqual(result, "привет мир")
    }

    // MARK: - 11. Дубликат alternative не добавляется повторно

    func test_duplicate_alternative_not_doubled() throws {
        let store = try makeStore()

        try store.addWord("Jira", alternatives: ["жира", "джира"])
        try store.addWord("Jira", alternatives: ["жира", "гира"])

        let entries = try store.allEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(Set(entries.first?.alternatives ?? []), Set(["жира", "джира", "гира"]))
    }
}
