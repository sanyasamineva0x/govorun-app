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
            textMode: .universal
        )

        XCTAssertEqual(result.finalText, "Созвон в 15:30.")
        XCTAssertEqual(result.path, .llmRejected)
        XCTAssertEqual(result.gateFailureReason, .missingProtectedTokens(["15", "30"]))
    }

    func test_postflight_happy_path_returns_llm_output() {
        let result = NormalizationPipeline.postflight(
            deterministicText: "Созвон в 15:30.",
            llmOutput: "Созвон в 15:30.",
            textMode: .universal
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
            textMode: .universal
        )

        XCTAssertEqual(result.finalText, "Подготовь текст: синхронизация со своим Jira Server.")
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
            textMode: .universal,
            terminalPeriodEnabled: false
        )

        XCTAssertEqual(result.finalText, "Напомни про 25%")
        XCTAssertEqual(result.path, .llm)
        XCTAssertNil(result.gateFailureReason)
    }

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
