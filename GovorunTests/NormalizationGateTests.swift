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

    // MARK: - GATE-05: formal ты→вы через .rewriting

    func test_rewriting_accepts_ty_to_vy_transformation() {
        let result = NormalizationGate.evaluate(
            input: "Ты можешь скинуть отчёт до пятницы.",
            output: "Вы можете скинуть отчёт до пятницы.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.output, "Вы можете скинуть отчёт до пятницы.")
    }

    func test_rewriting_accepts_imperative_te_form() {
        let result = NormalizationGate.evaluate(
            input: "Скажи Пете, что встреча перенеслась.",
            output: "Скажите Пете, что встреча перенеслась.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted)
    }

    func test_rewriting_accepts_possessive_replacement() {
        let result = NormalizationGate.evaluate(
            input: "Перешли ей твой отчёт за март.",
            output: "Перешлите ей ваш отчёт за март.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted)
    }

    func test_rewriting_preserves_protected_tokens() {
        let result = NormalizationGate.evaluate(
            input: "Ты получил моё письмо от 25 марта в Slack.",
            output: "Вы получили моё письмо от 25 марта в Slack.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted)
    }

    func test_rewriting_rejects_missing_protected_token() {
        let result = NormalizationGate.evaluate(
            input: "Ты получил моё письмо от 25 марта в Slack.",
            output: "Вы получили моё письмо от марта.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertFalse(result.accepted)
        guard case .missingProtectedTokens? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }
    }

    func test_rewriting_rejects_empty_output_formal() {
        let result = NormalizationGate.evaluate(
            input: "Скажи пете что встреча перенеслась.",
            output: "",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.failureReason, .empty)
    }

    func test_rewriting_accepts_already_formal_text_unchanged() {
        let result = NormalizationGate.evaluate(
            input: "Вы можете отправить документ.",
            output: "Вы можете отправить документ.",
            contract: .rewriting,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.output, "Вы можете отправить документ.")
    }

    // MARK: - GATE-01: nil style backward compatibility

    func test_nil_style_preserves_existing_behavior() {
        let result = NormalizationGate.evaluate(
            input: "Открой Slack.",
            output: "Открой приложение.",
            contract: .normalization,
            superStyle: nil
        )

        XCTAssertFalse(result.accepted)
        guard case .missingProtectedTokens? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }
    }

    // MARK: - GATE-02: relaxed brand/tech aliases

    func test_relaxed_accepts_brand_alias_as_protected_token() {
        let result = NormalizationGate.evaluate(
            input: "Скинь в Slack.",
            output: "скинь в слак",
            contract: .normalization,
            superStyle: .relaxed
        )

        XCTAssertTrue(result.accepted, "relaxed должен принять слак как алиас Slack. Причина: \(String(describing: result.failureReason))")
    }

    func test_relaxed_accepts_tech_alias_as_protected_token() {
        let result = NormalizationGate.evaluate(
            input: "Открой PDF.",
            output: "открой пдф",
            contract: .normalization,
            superStyle: .relaxed
        )

        XCTAssertTrue(result.accepted, "relaxed должен принять пдф как алиас PDF. Причина: \(String(describing: result.failureReason))")
    }

    func test_relaxed_rejects_missing_token_without_alias() {
        let result = NormalizationGate.evaluate(
            input: "Открой Slack и Notion.",
            output: "открой слак",
            contract: .normalization,
            superStyle: .relaxed
        )

        XCTAssertFalse(result.accepted)
        guard case .missingProtectedTokens(let tokens)? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }
        XCTAssertTrue(tokens.contains("notion"), "Notion должен быть в missing tokens")
    }

    func test_normal_does_not_accept_brand_alias() {
        let result = NormalizationGate.evaluate(
            input: "Скинь в Slack.",
            output: "Скинь в слак.",
            contract: .normalization,
            superStyle: .normal
        )

        XCTAssertFalse(result.accepted)
        guard case .missingProtectedTokens? = result.failureReason else {
            return XCTFail("Ожидалась missingProtectedTokens, получили \(String(describing: result.failureReason))")
        }
    }

    // MARK: - GATE-04: formal slang expansions

    func test_formal_accepts_slang_expansion_as_protected_token() {
        let result = NormalizationGate.evaluate(
            input: "Спс за помощь.",
            output: "Спасибо за помощь.",
            contract: .normalization,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted, "formal должен принять спасибо как раскрытие спс. Причина: \(String(describing: result.failureReason))")
    }

    func test_formal_rejects_unknown_slang() {
        let result = NormalizationGate.evaluate(
            input: "Хз что делать.",
            output: "Не знаю что делать.",
            contract: .normalization,
            superStyle: .formal
        )

        XCTAssertFalse(result.accepted, "хз не в таблице slangExpansions, gate должен отклонить")
    }

    func test_relaxed_does_not_accept_slang_alias() {
        // relaxed не использует slangExpansions -- спс и спасибо считаются разными словами
        // 2 из 3 токенов отличаются = 67% edits >> relaxed threshold 0.35
        let result = NormalizationGate.evaluate(
            input: "Спс чел.",
            output: "спасибо человек",
            contract: .normalization,
            superStyle: .relaxed
        )

        XCTAssertFalse(result.accepted, "relaxed не использует slang алиасы, спс → спасибо и чел → человек = excessive edits")
    }

    // MARK: - GATE-03: style-neutral edit distance

    func test_relaxed_style_neutral_distance_brand_alias() {
        let result = NormalizationGate.evaluate(
            input: "Скинь в Slack файл.",
            output: "скинь в слак файл",
            contract: .normalization,
            superStyle: .relaxed
        )

        XCTAssertTrue(result.accepted, "Slack→слак не должен давать edit distance. Причина: \(String(describing: result.failureReason))")
    }

    func test_formal_style_neutral_distance_slang() {
        let result = NormalizationGate.evaluate(
            input: "Спс большое чел.",
            output: "Спасибо большое, человек.",
            contract: .normalization,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted, "спс→спасибо и чел→человек должны нормализоваться до distance 0. Причина: \(String(describing: result.failureReason))")
    }

    // MARK: - GATE-03: threshold relaxation

    func test_relaxed_threshold_is_relaxed_for_short_text() {
        // 4 токена, output убирает 1 + меняет регистр = ~25-30% edits
        // nil threshold = 0.25 (reject), relaxed threshold = 0.35 (accept)
        let result = NormalizationGate.evaluate(
            input: "раз два три четыре",
            output: "Раз два три.",
            contract: .normalization,
            superStyle: .relaxed
        )

        XCTAssertTrue(result.accepted, "relaxed threshold 0.35 должен принять ~25% edits. Причина: \(String(describing: result.failureReason))")
    }

    func test_formal_threshold_is_relaxed_for_long_text() {
        // 10 токенов, output убирает 4 = 40% edits
        // nil threshold = 0.40 (borderline), formal threshold = 0.50 (accept)
        let result = NormalizationGate.evaluate(
            input: "один два три четыре пять шесть семь восемь девять десять",
            output: "Один два три четыре пять шесть.",
            contract: .normalization,
            superStyle: .formal
        )

        XCTAssertTrue(result.accepted, "formal threshold 0.50 должен принять ~40% edits. Причина: \(String(describing: result.failureReason))")
    }
}
