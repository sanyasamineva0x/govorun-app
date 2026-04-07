@testable import Govorun
import XCTest

final class NormalizationPipelineTests: XCTestCase {
    func test_preflight_empty_transcript_skips_llm() {
        let result = NormalizationPipeline.preflight(transcript: "   ")

        XCTAssertEqual(result.deterministicText, "")
        XCTAssertFalse(result.shouldInvokeLLM)
    }

    func test_preflight_trivial_transcript_uses_deterministic_only() {
        let result = NormalizationPipeline.preflight(transcript: "привет")

        XCTAssertEqual(result.deterministicText, "Привет.")
        XCTAssertFalse(result.shouldInvokeLLM)
    }

    func test_preflight_nontrivial_transcript_invokes_llm_after_deterministic_baseline() {
        let result = NormalizationPipeline.preflight(
            transcript: "напомни про двадцать пять процентов и тысяча рублей в пять часов"
        )

        XCTAssertEqual(result.deterministicText, "Напомни про 25% и 1 000 рублей в 5:00.")
        XCTAssertTrue(result.shouldInvokeLLM)
    }

    func test_preflight_without_terminal_period_omits_trailing_period() {
        let result = NormalizationPipeline.preflight(
            transcript: "напомни про двадцать пять процентов",
            terminalPeriodEnabled: false
        )

        XCTAssertEqual(result.deterministicText, "Напомни про 25%")
        XCTAssertTrue(result.shouldInvokeLLM)
    }

    func test_postflight_rejected_output_falls_back_to_deterministic_text() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Созвон в 15:30.",
            llmOutput: "Созвон вечером.",
            contract: .normalization
        )

        XCTAssertEqual(result.finalText, "Созвон в 15:30.")
        XCTAssertEqual(result.path, .llmRejected)
        XCTAssertEqual(result.gateFailureReason, .missingProtectedTokens(["15", "30"]))
    }

    func test_postflight_happy_path_returns_llm_output() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Созвон в 15:30.",
            llmOutput: "Созвон в 15:30.",
            contract: .normalization
        )

        XCTAssertEqual(result.finalText, "Созвон в 15:30.")
        XCTAssertEqual(result.path, .llm)
        XCTAssertNil(result.gateFailureReason)
        XCTAssertNil(result.failureContext)
    }

    func test_postflight_applies_surface_canon_before_gate() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Подготовь текст: синхронизация со своим Jira Server.",
            llmOutput: "Подготовь текст: синхронизация со своим jira сервером.",
            contract: .normalization
        )

        XCTAssertEqual(result.finalText, "Подготовь текст: синхронизация со своим Jira Server.")
        XCTAssertEqual(result.path, .llm)
        XCTAssertNil(result.gateFailureReason)
    }

    func test_postflight_applies_surface_canon_for_quotes_and_percents() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "По проекту «Алтай», маржа выросла до 12,5%.",
            llmOutput: "По проекту Алтай, маржа выросла до 12,5 процента.",
            contract: .normalization
        )

        XCTAssertEqual(result.finalText, "По проекту «Алтай», маржа выросла до 12,5%.")
        XCTAssertEqual(result.path, .llm)
        XCTAssertNil(result.gateFailureReason)
    }

    func test_postflight_keeps_numeric_year_in_date_for_gate() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Запиши что релиз переносится на 23 марта 2026.",
            llmOutput: "Запиши, что релиз переносится на 23 марта 2026.",
            contract: .normalization,
            superStyle: .normal,
            terminalPeriodEnabled: false
        )

        XCTAssertEqual(result.finalText, "Запиши, что релиз переносится на 23 марта 2026")
        XCTAssertEqual(result.path, .llm)
        XCTAssertNil(result.gateFailureReason)
    }

    func test_preflight_carries_explicit_time_of_day_through_correction() {
        let result = NormalizationPipeline.preflight(
            transcript: "позвони маме в восемь вечера или нет лучше в девять",
            terminalPeriodEnabled: false
        )

        XCTAssertEqual(result.deterministicText, "Позвони маме в девять вечера")
        XCTAssertTrue(result.shouldInvokeLLM)
    }

    func test_postflight_without_terminal_period_strips_trailing_period() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Напомни про 25%.",
            llmOutput: "Напомни про 25%.",
            contract: .normalization,
            terminalPeriodEnabled: false
        )

        XCTAssertEqual(result.finalText, "Напомни про 25%")
        XCTAssertEqual(result.path, .llm)
        XCTAssertNil(result.gateFailureReason)
    }

    // MARK: - Постфлайт: стиль определяет точку и caps (POST-01, POST-02, TEST-05)

    func test_postflight_relaxed_strips_period_and_lowercases() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Привет мир.",
            llmOutput: "Привет мир.",
            contract: .normalization,
            superStyle: .relaxed,
            terminalPeriodEnabled: true
        )

        XCTAssertEqual(result.finalText, "привет мир")
    }

    func test_postflight_normal_strips_period() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Привет мир.",
            llmOutput: "Привет мир.",
            contract: .normalization,
            superStyle: .normal,
            terminalPeriodEnabled: true
        )

        XCTAssertEqual(result.finalText, "Привет мир")
    }

    func test_postflight_formal_keeps_period() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Привет мир.",
            llmOutput: "Привет мир.",
            contract: .normalization,
            superStyle: .formal,
            terminalPeriodEnabled: false
        )

        XCTAssertEqual(result.finalText, "Привет мир.")
    }

    func test_postflight_rejected_with_style_applies_caps() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Привет мир",
            llmOutput: "Совершенно другой текст.",
            contract: .normalization,
            superStyle: .relaxed
        )

        XCTAssertEqual(result.finalText, "привет мир")
        XCTAssertEqual(result.path, .llmRejected)
    }

    func test_postflight_nil_style_preserves_terminal_period_setting() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Привет мир.",
            llmOutput: "Привет мир.",
            contract: .normalization,
            terminalPeriodEnabled: true
        )

        XCTAssertEqual(result.finalText, "Привет мир.")
    }

    // MARK: - Постфлайт: ListFormatter (LIST-POST-01..03)

    func test_postflight_formats_list_in_llm_output() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "во-первых скорость во-вторых простота",
            llmOutput: "во-первых скорость во-вторых простота",
            contract: .normalization
        )

        XCTAssertEqual(result.finalText, "1. Скорость\n2. Простота")
    }

    func test_postflight_formats_list_with_relaxed_style() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "первое молоко второе хлеб",
            llmOutput: "первое молоко второе хлеб",
            contract: .normalization,
            superStyle: .relaxed
        )

        XCTAssertEqual(result.finalText, "1. молоко\n2. хлеб")
    }

    func test_postflight_list_no_terminal_period() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "первое молоко второе хлеб",
            llmOutput: "первое молоко второе хлеб",
            contract: .normalization,
            superStyle: .formal,
            terminalPeriodEnabled: true
        )

        XCTAssertEqual(
            result.finalText,
            "1. Молоко\n2. Хлеб",
            "terminal period не применяется к list items"
        )
    }

    // MARK: - Failed postflight

    func test_failed_postflight_returns_deterministic_fallback() {
        let result = NormalizationPipeline.failedPostflight(
            deterministicText: "Отправь отчёт.",
            failureContext: "HTTP 500"
        )

        XCTAssertEqual(result.finalText, "Отправь отчёт.")
        XCTAssertEqual(result.path, .llmFailed)
        XCTAssertNil(result.gateFailureReason)
        XCTAssertEqual(result.failureContext, "HTTP 500")
    }
}
