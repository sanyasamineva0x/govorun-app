@testable import Govorun
import XCTest

final class SuperTextStyleTests: XCTestCase {

    // MARK: - Enum cases

    func test_has_exactly_three_cases() {
        XCTAssertEqual(SuperTextStyle.allCases.count, 3)
    }

    func test_raw_values() {
        XCTAssertEqual(SuperTextStyle.relaxed.rawValue, "relaxed")
        XCTAssertEqual(SuperTextStyle.normal.rawValue, "normal")
        XCTAssertEqual(SuperTextStyle.formal.rawValue, "formal")
    }

    func test_codable_roundtrip() throws {
        for style in SuperTextStyle.allCases {
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(SuperTextStyle.self, from: data)
            XCTAssertEqual(decoded, style)
        }
    }

    // MARK: - SuperStyleMode

    func test_style_mode_has_exactly_two_cases() {
        XCTAssertEqual(SuperStyleMode.allCases.count, 2)
    }

    func test_style_mode_raw_values() {
        XCTAssertEqual(SuperStyleMode.auto.rawValue, "auto")
        XCTAssertEqual(SuperStyleMode.manual.rawValue, "manual")
    }

    // MARK: - contract

    func test_contract_returns_normalization_for_all_styles() {
        for style in SuperTextStyle.allCases {
            XCTAssertEqual(style.contract, .normalization, "\(style) should return .normalization")
        }
    }

    // MARK: - displayName

    func test_display_name_relaxed() {
        XCTAssertEqual(SuperTextStyle.relaxed.displayName, "Расслабленный")
    }

    func test_display_name_normal() {
        XCTAssertEqual(SuperTextStyle.normal.displayName, "Обычный")
    }

    func test_display_name_formal() {
        XCTAssertEqual(SuperTextStyle.formal.displayName, "Формальный")
    }

    // MARK: - applyDeterministic

    func test_apply_deterministic_relaxed_lowercases_first_letter() {
        XCTAssertEqual(SuperTextStyle.relaxed.applyDeterministic("привет"), "привет")
    }

    func test_apply_deterministic_normal_uppercases_first_letter() {
        XCTAssertEqual(SuperTextStyle.normal.applyDeterministic("привет"), "Привет")
    }

    func test_apply_deterministic_formal_uppercases_first_letter() {
        XCTAssertEqual(SuperTextStyle.formal.applyDeterministic("привет"), "Привет")
    }

    func test_apply_deterministic_relaxed_lowercases_uppercase_input() {
        XCTAssertEqual(SuperTextStyle.relaxed.applyDeterministic("Слово"), "слово")
    }

    func test_apply_deterministic_empty_string_all_styles() {
        for style in SuperTextStyle.allCases {
            XCTAssertEqual(style.applyDeterministic(""), "", "\(style) should handle empty string")
        }
    }

    // MARK: - Alias tables

    func test_brand_aliases_count() {
        XCTAssertEqual(SuperTextStyle.brandAliases.count, 25)
    }

    func test_tech_term_aliases_count() {
        XCTAssertEqual(SuperTextStyle.techTermAliases.count, 4)
    }

    func test_brand_aliases_contains_slack() {
        XCTAssertTrue(
            SuperTextStyle.brandAliases.contains(where: { $0.original == "Slack" && $0.relaxed == "слак" })
        )
    }

    func test_brand_aliases_contains_telegram() {
        XCTAssertTrue(
            SuperTextStyle.brandAliases.contains(where: { $0.original == "Telegram" && $0.relaxed == "телега" })
        )
    }

    func test_brand_aliases_contains_python() {
        XCTAssertTrue(
            SuperTextStyle.brandAliases.contains(where: { $0.original == "Python" && $0.relaxed == "питон" })
        )
    }

    func test_tech_term_aliases_contains_pdf() {
        XCTAssertTrue(
            SuperTextStyle.techTermAliases.contains(where: { $0.original == "PDF" && $0.relaxed == "пдф" })
        )
    }

    func test_tech_term_aliases_contains_api() {
        XCTAssertTrue(
            SuperTextStyle.techTermAliases.contains(where: { $0.original == "API" && $0.relaxed == "апи" })
        )
    }

    func test_tech_term_aliases_contains_url() {
        XCTAssertTrue(
            SuperTextStyle.techTermAliases.contains(where: { $0.original == "URL" && $0.relaxed == "урл" })
        )
    }

    func test_tech_term_aliases_contains_pr() {
        XCTAssertTrue(
            SuperTextStyle.techTermAliases.contains(where: { $0.original == "PR" && $0.relaxed == "пр" })
        )
    }
}
