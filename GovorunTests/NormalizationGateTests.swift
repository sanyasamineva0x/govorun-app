@testable import Govorun
import XCTest

final class NormalizationGateTests: XCTestCase {
    func test_accepts_empty_input_without_tokens() {
        let result = NormalizationGate.evaluate(
            input: "",
            output: "Любой текст.",
            contract: .normalization
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.output, "Любой текст.")
        XCTAssertNil(result.failureReason)
    }

    func test_accepts_self_correction_with_large_edit_distance() {
        let result = NormalizationGate.evaluate(
            input: "Привет марк ой точнее саша.",
            output: "Привет, Саша.",
            contract: .normalization
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.output, "Привет, Саша.")
    }

    func test_short_text_accepts_edit_distance_at_quarter_boundary() {
        let result = NormalizationGate.evaluate(
            input: "раз два три четыре",
            output: "Раз два три.",
            contract: .normalization
        )

        XCTAssertTrue(result.accepted)
    }

    func test_short_text_rejects_edit_distance_above_quarter_boundary() {
        let result = NormalizationGate.evaluate(
            input: "раз два три четыре",
            output: "Раз два.",
            contract: .normalization
        )

        XCTAssertFalse(result.accepted)
        guard case .excessiveEdits? = result.failureReason else {
            return XCTFail("Ожидалась excessiveEdits, получили \(String(describing: result.failureReason))")
        }
    }

    func test_long_text_accepts_edit_distance_at_forty_percent_boundary() {
        let result = NormalizationGate.evaluate(
            input: "один два три четыре пять шесть семь восемь девять десять",
            output: "Один два три четыре пять шесть.",
            contract: .normalization
        )

        XCTAssertTrue(result.accepted)
    }

    func test_long_text_rejects_edit_distance_above_forty_percent_boundary() {
        let result = NormalizationGate.evaluate(
            input: "один два три четыре пять шесть семь восемь девять десять",
            output: "Один два три четыре пять.",
            contract: .normalization
        )

        XCTAssertFalse(result.accepted)
        guard case .excessiveEdits? = result.failureReason else {
            return XCTFail("Ожидалась excessiveEdits, получили \(String(describing: result.failureReason))")
        }
    }

    func test_correction_accepts_edit_distance_up_to_eighty_percent() {
        let result = NormalizationGate.evaluate(
            input: "раз два три нет четыре",
            output: "Четыре.",
            contract: .normalization
        )

        XCTAssertTrue(result.accepted)
    }

    func test_correction_rejects_edit_distance_above_eighty_percent() {
        let result = NormalizationGate.evaluate(
            input: "раз два три четыре пять шесть семь восемь нет девять",
            output: "Что-то совсем другое здесь.",
            contract: .normalization
        )

        XCTAssertFalse(result.accepted)
        guard case .excessiveEdits? = result.failureReason else {
            return XCTFail("Ожидалась excessiveEdits, получили \(String(describing: result.failureReason))")
        }
    }

    func test_rejects_missing_protected_latin_and_numeric_tokens() {
        let result = NormalizationGate.evaluate(
            input: "Открой Jira в 15:30.",
            output: "Открой задачу.",
            contract: .normalization
        )

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.output, "Открой Jira в 15:30.")

