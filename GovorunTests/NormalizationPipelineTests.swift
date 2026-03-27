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

    func test_failed_postflight_returns_deterministic_fallback() {
        let result = NormalizationPipeline.failedPostflight(
            deterministicText: "Отправь отчёт."
        )

        XCTAssertEqual(result.finalText, "Отправь отчёт.")
        XCTAssertEqual(result.path, .llmFailed)
        XCTAssertNil(result.gateFailureReason)
    }
}
