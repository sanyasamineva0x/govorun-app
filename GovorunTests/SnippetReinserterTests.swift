import XCTest
@testable import Govorun

final class SnippetReinserterTests: XCTestCase {

    // MARK: - reinsert: happy path

    func test_reinsert_single_placeholder() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "Привет, мой адрес — [[[GOVORUN_SNIPPET]]].",
            content: "Аминева 9"
        )
        XCTAssertEqual(result, "Привет, мой адрес — Аминева 9.")
    }

    func test_reinsert_placeholder_at_start_of_string() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "[[[GOVORUN_SNIPPET]]].",
            content: "Аминева 9"
        )
        XCTAssertEqual(result, "Аминева 9.")
    }

    func test_reinsert_placeholder_at_end_of_string() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "Мой адрес: [[[GOVORUN_SNIPPET]]]",
            content: "Аминева 9"
        )
        XCTAssertEqual(result, "Мой адрес: Аминева 9")
    }

    func test_reinsert_placeholder_next_to_punctuation_is_valid() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "Адрес: [[[GOVORUN_SNIPPET]]].",
            content: "Аминева 9"
        )
        XCTAssertEqual(result, "Адрес: Аминева 9.")
    }

    // MARK: - reinsert: failure cases

    func test_reinsert_no_placeholder_returns_nil() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "Привет, мой адрес.",
            content: "Аминева 9"
        )
        XCTAssertNil(result)
    }

    func test_reinsert_multiple_placeholders_returns_nil() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "Адрес: [[[GOVORUN_SNIPPET]]], повторяю: [[[GOVORUN_SNIPPET]]].",
            content: "Аминева 9"
        )
        XCTAssertNil(result)
    }

    func test_reinsert_placeholder_glued_to_word_returns_nil() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "Мой[[[GOVORUN_SNIPPET]]].",
            content: "Аминева 9"
        )
        XCTAssertNil(result)
    }

    // MARK: - Data integrity (byte-for-byte)

    func test_reinsert_preserves_email() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "Мой имейл: [[[GOVORUN_SNIPPET]]].",
            content: "sanya.amineva+test@gmail.com"
        )
        XCTAssertEqual(result, "Мой имейл: sanya.amineva+test@gmail.com.")
    }

    func test_reinsert_preserves_phone() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "Мой телефон: [[[GOVORUN_SNIPPET]]].",
            content: "+7 (999) 123-45-67"
        )
        XCTAssertEqual(result, "Мой телефон: +7 (999) 123-45-67.")
    }

    func test_reinsert_preserves_url() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "Ссылка: [[[GOVORUN_SNIPPET]]].",
            content: "https://docs.google.com/document/d/1aBcDeFgHiJkLmNoPqRsTuVwXyZ/edit?usp=sharing"
        )
        XCTAssertEqual(result, "Ссылка: https://docs.google.com/document/d/1aBcDeFgHiJkLmNoPqRsTuVwXyZ/edit?usp=sharing.")
    }

    func test_reinsert_preserves_inn() {
        let result = SnippetReinserter.reinsert(
            llmOutput: "Реквизиты: [[[GOVORUN_SNIPPET]]].",
            content: "ИП Иванов, ИНН 1234567890, р/с 40802810500000012345"
        )
        XCTAssertEqual(result, "Реквизиты: ИП Иванов, ИНН 1234567890, р/с 40802810500000012345.")
    }

    func test_reinsert_preserves_multiline_content() {
        let content = "ИП Иванов\nИНН 1234567890\nр/с 40802810..."
        let result = SnippetReinserter.reinsert(
            llmOutput: "Мои реквизиты:\n[[[GOVORUN_SNIPPET]]]",
            content: content
        )
        XCTAssertEqual(result, "Мои реквизиты:\nИП Иванов\nИНН 1234567890\nр/с 40802810...")
    }

    // MARK: - mechanicalFallback

    func test_mechanical_fallback_preserves_context() {
        let result = SnippetReinserter.mechanicalFallback(
            rawTranscript: "лена вот мой адрес",
            trigger: "мой адрес", content: "Аминева 9"
        )
        XCTAssertEqual(result, "Лена вот мой адрес: Аминева 9")
    }

    func test_mechanical_fallback_trigger_at_start() {
        let result = SnippetReinserter.mechanicalFallback(
            rawTranscript: "мой адрес пожалуйста",
            trigger: "мой адрес", content: "Аминева 9"
        )
        XCTAssertEqual(result, "Мой адрес: Аминева 9 пожалуйста")
    }

    func test_mechanical_fallback_trigger_only() {
        let result = SnippetReinserter.mechanicalFallback(
            rawTranscript: "мой адрес",
            trigger: "мой адрес", content: "Аминева 9"
        )
        XCTAssertEqual(result, "Мой адрес: Аминева 9")
    }

    func test_mechanicalFallback_empty_rawTranscript() {
        let result = SnippetReinserter.mechanicalFallback(
            rawTranscript: "",
            trigger: "мой адрес", content: "Аминева 9"
        )
        XCTAssertEqual(result, "Мой адрес: Аминева 9")
    }
}
