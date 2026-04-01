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

    // MARK: - styleBlock

    func test_style_block_relaxed_contains_brand_instruction() {
        let block = SuperTextStyle.relaxed.styleBlock
        XCTAssertTrue(block.contains("бренды"), "relaxed styleBlock should mention brands")
        XCTAssertTrue(block.contains("кириллица"), "relaxed styleBlock should mention cyrillic")
    }

    func test_style_block_relaxed_contains_brand_aliases() {
        let block = SuperTextStyle.relaxed.styleBlock
        XCTAssertTrue(block.contains("слак"), "relaxed styleBlock should contain слак")
        XCTAssertTrue(block.contains("зум"), "relaxed styleBlock should contain зум")
        XCTAssertTrue(block.contains("телега"), "relaxed styleBlock should contain телега")
    }

    func test_style_block_relaxed_contains_tech_term_aliases() {
        let block = SuperTextStyle.relaxed.styleBlock
        XCTAssertTrue(block.contains("пдф"), "relaxed styleBlock should contain пдф")
        XCTAssertTrue(block.contains("апи"), "relaxed styleBlock should contain апи")
        XCTAssertTrue(block.contains("урл"), "relaxed styleBlock should contain урл")
        XCTAssertTrue(block.contains("пр"), "relaxed styleBlock should contain пр")
    }

    func test_style_block_relaxed_no_capitalization() {
        let block = SuperTextStyle.relaxed.styleBlock
        XCTAssertTrue(block.contains("НЕ ставь заглавную букву"))
    }

    func test_style_block_relaxed_no_trailing_dot() {
        let block = SuperTextStyle.relaxed.styleBlock
        XCTAssertTrue(block.contains("Без точки в конце"))
    }

    func test_style_block_normal_original_brands() {
        let block = SuperTextStyle.normal.styleBlock
        XCTAssertTrue(block.contains("оригинальное написание"))
    }

    func test_style_block_normal_no_relaxed_aliases() {
        let block = SuperTextStyle.normal.styleBlock
        XCTAssertFalse(block.contains("слак"), "normal styleBlock should not contain слак")
        XCTAssertFalse(block.contains("зум"), "normal styleBlock should not contain зум")
    }

    func test_style_block_formal_slang_expansion() {
        let block = SuperTextStyle.formal.styleBlock
        XCTAssertTrue(block.contains("Сленг раскрывать"))
    }

    func test_style_block_formal_original_brands() {
        let block = SuperTextStyle.formal.styleBlock
        XCTAssertTrue(block.contains("оригинальное написание"))
    }

    // MARK: - basePrompt

    private var fixedDate: Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 1
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func test_base_prompt_contains_postprocessor() {
        let prompt = SuperTextStyle.basePrompt(currentDate: fixedDate)
        XCTAssertTrue(prompt.contains("постпроцессор голосового ввода"))
    }

    func test_base_prompt_contains_date() {
        let prompt = SuperTextStyle.basePrompt(currentDate: fixedDate)
        XCTAssertTrue(prompt.contains("1 января 2025"))
    }

    func test_base_prompt_contains_self_correction() {
        let prompt = SuperTextStyle.basePrompt(currentDate: fixedDate)
        XCTAssertTrue(prompt.contains("САМОКОРРЕКЦИЯ"))
    }

    func test_base_prompt_contains_transliteration() {
        let prompt = SuperTextStyle.basePrompt(currentDate: fixedDate)
        XCTAssertTrue(prompt.contains("ТРАНСЛИТЕРАЦИЯ"))
    }

    func test_base_prompt_contains_numbers_section() {
        let prompt = SuperTextStyle.basePrompt(currentDate: fixedDate)
        XCTAssertTrue(prompt.contains("ЧИСЛА, ВАЛЮТЫ И ДАТЫ"))
    }

    func test_base_prompt_with_personal_dictionary() {
        let prompt = SuperTextStyle.basePrompt(
            currentDate: fixedDate,
            personalDictionary: ["тест": "Тест"]
        )
        XCTAssertTrue(prompt.contains("Личный словарь"))
        XCTAssertTrue(prompt.contains("тест→Тест"))
    }

    // MARK: - systemPrompt

    func test_system_prompt_contains_base_prompt() {
        let prompt = SuperTextStyle.normal.systemPrompt(currentDate: fixedDate)
        XCTAssertTrue(prompt.contains("постпроцессор голосового ввода"))
    }

    func test_system_prompt_contains_style_block() {
        let prompt = SuperTextStyle.relaxed.systemPrompt(currentDate: fixedDate)
        XCTAssertTrue(prompt.contains("слак"), "systemPrompt for relaxed should contain relaxed aliases")
    }

    func test_system_prompt_with_app_name() {
        let prompt = SuperTextStyle.normal.systemPrompt(
            currentDate: fixedDate,
            appName: "Telegram"
        )
        XCTAssertTrue(prompt.contains("КОНТЕКСТ ПРИЛОЖЕНИЯ"))
        XCTAssertTrue(prompt.contains("Telegram"))
    }

    func test_system_prompt_without_app_name() {
        let prompt = SuperTextStyle.normal.systemPrompt(currentDate: fixedDate)
        XCTAssertFalse(prompt.contains("КОНТЕКСТ ПРИЛОЖЕНИЯ"))
    }

    func test_system_prompt_with_snippet_context() {
        let prompt = SuperTextStyle.normal.systemPrompt(
            currentDate: fixedDate,
            snippetContext: SnippetContext(trigger: "мой имейл")
        )
        XCTAssertTrue(prompt.contains("ПОДСТАНОВКА"))
        XCTAssertTrue(prompt.contains("мой имейл"))
    }

    func test_system_prompt_without_snippet_context() {
        let prompt = SuperTextStyle.normal.systemPrompt(currentDate: fixedDate)
        XCTAssertFalse(prompt.contains("ПОДСТАНОВКА"))
    }

    // MARK: - cardDescription

    func test_card_description_relaxed() {
        XCTAssertEqual(
            SuperTextStyle.relaxed.cardDescription,
            "Как в мессенджере — строчные буквы, бренды кириллицей, без точки"
        )
    }

    func test_card_description_normal() {
        XCTAssertEqual(
            SuperTextStyle.normal.cardDescription,
            "Стандартный — заглавная буква, бренды оригинальные, без точки"
        )
    }

    func test_card_description_formal() {
        XCTAssertEqual(
            SuperTextStyle.formal.cardDescription,
            "Деловой — заглавная буква, бренды оригинальные, сленг раскрыт, точка в конце"
        )
    }

    // MARK: - SuperStyleMode displayName

    func test_super_style_mode_display_name_auto() {
        XCTAssertEqual(SuperStyleMode.auto.displayName, "Авто")
    }

    func test_super_style_mode_display_name_manual() {
        XCTAssertEqual(SuperStyleMode.manual.displayName, "Ручной")
    }
}