        guard case .missingProtectedTokens(let tokens)? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }

        XCTAssertTrue(tokens.contains("jira"))
        XCTAssertTrue(tokens.contains("15"))
        XCTAssertTrue(tokens.contains("30"))
    }

    func test_rejects_missing_url_token() {
        let result = NormalizationGate.evaluate(
            input: "Открой https://govorun.app/docs.",
            output: "Открой сайт.",
            contract: .normalization
        )

        XCTAssertFalse(result.accepted)
        guard case .missingProtectedTokens(let tokens)? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }
        XCTAssertTrue(tokens.contains("https://govorun.app/docs."))
    }

    func test_rejects_missing_email_token() {
        let result = NormalizationGate.evaluate(
            input: "Напиши на test@example.com.",
            output: "Напиши автору.",
            contract: .normalization
        )

        XCTAssertFalse(result.accepted)
        guard case .missingProtectedTokens(let tokens)? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }
        XCTAssertTrue(tokens.contains("test@example.com"))
    }

    func test_rejects_missing_currency_token() {
        let result = NormalizationGate.evaluate(
            input: "Потратить 500 ₽.",
            output: "Потратить деньги.",
            contract: .normalization
        )

        XCTAssertFalse(result.accepted)
        guard case .missingProtectedTokens(let tokens)? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }
        XCTAssertTrue(tokens.contains("500"))
        XCTAssertTrue(tokens.contains("₽"))
    }

    func test_correction_source_ignores_tokens_before_marker() {
        let result = NormalizationGate.evaluate(
            input: "Открой Jira а нет Notion.",
            output: "Открой Notion.",
            contract: .normalization
        )

        XCTAssertTrue(result.accepted)
        XCTAssertNil(result.failureReason)
    }

    func test_correction_source_keeps_tokens_after_marker_protected() {
        let result = NormalizationGate.evaluate(
            input: "Открой Jira а нет Notion.",
            output: "Открой приложение.",
            contract: .normalization
        )

        XCTAssertFalse(result.accepted)
        guard case .missingProtectedTokens(let tokens)? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }
        XCTAssertTrue(tokens.contains("notion"))
        XCTAssertFalse(tokens.contains("jira"))
    }

    func test_correction_source_handles_standalone_net_at_sentence_start() {
        let result = NormalizationGate.evaluate(
            input: "Нет, открой Notion.",
            output: "Открой Notion.",
            contract: .normalization
        )

        XCTAssertTrue(result.accepted)
        XCTAssertNil(result.failureReason)
    }

    func test_accepts_output_with_ignored_placeholder_literal() {
        let result = NormalizationGate.evaluate(
            input: "Привет вот мой адрес.",
            output: "Привет, мой адрес — [[[GOVORUN_SNIPPET]]].",
            contract: .normalization,
            ignoredOutputLiterals: [SnippetPlaceholder.token]
        )

        XCTAssertTrue(result.accepted)
        XCTAssertNil(result.failureReason)
    }

    func test_ignored_placeholder_does_not_hide_missing_protected_tokens() {
        let result = NormalizationGate.evaluate(
            input: "Открой Jira в 15:30.",
            output: "Открой [[[GOVORUN_SNIPPET]]].",
            contract: .normalization,
            ignoredOutputLiterals: [SnippetPlaceholder.token]
        )

        XCTAssertFalse(result.accepted)
        guard case .missingProtectedTokens(let tokens)? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }
        XCTAssertTrue(tokens.contains("jira"))
        XCTAssertTrue(tokens.contains("15"))
        XCTAssertTrue(tokens.contains("30"))
    }

    func test_rejects_short_hallucinatory_rewrite_without_correction_markers() {
        let result = NormalizationGate.evaluate(
            input: "Привет мир.",
            output: "Добрый день, коллеги.",
            contract: .normalization
        )

        XCTAssertFalse(result.accepted)

        guard case .excessiveEdits? = result.failureReason else {
            return XCTFail("Ожидалась excessiveEdits, получили \(String(describing: result.failureReason))")
        }
    }

    /// Пока .rewriting не используется в production-коде.
    /// Эти тесты фиксируют контракт заранее, чтобы следующая итерация
    /// не вводила его вслепую.
    func test_rewriting_contract_allows_style_shift_within_length_bounds() {
        let result = NormalizationGate.evaluate(
            input: "Перенеси встречу с Ивановым на четверг.",
            output: "Предлагаю перенести встречу с Ивановым на четверг.",
            contract: .rewriting
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.output, "Предлагаю перенести встречу с Ивановым на четверг.")
    }

    func test_rewriting_contract_rejects_too_short_output() {
        let result = NormalizationGate.evaluate(
            input: "Подготовь письмо с объяснением причин переноса и новыми сроками.",
            output: "Подготовь письмо.",
            contract: .rewriting
        )

        XCTAssertFalse(result.accepted)
        guard case .invalidLengthRatio? = result.failureReason else {
            return XCTFail("Ожидалась invalidLengthRatio, получили \(String(describing: result.failureReason))")
        }
    }

    func test_rewriting_contract_rejects_too_long_output() {
        let result = NormalizationGate.evaluate(
            input: "Подготовь письмо с новыми сроками.",
            output: "Подготовь письмо с новыми сроками, обязательным вступлением, длинным пояснением причин, резюме, послесловием и отдельным приложением для команды.",
            contract: .rewriting
        )

        XCTAssertFalse(result.accepted)
        guard case .invalidLengthRatio? = result.failureReason else {
            return XCTFail("Ожидалась invalidLengthRatio, получили \(String(describing: result.failureReason))")
        }
    }
}
