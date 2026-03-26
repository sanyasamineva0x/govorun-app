@testable import Govorun
import XCTest

final class NormalizationGateTests: XCTestCase {
    func test_accepts_self_correction_with_large_edit_distance() {
        let result = NormalizationGate.evaluate(
            input: "Привет марк ой точнее саша.",
            output: "Привет, Саша.",
            contract: .normalization
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.output, "Привет, Саша.")
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

    func test_rewriting_contract_allows_style_shift_within_length_bounds() {
        let result = NormalizationGate.evaluate(
            input: "Перенеси встречу с Ивановым на четверг.",
            output: "Предлагаю перенести встречу с Ивановым на четверг.",
            contract: .rewriting
        )

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.output, "Предлагаю перенести встречу с Ивановым на четверг.")
    }
}
