@testable import Govorun
import XCTest

// MARK: - Мок WorkspaceProviding

final class MockWorkspaceProvider: WorkspaceProviding {
    var bundleId: String?
    var appName: String?

    func frontmostApp() -> (bundleId: String?, appName: String?) {
        (bundleId, appName)
    }
}

// MARK: - Тесты AppContextEngine

final class AppContextEngineTests: XCTestCase {
    private func makeEngine(
        bundleId: String? = nil,
        appName: String? = nil
    ) -> (AppContextEngine, MockWorkspaceProvider) {
        let workspace = MockWorkspaceProvider()
        workspace.bundleId = bundleId
        workspace.appName = appName

        let engine = AppContextEngine(workspace: workspace)
        return (engine, workspace)
    }

    // MARK: - 1. Telegram: bundleId и appName определяются

    func test_telegram_detected() {
        let (engine, _) = makeEngine(
            bundleId: "ru.keepcoder.Telegram",
            appName: "Telegram"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.bundleId, "ru.keepcoder.Telegram")
        XCTAssertEqual(context.appName, "Telegram")
    }

    // MARK: - 2. Safari: bundleId и appName определяются

    func test_safari_detected() {
        let (engine, _) = makeEngine(
            bundleId: "com.apple.Safari",
            appName: "Safari"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.bundleId, "com.apple.Safari")
        XCTAssertEqual(context.appName, "Safari")
    }

    // MARK: - 3. Неизвестное приложение: bundleId и appName определяются

    func test_unknown_app_detected() {
        let (engine, _) = makeEngine(
            bundleId: "com.some.unknown.app",
            appName: "UnknownApp"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.bundleId, "com.some.unknown.app")
        XCTAssertEqual(context.appName, "UnknownApp")
    }

    // MARK: - 4. Нет frontmost app → пустые строки

    func test_nil_bundle_id_returns_empty_strings() {
        let (engine, _) = makeEngine(
            bundleId: nil,
            appName: nil
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.bundleId, "")
        XCTAssertEqual(context.appName, "")
    }

    // MARK: - 5. Промпт зависит от стиля

    func test_prompt_varies_by_mode() {
        let date = Date(timeIntervalSince1970: 1_710_000_000)

        let relaxedPrompt = SuperTextStyle.relaxed.systemPrompt(currentDate: date)
        let formalPrompt = SuperTextStyle.formal.systemPrompt(currentDate: date)

        XCTAssertNotEqual(relaxedPrompt, formalPrompt)
    }

    // MARK: - 6. .relaxed → разговорный стиль

    func test_relaxed_style_uses_conversational_register() {
        let style = SuperTextStyle.relaxed.styleBlock
        XCTAssertTrue(style.contains("разговорный"))
    }

    // MARK: - 7. .formal → деловой стиль

    func test_formal_style_uses_business_register() {
        let style = SuperTextStyle.formal.styleBlock
        XCTAssertTrue(style.contains("деловой"))
    }

    // MARK: - 8. Промпт содержит текущую дату

    func test_prompt_includes_current_date() throws {
        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(year: 2_026, month: 3, day: 10)
        let date = try XCTUnwrap(calendar.date(from: components))

        let prompt = SuperTextStyle.normal.systemPrompt(currentDate: date)

        XCTAssertTrue(prompt.contains("10"))
        XCTAssertTrue(prompt.contains("2026"))
    }

    func test_prompt_preserves_command_frame_examples() {
        let prompt = SuperTextStyle.normal.systemPrompt(currentDate: Date())

        XCTAssertTrue(prompt.contains("СОХРАНИ эту рамку"))
        XCTAssertTrue(prompt.contains("«Запиши, что ...» НЕЛЬЗЯ превращать просто в «...»"))
        XCTAssertTrue(prompt.contains("«Подготовь текст: ...» НЕЛЬЗЯ превращать в обычное сообщение без этой рамки"))
        XCTAssertTrue(prompt.contains("«Запиши, что релиз переносится на 23 марта 2026»"))
    }

    func test_prompt_includes_anti_paraphrase_long_form_examples() {
        let prompt = SuperTextStyle.normal.systemPrompt(currentDate: Date())

        XCTAssertTrue(prompt.contains("НЕ компрессируй длинную диктовку"))
        XCTAssertTrue(prompt.contains("НЕ пересказывай и НЕ упрощай инструкцию"))
        XCTAssertTrue(prompt.contains("«Подготовь текст: demo прошло хорошо, но клиент просит добавить экспорт в PDF, офлайн-режим и синхронизацию со своим Jira Server»"))
        XCTAssertTrue(prompt.contains("«Добавь заметку: если Sparkle-обновление не сработает, нужно проверить appcast, подпись, длину enclosure и CURRENT_PROJECT_VERSION»"))
    }

    func test_prompt_correction_examples_preserve_explicit_time_of_day() {
        let prompt = SuperTextStyle.normal.systemPrompt(currentDate: Date())

        XCTAssertTrue(prompt.contains("«позвони в восемь вечера или нет лучше в девять» → «Позвони в девять вечера»"))
        XCTAssertTrue(prompt.contains("«позвони маме в восемь вечера или нет лучше в девять» → «Позвони маме в девять вечера»"))
    }
}
