@testable import Govorun
import SwiftData
import XCTest

// MARK: - Тесты SnippetEngine

final class SnippetEngineTests: XCTestCase {
    private func makeEngine(_ records: [SnippetRecord]) -> SnippetEngine {
        let engine = SnippetEngine()
        engine.updateSnippets(records)
        return engine
    }

    private func record(
        trigger: String,
        content: String,
        matchMode: MatchMode = .exact,
        isEnabled: Bool = true
    ) -> SnippetRecord {
        SnippetRecord(trigger: trigger, content: content, matchMode: matchMode, isEnabled: isEnabled)
    }

    // MARK: - 1. Exact match

    func test_exact_match() {
        let engine = makeEngine([
            record(trigger: "мой имейл", content: "sanya@example.com"),
        ])

        let match = engine.match("мой имейл")
        XCTAssertEqual(match?.content, "sanya@example.com")
        XCTAssertEqual(match?.trigger, "мой имейл")
    }

    // MARK: - 2. Exact match case-insensitive

    func test_exact_match_case_insensitive() {
        let engine = makeEngine([
            record(trigger: "Мой Имейл", content: "sanya@example.com"),
        ])

        XCTAssertEqual(engine.match("мой имейл")?.content, "sanya@example.com")
    }

    // MARK: - 3. Fuzzy match (Levenshtein)

    func test_fuzzy_match() {
        let engine = makeEngine([
            record(trigger: "мой имейл", content: "sanya@example.com", matchMode: .fuzzy),
        ])

        // "мой мейл" — distance 1 от "мой имейл" (9 символов, порог ≤2)
        XCTAssertEqual(engine.match("мой мейл")?.content, "sanya@example.com")
    }

    // MARK: - 4. No match — обычный текст

    func test_no_match() {
        let engine = makeEngine([
            record(trigger: "мой имейл", content: "sanya@example.com"),
        ])

        XCTAssertNil(engine.match("привет как дела"))
    }

    // MARK: - 5. Disabled snippet ignored

    func test_disabled_snippet_ignored() {
        let engine = makeEngine([
            record(trigger: "мой имейл", content: "sanya@example.com", isEnabled: false),
        ])

        XCTAssertNil(engine.match("мой имейл"))
    }

    // MARK: - 6. Levenshtein threshold — за пределами порога

    func test_levenshtein_threshold_exceeded() {
        let engine = makeEngine([
            record(trigger: "мой имейл", content: "sanya@example.com", matchMode: .fuzzy),
        ])

        // "мой адрес" — distance значительно больше порога
        XCTAssertNil(engine.match("мой адрес"))
    }

    // MARK: - 7. Несколько сниппетов — первый match побеждает

    func test_first_match_wins() {
        let engine = makeEngine([
            record(trigger: "мой имейл", content: "sanya@example.com"),
            record(trigger: "мой телефон", content: "+7 999 123-45-67"),
        ])

        XCTAssertEqual(engine.match("мой телефон")?.content, "+7 999 123-45-67")
        XCTAssertEqual(engine.match("мой имейл")?.content, "sanya@example.com")
    }

    // MARK: - 8. Fuzzy match с точным порогом

    func test_fuzzy_exact_threshold() {
        // Триггер "привет" — 6 символов, порог = ceil(6 * 0.3) = 2
        let engine = makeEngine([
            record(trigger: "привет", content: "Здравствуйте!", matchMode: .fuzzy),
        ])

        // distance 1 — в пределах порога → матчится
        XCTAssertEqual(engine.match("приет")?.content, "Здравствуйте!") // distance 1 ≤ 2
        // distance 2 — ровно на пороге → матчится
        XCTAssertEqual(engine.match("прет")?.content, "Здравствуйте!") // distance 2 ≤ 2
        // distance 3 — за порогом → не матчится
        XCTAssertNil(engine.match("рет")) // distance 3 > 2
    }

    // MARK: - 9. Пустой текст → нет матча

    func test_empty_text_no_match() {
        let engine = makeEngine([
            record(trigger: "мой имейл", content: "sanya@example.com", matchMode: .fuzzy),
        ])

        XCTAssertNil(engine.match(""))
        XCTAssertNil(engine.match("   "))
    }

    // MARK: - 10. Trim пробелов при сравнении

    func test_trimmed_match() {
        let engine = makeEngine([
            record(trigger: "мой имейл", content: "sanya@example.com"),
        ])

        XCTAssertEqual(engine.match("  мой имейл  ")?.content, "sanya@example.com")
    }

    // MARK: - 11. updateSnippets заменяет данные

