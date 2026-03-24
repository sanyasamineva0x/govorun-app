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

// MARK: - Мок AppModeOverriding

final class MockAppModeOverrides: AppModeOverriding {
    var overrides: [String: String] = [:]

    func modeOverride(for bundleId: String) -> String? {
        overrides[bundleId]
    }

    func setModeOverride(_ mode: String?, for bundleId: String) {
        overrides[bundleId] = mode
    }

    func allOverrides() -> [String: String] {
        overrides
    }
}

// MARK: - Тесты AppContextEngine

final class AppContextEngineTests: XCTestCase {
    private func makeEngine(
        bundleId: String? = nil,
        appName: String? = nil,
        overrides: [String: String] = [:]
    ) -> (AppContextEngine, MockWorkspaceProvider, MockAppModeOverrides) {
        let workspace = MockWorkspaceProvider()
        workspace.bundleId = bundleId
        workspace.appName = appName

        let modeOverrides = MockAppModeOverrides()
        modeOverrides.overrides = overrides

        let engine = AppContextEngine(
            workspace: workspace,
            modeOverrides: modeOverrides
        )
        return (engine, workspace, modeOverrides)
    }

    // MARK: - 1. Telegram → .chat

    func test_telegram_detected_as_chat() {
        let (engine, _, _) = makeEngine(
            bundleId: "ru.keepcoder.Telegram",
            appName: "Telegram"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.bundleId, "ru.keepcoder.Telegram")
        XCTAssertEqual(context.appName, "Telegram")
        XCTAssertEqual(context.textMode, .chat)
    }

    // MARK: - 2. Mail → .email

    func test_mail_detected_as_email() {
        let (engine, _, _) = makeEngine(
            bundleId: "com.apple.mail",
            appName: "Mail"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .email)
    }

    // MARK: - 3. Chrome → .universal

    func test_chrome_detected_as_universal() {
        let (engine, _, _) = makeEngine(
            bundleId: "com.google.Chrome",
            appName: "Google Chrome"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .universal)
    }

    // MARK: - 4. Safari → .universal

    func test_safari_detected_as_universal() {
        let (engine, _, _) = makeEngine(
            bundleId: "com.apple.Safari",
            appName: "Safari"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .universal)
    }

    // MARK: - 5. Неизвестное приложение → .universal

    func test_unknown_app_is_universal() {
        let (engine, _, _) = makeEngine(
            bundleId: "com.some.unknown.app",
            appName: "UnknownApp"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .universal)
    }

    // MARK: - 6. Пользовательское переопределение

    func test_user_override_respected() {
        let (engine, _, _) = makeEngine(
            bundleId: "com.google.Chrome",
            appName: "Google Chrome",
            overrides: ["com.google.Chrome": "email"]
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .email)
    }

    // MARK: - 7. Промпт зависит от режима

    func test_prompt_varies_by_mode() {
        let date = Date(timeIntervalSince1970: 1_710_000_000) // фиксированная дата

        let chatPrompt = TextMode.chat.systemPrompt(currentDate: date)
        let emailPrompt = TextMode.email.systemPrompt(currentDate: date)

        XCTAssertNotEqual(chatPrompt, emailPrompt)
    }

    // MARK: - 8. .chat → регистр "ты"

    func test_chat_mode_uses_ty_register() {
        let style = TextMode.chat.styleBlock
        XCTAssertTrue(style.contains("\"ты\""))
    }

    // MARK: - 9. .email → регистр "Вы"

    func test_email_mode_uses_vy_register() {
        let style = TextMode.email.styleBlock
        XCTAssertTrue(style.contains("\"Вы\""))
    }

    // MARK: - 10. Промпт содержит текущую дату

    func test_prompt_includes_current_date() throws {
        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(year: 2_026, month: 3, day: 10)
        let date = try XCTUnwrap(calendar.date(from: components))

        let prompt = TextMode.universal.systemPrompt(currentDate: date)

        XCTAssertTrue(prompt.contains("10"))
        XCTAssertTrue(prompt.contains("2026"))
    }

    // MARK: - 11. Нет frontmost app → .universal

    func test_nil_bundle_id_is_universal() {
        let (engine, _, _) = makeEngine(
            bundleId: nil,
            appName: nil
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .universal)
        XCTAssertEqual(context.bundleId, "")
        XCTAssertEqual(context.appName, "")
    }

    // MARK: - 12. Slack → .chat

    func test_slack_detected_as_chat() {
        let (engine, _, _) = makeEngine(
            bundleId: "com.tinyspeck.slackmacgap",
            appName: "Slack"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .chat)
    }

    // MARK: - 13. VS Code → .code

    func test_vscode_detected_as_code() {
        let (engine, _, _) = makeEngine(
            bundleId: "com.microsoft.VSCode",
            appName: "Visual Studio Code"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .code)
    }

    // MARK: - 14. Notes → .note

    func test_notes_detected_as_note() {
        let (engine, _, _) = makeEngine(
            bundleId: "com.apple.Notes",
            appName: "Notes"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .note)
    }

    // MARK: - 15. Pages → .document

    func test_pages_detected_as_document() {
        let (engine, _, _) = makeEngine(
            bundleId: "com.apple.iWork.Pages",
            appName: "Pages"
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .document)
    }

    // MARK: - 16. textMode(for:) прямой вызов

    func test_textMode_for_known_bundleId() {
        let (engine, _, _) = makeEngine()

        XCTAssertEqual(engine.textMode(for: "ru.keepcoder.Telegram"), .chat)
        XCTAssertEqual(engine.textMode(for: "com.apple.mail"), .email)
        XCTAssertEqual(engine.textMode(for: "com.microsoft.VSCode"), .code)
        XCTAssertEqual(engine.textMode(for: "com.unknown.app"), .universal)
    }

    // MARK: - 17. Override приоритетнее дефолта

    func test_override_takes_priority_over_default() {
        let (engine, _, overrides) = makeEngine(
            bundleId: "ru.keepcoder.Telegram",
            appName: "Telegram"
        )

        // Без override: .chat
        XCTAssertEqual(engine.detectCurrentApp().textMode, .chat)

        // С override: .email
        overrides.overrides["ru.keepcoder.Telegram"] = "email"
        XCTAssertEqual(engine.detectCurrentApp().textMode, .email)
    }

    // MARK: - 18. Невалидный override → fallback на дефолт

    func test_invalid_override_falls_back_to_default() {
        let (engine, _, _) = makeEngine(
            bundleId: "ru.keepcoder.Telegram",
            appName: "Telegram",
            overrides: ["ru.keepcoder.Telegram": "nonexistent_mode"]
        )
        let context = engine.detectCurrentApp()

        XCTAssertEqual(context.textMode, .chat)
    }
}