    func test_update_snippets_replaces() {
        let engine = SnippetEngine()

        engine.updateSnippets([
            record(trigger: "мой имейл", content: "old@test.com"),
        ])
        XCTAssertEqual(engine.match("мой имейл")?.content, "old@test.com")

        engine.updateSnippets([
            record(trigger: "мой телефон", content: "+7 000"),
        ])
        XCTAssertNil(engine.match("мой имейл"))
        XCTAssertEqual(engine.match("мой телефон")?.content, "+7 000")
    }

    // MARK: - 12. match возвращает trigger и content

    func test_match_returns_trigger_and_content() {
        let engine = makeEngine([
            record(trigger: "мой имейл", content: "test@example.com", matchMode: .exact),
        ])

        let match = engine.match("мой имейл")
        XCTAssertEqual(match?.trigger, "мой имейл")
        XCTAssertEqual(match?.content, "test@example.com")
    }

    // MARK: - Tokenize

    func test_tokenize_strips_punctuation() {
        let tokens = SnippetEngine.tokenize("привет, вот мой адрес")
        XCTAssertEqual(tokens, ["привет", "вот", "мой", "адрес"])
    }

    func test_tokenize_strips_trailing_question_mark() {
        let tokens = SnippetEngine.tokenize("мой адрес?")
        XCTAssertEqual(tokens, ["мой", "адрес"])
    }

    func test_tokenize_collapses_whitespace() {
        let tokens = SnippetEngine.tokenize("  привет   мой   адрес  ")
        XCTAssertEqual(tokens, ["привет", "мой", "адрес"])
    }

    func test_tokenize_handles_dash() {
        let tokens = SnippetEngine.tokenize("вот — мой адрес")
        XCTAssertEqual(tokens, ["вот", "мой", "адрес"])
    }

    func test_tokenize_empty_string() {
        let tokens = SnippetEngine.tokenize("")
        XCTAssertEqual(tokens, [])
    }

    // MARK: - Standalone kind

    func test_standalone_exact_returns_standalone_kind() {
        let engine = makeEngine([record(trigger: "мой адрес", content: "аминева 9", matchMode: .exact)])
        let result = engine.match("мой адрес")
        guard case .standalone = result?.kind else { XCTFail("Ожидался standalone"); return }
        XCTAssertEqual(result?.content, "аминева 9")
    }

    // MARK: - Standalone with punctuation

    func test_standalone_exact_with_trailing_question_mark() {
        let engine = makeEngine([
            record(trigger: "мой адрес", content: "Аминева 9", matchMode: .exact),
        ])
        let result = engine.match("мой адрес?")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kind, .standalone)
        XCTAssertEqual(result?.content, "Аминева 9")
    }

    func test_standalone_exact_with_trailing_comma() {
        let engine = makeEngine([
            record(trigger: "мой адрес", content: "Аминева 9", matchMode: .exact),
        ])
        let result = engine.match("мой адрес,")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kind, .standalone)
    }

    func test_standalone_fuzzy_with_punctuation() {
        let engine = makeEngine([
            record(trigger: "мой адрес", content: "Аминева 9", matchMode: .fuzzy),
        ])
        let result = engine.match("мой адрес!")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.kind, .standalone)
    }

    // MARK: - Embedded

    func test_embedded_exact_match_detects_trigger_inside() {
        let engine = makeEngine([record(trigger: "мой адрес", content: "аминева 9", matchMode: .exact)])
        let result = engine.match("привет вот мой адрес")
        guard case .embedded = result?.kind else { XCTFail("Ожидался embedded"); return }
        XCTAssertEqual(result?.trigger, "мой адрес")
        XCTAssertEqual(result?.content, "аминева 9")
    }

    func test_embedded_exact_with_comma_before_trigger() {
        let engine = makeEngine([record(trigger: "мой адрес", content: "аминева 9", matchMode: .exact)])
        let result = engine.match("привет, вот мой адрес")
        guard case .embedded = result?.kind else { XCTFail("Запятая не должна мешать embedded match"); return }
    }

    func test_embedded_exact_with_question_mark_after_trigger() {
        let engine = makeEngine([record(trigger: "мой адрес", content: "аминева 9", matchMode: .exact)])
        let result = engine.match("какой мой адрес?")
        guard case .embedded = result?.kind else { XCTFail("Вопрос. знак не должен мешать"); return }
    }

    func test_embedded_exact_with_dash_near_trigger() {
        let engine = makeEngine([record(trigger: "мой имейл", content: "a@b.com", matchMode: .exact)])
        let result = engine.match("скинь на мой имейл, пожалуйста")
        guard case .embedded = result?.kind else { XCTFail("Запятая после trigger не должна мешать"); return }
    }

    func test_embedded_fuzzy_does_not_match_embedded_context() {
        // "мой адре" — Levenshtein 1 от "мой адрес", порог ceil(9*0.3)=3 → standalone fuzzy бы сматчил
        // Но в embedded контексте fuzzy не должен работать (exact only)
        // standalone: "Лена вот мой адре скажи" tokenized+joined = "лена вот мой адре скажи",
        //   Levenshtein("лена вот мой адре скажи", "мой адрес") >> 3 → miss
        // embedded: tokenize exact → ["мой", "адре"] != ["мой", "адрес"] → miss
        // Это правильное поведение: fuzzy embedded не поддерживается
        let engine = makeEngine([record(trigger: "мой адрес", content: "аминева 9", matchMode: .fuzzy)])
        let result = engine.match("Лена вот мой адре скажи")
        XCTAssertNil(result)
    }

    func test_embedded_no_match_when_trigger_absent() {
        let engine = makeEngine([record(trigger: "мой адрес", content: "аминева 9", matchMode: .exact)])
        let result = engine.match("привет как дела")
        XCTAssertNil(result)
    }

    func test_embedded_longest_trigger_wins() {
        let engine = makeEngine([
            record(trigger: "мой", content: "X", matchMode: .exact),
            record(trigger: "мой адрес", content: "аминева 9", matchMode: .exact),
        ])
        let result = engine.match("вот мой адрес")
        guard case .embedded = result?.kind else { XCTFail("Ожидался embedded"); return }
        XCTAssertEqual(result?.content, "аминева 9")
    }

    func test_embedded_not_triggered_on_exact_match() {
        let engine = makeEngine([record(trigger: "мой адрес", content: "аминева 9", matchMode: .exact)])
        let result = engine.match("мой адрес")
        guard case .standalone = result?.kind else { XCTFail("Standalone должен быть приоритетнее"); return }
    }

    func test_embedded_exact_allows_short_triggers() {
        let engine = makeEngine([record(trigger: "код", content: "abc123", matchMode: .exact)])
        let result = engine.match("привет вот код")
        guard case .embedded = result?.kind else { XCTFail("Exact embedded должен работать для коротких"); return }
    }
}

// MARK: - Levenshtein Distance тесты

final class LevenshteinDistanceTests: XCTestCase {
    func test_identical_strings() {
        XCTAssertEqual(SnippetEngine.levenshteinDistance("привет", "привет"), 0)
    }

    func test_one_insertion() {
        XCTAssertEqual(SnippetEngine.levenshteinDistance("мой мейл", "мой имейл"), 1)
    }

    func test_one_deletion() {
        XCTAssertEqual(SnippetEngine.levenshteinDistance("мой имейл", "мой мейл"), 1)
    }

    func test_one_substitution() {
        XCTAssertEqual(SnippetEngine.levenshteinDistance("кот", "кит"), 1)
    }

    func test_empty_strings() {
        XCTAssertEqual(SnippetEngine.levenshteinDistance("", ""), 0)
        XCTAssertEqual(SnippetEngine.levenshteinDistance("abc", ""), 3)
        XCTAssertEqual(SnippetEngine.levenshteinDistance("", "abc"), 3)
    }

    func test_completely_different() {
        XCTAssertEqual(SnippetEngine.levenshteinDistance("кот", "дом"), 2)
    }
}

// MARK: - Тесты SnippetStore

final class SnippetStoreTests: XCTestCase {
    private func makeStore() throws -> SnippetStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Snippet.self,
            configurations: config
        )
        let context = ModelContext(container)
        return SnippetStore(modelContext: context)
    }

    // MARK: - 1. Добавление сниппета

    func test_add_snippet() throws {
        let store = try makeStore()

        try store.addSnippet(trigger: "мой имейл", content: "sanya@example.com")

        let all = try store.allSnippets()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.trigger, "мой имейл")
        XCTAssertEqual(all.first?.content, "sanya@example.com")
        XCTAssertEqual(all.first?.matchMode, .fuzzy)
        XCTAssertTrue(all.first?.isEnabled ?? false)
    }

    // MARK: - 2. Удаление сниппета

    func test_remove_snippet() throws {
        let store = try makeStore()

        try store.addSnippet(trigger: "мой имейл", content: "sanya@example.com")
        try store.removeSnippet(trigger: "мой имейл")

        let all = try store.allSnippets()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - 3. Получение SnippetRecords для engine

    func test_snippet_records() throws {
        let store = try makeStore()

        try store.addSnippet(trigger: "мой имейл", content: "sanya@example.com")
        try store.addSnippet(trigger: "мой телефон", content: "+7 999 123-45-67", matchMode: .exact)

        let records = try store.snippetRecords()
        XCTAssertEqual(records.count, 2)
    }

    // MARK: - 4. Удаление несуществующего → ошибка

    func test_remove_nonexistent_throws() throws {
        let store = try makeStore()

        XCTAssertThrowsError(try store.removeSnippet(trigger: "нет такого")) { error in
            guard case SnippetStoreError.snippetNotFound = error else {
                XCTFail("Ожидалась SnippetStoreError.snippetNotFound")
                return
            }
        }
    }

    // MARK: - 5. Дубликат триггера → обновление content

    func test_duplicate_trigger_updates_content() throws {
        let store = try makeStore()

        try store.addSnippet(trigger: "мой имейл", content: "old@test.com")
        try store.addSnippet(trigger: "мой имейл", content: "new@test.com")

        let all = try store.allSnippets()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "new@test.com")
    }

    // MARK: - 6. Пустой триггер не добавляется

    func test_empty_trigger_ignored() throws {
        let store = try makeStore()

        try store.addSnippet(trigger: "", content: "something")
        try store.addSnippet(trigger: "   ", content: "something")

        let all = try store.allSnippets()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - 7. Сортировка по триггеру

    func test_all_snippets_sorted() throws {
        let store = try makeStore()

        try store.addSnippet(trigger: "шаблон", content: "...")
        try store.addSnippet(trigger: "адрес", content: "...")
        try store.addSnippet(trigger: "мой имейл", content: "...")

        let all = try store.allSnippets()
        let triggers = all.map(\.trigger)
        XCTAssertEqual(triggers, ["адрес", "мой имейл", "шаблон"])
    }

    // MARK: - 8. incrementUsage увеличивает счётчик

    func test_increment_usage() throws {
        let store = try makeStore()

        try store.addSnippet(trigger: "мой имейл", content: "sanya@example.com")
        try store.incrementUsage(trigger: "мой имейл")
        try store.incrementUsage(trigger: "мой имейл")

        let all = try store.allSnippets()
        XCTAssertEqual(all.first?.usageCount, 2)
    }

    // MARK: - 9. incrementUsage на несуществующий → ошибка

    func test_increment_usage_nonexistent_throws() throws {
        let store = try makeStore()

        XCTAssertThrowsError(try store.incrementUsage(trigger: "нет такого")) { error in
            guard case SnippetStoreError.snippetNotFound = error else {
                XCTFail("Ожидалась snippetNotFound")
                return
            }
        }
    }

    // MARK: - 10. seedDefaultsIfNeeded создаёт сниппеты когда пусто

    func test_seedDefaultsIfNeeded_creates_snippets_when_empty() throws {
        let store = try makeStore()
        try store.seedDefaultsIfNeeded()
        let all = try store.allSnippets()
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - 11. seedDefaultsIfNeeded не создаёт когда не пусто

    func test_seedDefaultsIfNeeded_does_nothing_when_not_empty() throws {
        let store = try makeStore()
        try store.addSnippet(trigger: "test", content: "test", matchMode: .exact)
        try store.seedDefaultsIfNeeded()
        let all = try store.allSnippets()
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - 12. setEnabled на несуществующий сниппет → ошибка

    func test_set_enabled_nonexistent_throws() throws {
        let store = try makeStore()

        XCTAssertThrowsError(try store.setEnabled(false, for: "несуществующий")) { error in
            guard case SnippetStoreError.snippetNotFound(let trigger) = error else {
                XCTFail("Ожидалась snippetNotFound")
                return
            }
            XCTAssertEqual(trigger, "несуществующий")
        }
    }

    // MARK: - 13. Toggle enabled

    func test_toggle_enabled() throws {
        let store = try makeStore()

        try store.addSnippet(trigger: "мой имейл", content: "sanya@example.com")
        try store.setEnabled(false, for: "мой имейл")

        let all = try store.allSnippets()
        XCTAssertFalse(all.first?.isEnabled ?? true)

        // records должны включать disabled
        let records = try store.snippetRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertFalse(records.first?.isEnabled ?? true)
    }
}

// MARK: - TextMode Snippet Prompt тесты

final class TextModeSnippetPromptTests: XCTestCase {
    func test_systemPrompt_includes_snippet_placeholder_block() {
        let ctx = SnippetContext(trigger: "мой адрес")
        let prompt = TextMode.universal.systemPrompt(
            currentDate: Date(),
            snippetContext: ctx
        )
        XCTAssertTrue(prompt.contains("ПОДСТАНОВКА"))
        XCTAssertTrue(prompt.contains("мой адрес"))
        XCTAssertTrue(prompt.contains("[[[GOVORUN_SNIPPET]]]"))
    }

    func test_systemPrompt_without_snippet_has_no_substitution_block() {
        let prompt = TextMode.universal.systemPrompt(currentDate: Date())
        XCTAssertFalse(prompt.contains("ПОДСТАНОВКА"))
        XCTAssertFalse(prompt.contains("[[[GOVORUN_SNIPPET]]]"))
    }
}
