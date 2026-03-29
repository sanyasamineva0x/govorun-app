# Text Styles v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить три стиля текста (relaxed/normal/formal) для Говорун Super с авто/ручным переключением, не затрагивая classic path.

**Architecture:** Новый enum `SuperTextStyle` + `SuperStyleEngine` (bundleId → стиль) параллельно существующему `TextMode`. PipelineEngine в Super mode использует `SuperTextStyle` для промпта и gate policy. Classic path без изменений.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit (NSMenu), XCTest

**Spec:** `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md`

---

## File Structure

| Действие | Файл | Ответственность |
|----------|------|-----------------|
| Create | `Govorun/Models/SuperTextStyle.swift` | Enum + styleBlock + systemPrompt генерация |
| Create | `Govorun/Core/SuperStyleEngine.swift` | bundleId → SuperTextStyle, авто/ручной |
| Create | `Govorun/Views/SuperStyleMenuSection.swift` | Menubar UI: сегмент + карточки стилей |
| Create | `Govorun/Views/SuperModelRequiredAlert.swift` | Окно "нужна модель" + кнопка "Понял" |
| Modify | `Govorun/Storage/SettingsStore.swift` | Новые ключи: superStyleMode, manualSuperStyle |
| Modify | `Govorun/Services/LLMClient.swift` | Новая перегрузка normalize с SuperTextStyle |
| Modify | `Govorun/Services/LocalLLMClient.swift` | sendChatCompletion с SuperTextStyle prompt |
| Modify | `GovorunTests/TestHelpers.swift` | MockLLMClient — новая перегрузка |
| Modify | `Govorun/Core/NormalizationGate.swift` | Style-aware protected tokens + edit distance |
| Modify | `Govorun/Core/NormalizationPipeline.swift` | postflight: стиль владеет точкой в Super |
| Modify | `Govorun/Core/PipelineEngine.swift` | Интеграция SuperTextStyle во все ветки Super path |
| Modify | `Govorun/App/AppState.swift` | SuperStyleEngine init + передача стиля |
| Modify | `Govorun/App/StatusBarController.swift` | NSHostingView bridge для SuperStyleMenuSection |
| Create | `GovorunTests/SuperTextStyleTests.swift` | Тесты enum, styleBlock, промпт |
| Create | `GovorunTests/SuperStyleEngineTests.swift` | Тесты маппинга, авто/ручной |
| Create | `GovorunTests/NormalizationGateStyleTests.swift` | Тесты style-aware gate |
| Modify | `GovorunTests/NormalizationPipelineTests.swift` | Тесты postflight с SuperTextStyle |
| Create | `GovorunTests/LLMClientSuperStyleTests.swift` | Тесты LLMClient с SuperTextStyle |

---

### Task 1: SuperTextStyle enum

**Files:**
- Create: `Govorun/Models/SuperTextStyle.swift`
- Create: `GovorunTests/SuperTextStyleTests.swift`

- [ ] **Step 1: Написать тесты enum**

```swift
// GovorunTests/SuperTextStyleTests.swift
import XCTest
@testable import Govorun

final class SuperTextStyleTests: XCTestCase {

    // MARK: - Enum basics

    func test_all_cases_exist() {
        let cases = SuperTextStyle.allCases
        XCTAssertEqual(cases.count, 3)
        XCTAssertTrue(cases.contains(.relaxed))
        XCTAssertTrue(cases.contains(.normal))
        XCTAssertTrue(cases.contains(.formal))
    }

    func test_raw_values_are_stable() {
        XCTAssertEqual(SuperTextStyle.relaxed.rawValue, "relaxed")
        XCTAssertEqual(SuperTextStyle.normal.rawValue, "normal")
        XCTAssertEqual(SuperTextStyle.formal.rawValue, "formal")
    }

    func test_codable_round_trip() throws {
        for style in SuperTextStyle.allCases {
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(SuperTextStyle.self, from: data)
            XCTAssertEqual(style, decoded)
        }
    }

    // MARK: - UI labels

    func test_display_names() {
        XCTAssertEqual(SuperTextStyle.relaxed.displayName, "Расслабленный")
        XCTAssertEqual(SuperTextStyle.normal.displayName, "Обычный")
        XCTAssertEqual(SuperTextStyle.formal.displayName, "Формальный")
    }

    func test_short_descriptions() {
        XCTAssertFalse(SuperTextStyle.relaxed.shortDescription.isEmpty)
        XCTAssertFalse(SuperTextStyle.normal.shortDescription.isEmpty)
        XCTAssertFalse(SuperTextStyle.formal.shortDescription.isEmpty)
    }

    // MARK: - Terminal period

    func test_terminal_period_policy() {
        XCTAssertFalse(SuperTextStyle.relaxed.terminalPeriod)
        XCTAssertFalse(SuperTextStyle.normal.terminalPeriod)
        XCTAssertTrue(SuperTextStyle.formal.terminalPeriod)
    }
}
```

- [ ] **Step 2: Запустить тесты — убедиться что падают**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests 2>&1 | tail -5`
Expected: FAIL — `SuperTextStyle` not found

- [ ] **Step 3: Реализовать enum**

```swift
// Govorun/Models/SuperTextStyle.swift
import Foundation

enum SuperTextStyle: String, CaseIterable, Codable {
    case relaxed
    case normal
    case formal

    var displayName: String {
        switch self {
        case .relaxed: "Расслабленный"
        case .normal: "Обычный"
        case .formal: "Формальный"
        }
    }

    var shortDescription: String {
        switch self {
        case .relaxed: "строчные, без точек, сленг ок"
        case .normal: "с заглавной, без точки"
        case .formal: "с заглавной, точка, полные слова"
        }
    }

    var terminalPeriod: Bool {
        self == .formal
    }
}
```

- [ ] **Step 4: Запустить тесты — убедиться что проходят**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Добавить в project.yml и перегенерировать**

Добавить `Govorun/Models/SuperTextStyle.swift` и `GovorunTests/SuperTextStyleTests.swift` в sources (если xcodegen использует directory-based sources — достаточно положить файлы в правильные папки). Run: `cd ~/Desktop/govorun-app && xcodegen generate`

- [ ] **Step 6: Коммит**

```bash
git add Govorun/Models/SuperTextStyle.swift GovorunTests/SuperTextStyleTests.swift
git commit -m "feat: добавить SuperTextStyle enum (relaxed/normal/formal)"
```

---

### Task 2: Style blocks для промпта

**Files:**
- Modify: `Govorun/Models/SuperTextStyle.swift`
- Modify: `GovorunTests/SuperTextStyleTests.swift`

- [ ] **Step 1: Написать тесты styleBlock**

Добавить в `SuperTextStyleTests.swift`:

```swift
// MARK: - Style blocks

func test_relaxed_style_block_contains_lowercase_rule() {
    let block = SuperTextStyle.relaxed.styleBlock
    XCTAssertTrue(block.contains("строчными"), "relaxed должен указывать строчные буквы")
    XCTAssertTrue(block.contains("слак"), "relaxed должен содержать пример кириллицы бренда")
}

func test_relaxed_style_block_contains_slang_preservation() {
    let block = SuperTextStyle.relaxed.styleBlock
    XCTAssertTrue(block.contains("сленг"), "relaxed должен упоминать сленг")
}

func test_normal_style_block_contains_capital_rule() {
    let block = SuperTextStyle.normal.styleBlock
    XCTAssertTrue(block.contains("заглавн"), "normal должен указывать заглавную букву")
    XCTAssertTrue(block.contains("Slack"), "normal должен содержать оригинал бренда")
}

func test_formal_style_block_contains_period_and_slang_expansion() {
    let block = SuperTextStyle.formal.styleBlock
    XCTAssertTrue(block.contains("точк"), "formal должен указывать точку")
    XCTAssertTrue(block.contains("спасибо"), "formal должен раскрывать сленг")
}

func test_all_style_blocks_contain_filler_removal() {
    for style in SuperTextStyle.allCases {
        XCTAssertTrue(
            style.styleBlock.contains("филлер"),
            "\(style) должен убирать филлеры"
        )
    }
}
```

- [ ] **Step 2: Запустить — убедиться что падают**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests 2>&1 | tail -5`
Expected: FAIL — `styleBlock` not found

- [ ] **Step 3: Реализовать styleBlock**

Добавить в `SuperTextStyle.swift`:

```swift
// MARK: - Промпт

extension SuperTextStyle {
    var styleBlock: String {
        switch self {
        case .relaxed:
            """
            СТИЛЬ: Расслабленный (мессенджер).
            ПЕРЕОПРЕДЕЛЕНИЕ регистра: НЕ ставь заглавную букву в начале. Пиши строчными.
            Без точки в конце.
            Сленг сохраняй как есть: норм, спс, ок, плиз, имхо.
            Филлеры (ну, короче, типа, в общем, как бы) — убирай.
            ТРАНСЛИТЕРАЦИЯ брендов → кириллица строчными: слак, зум, телега, жира, ношен, \
            гитхаб, ютуб, гугл, вотсап, дискорд, фигма, докер, хром, сафари, тимс, \
            трелло, конфлюенс, эксель, ворд, фотошоп, айфон, макбук, винда, линукс, питон.
            Техтермины → кириллица где естественно: пдф, апи, урл, пр.
            Остальные техтермины (CSV, CI/CD, QA, ML, iOS) — оригинал.
            Пример: «скинь в слак что митинг в четверг» → «скинь в слак что митинг в четверг»
            """
        case .normal:
            """
            СТИЛЬ: Обычный.
            Заглавная буква в начале предложения. Без точки в конце.
            Сленг сохраняй как есть: норм, спс, ок.
            Филлеры (ну, короче, типа, в общем, как бы) — убирай.
            ТРАНСЛИТЕРАЦИЯ: бренды → оригинал (Slack, Zoom, Telegram, Jira, Notion, \
            GitHub, YouTube, Google, WhatsApp, Discord, Figma, Docker, Chrome, Safari, \
            Teams, Trello, Confluence, Excel, Word, Photoshop, iPhone, MacBook, Windows, Linux, Python).
            Техтермины → оригинал: PDF, API, URL, PR.
            Пример: «скинь в слак что митинг в четверг» → «Скинь в Slack, что митинг в четверг»
            """
        case .formal:
            """
            СТИЛЬ: Формальный.
            Заглавная буква в начале предложения. Точка в конце.
            Сленг раскрывай полностью: спс→спасибо, норм→нормально, плиз→пожалуйста, ок→хорошо, имхо→по моему мнению.
            Филлеры (ну, короче, типа, в общем, как бы) — убирай.
            ТРАНСЛИТЕРАЦИЯ: бренды → оригинал (Slack, Zoom, Telegram, Jira, Notion, \
            GitHub, YouTube, Google, WhatsApp, Discord, Figma, Docker, Chrome, Safari, \
            Teams, Trello, Confluence, Excel, Word, Photoshop, iPhone, MacBook, Windows, Linux, Python).
            Техтермины → оригинал: PDF, API, URL, PR.
            Пример: «скинь в слак что митинг в четверг спс» → «Скинь в Slack, что митинг в четверг, спасибо.»
            """
        }
    }
}
```

- [ ] **Step 4: Запустить тесты — убедиться что проходят**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Коммит**

```bash
git add Govorun/Models/SuperTextStyle.swift GovorunTests/SuperTextStyleTests.swift
git commit -m "feat: добавить styleBlock для трёх SuperTextStyle"
```

---

### Task 3: systemPrompt генерация для SuperTextStyle

**Files:**
- Modify: `Govorun/Models/SuperTextStyle.swift`
- Modify: `GovorunTests/SuperTextStyleTests.swift`

- [ ] **Step 1: Написать тесты systemPrompt**

Добавить в `SuperTextStyleTests.swift`:

```swift
// MARK: - System prompt

func test_system_prompt_contains_base_and_style() {
    let date = Date(timeIntervalSince1970: 1774800000) // 2026-03-26
    for style in SuperTextStyle.allCases {
        let prompt = style.systemPrompt(currentDate: date)
        XCTAssertTrue(prompt.contains("постпроцессор"), "\(style) prompt должен содержать базовый промпт")
        XCTAssertTrue(prompt.contains("СТИЛЬ:"), "\(style) prompt должен содержать стилевой блок")
    }
}

func test_system_prompt_includes_app_context() {
    let prompt = SuperTextStyle.normal.systemPrompt(
        currentDate: Date(),
        appName: "Telegram"
    )
    XCTAssertTrue(prompt.contains("Telegram"))
    XCTAssertTrue(prompt.contains("КОНТЕКСТ ПРИЛОЖЕНИЯ"))
}

func test_system_prompt_includes_snippet_context() {
    let prompt = SuperTextStyle.normal.systemPrompt(
        currentDate: Date(),
        snippetContext: SnippetContext(trigger: "мой имейл")
    )
    XCTAssertTrue(prompt.contains("мой имейл"))
    XCTAssertTrue(prompt.contains(SnippetPlaceholder.token))
}

func test_system_prompt_includes_personal_dictionary() {
    let prompt = SuperTextStyle.normal.systemPrompt(
        currentDate: Date(),
        personalDictionary: ["алтай": "Алтай"]
    )
    XCTAssertTrue(prompt.contains("алтай→Алтай"))
}

func test_relaxed_prompt_overrides_base_capitalization() {
    let prompt = SuperTextStyle.relaxed.systemPrompt(currentDate: Date())
    // base prompt говорит "ЗАГЛАВНАЯ буква", relaxed переопределяет
    XCTAssertTrue(prompt.contains("ПЕРЕОПРЕДЕЛЕНИЕ регистра"))
}
```

- [ ] **Step 2: Запустить — убедиться что падают**

Expected: FAIL — `systemPrompt` not found on `SuperTextStyle`

- [ ] **Step 3: Реализовать systemPrompt**

Добавить в `SuperTextStyle.swift`:

```swift
extension SuperTextStyle {
    func systemPrompt(
        currentDate: Date,
        personalDictionary: [String: String] = [:],
        snippetContext: SnippetContext? = nil,
        appName: String? = nil
    ) -> String {
        // Переиспользуем базовый промпт из TextMode — он не зависит от стиля
        var prompt = TextMode.basePrompt(
            currentDate: currentDate,
            personalDictionary: personalDictionary
        )
        prompt += "\n\n" + styleBlock

        if let app = appName, !app.isEmpty {
            prompt += """

            КОНТЕКСТ ПРИЛОЖЕНИЯ:
            Пользователь диктует в приложении «\(app)».
            Учитывай это при выборе тональности и оформления.
            """
        }

        if let snippet = snippetContext {
            prompt += """

            ПОДСТАНОВКА:
            Пользователь использовал голосовое сокращение «\(snippet.trigger)».
            На место этого сокращения вставь РОВНО токен \(SnippetPlaceholder.token) — без кавычек, без изменений.
            НЕ вставляй значение сокращения — только токен.
            Построй естественное предложение вокруг токена.
            Токен должен стоять отдельно, окружённым пробелами или пунктуацией.
            """
        }

        return prompt
    }
}
```

- [ ] **Step 4: Запустить тесты — убедиться что проходят**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Коммит**

```bash
git add Govorun/Models/SuperTextStyle.swift GovorunTests/SuperTextStyleTests.swift
git commit -m "feat: добавить systemPrompt генерацию для SuperTextStyle"
```

---

### Task 3.5: LLMClient — перегрузка normalize для SuperTextStyle

**Files:**
- Modify: `Govorun/Services/LLMClient.swift`
- Modify: `Govorun/Services/LocalLLMClient.swift`
- Modify: `GovorunTests/TestHelpers.swift`
- Create: `GovorunTests/LLMClientSuperStyleTests.swift`

Текущий `LLMClient.normalize(_:mode:hints:)` собирает system prompt внутри `LocalLLMClient` через `mode.systemPrompt(...)`. Для Super стилей нужна параллельная перегрузка, которая принимает `SuperTextStyle` и использует его prompt вместо `TextMode`.

- [ ] **Step 1: Написать тесты**

```swift
// GovorunTests/LLMClientSuperStyleTests.swift
import XCTest
@testable import Govorun

final class LLMClientSuperStyleTests: XCTestCase {

    func test_mock_normalize_with_super_style_records_call() async throws {
        let mock = MockLLMClient()
        mock.normalizeResult = "привет"
        let hints = NormalizationHints()

        let result = try await mock.normalize(
            "ну привет",
            superStyle: .relaxed,
            hints: hints
        )

        XCTAssertEqual(result, "привет")
        XCTAssertEqual(mock.normalizeSuperStyleCalls.count, 1)
        XCTAssertEqual(mock.normalizeSuperStyleCalls[0].superStyle, .relaxed)
    }

    func test_mock_normalize_with_super_style_uses_separate_result() async throws {
        let mock = MockLLMClient()
        mock.normalizeResult = "classic result"
        mock.normalizeSuperStyleResult = "super result"
        let hints = NormalizationHints()

        let classicResult = try await mock.normalize("тест", mode: .universal, hints: hints)
        let superResult = try await mock.normalize("тест", superStyle: .relaxed, hints: hints)

        XCTAssertEqual(classicResult, "classic result")
        XCTAssertEqual(superResult, "super result")
    }
}
```

- [ ] **Step 2: Запустить — убедиться что падают**

Expected: FAIL — `normalize(_:superStyle:hints:)` not found

- [ ] **Step 3: Добавить перегрузку в протокол LLMClient**

В `Govorun/Services/LLMClient.swift`, добавить в протокол:

```swift
protocol LLMClient: Sendable {
    func normalize(_ text: String, mode: TextMode, hints: NormalizationHints) async throws -> String
    func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String
}
```

- [ ] **Step 4: Реализовать в LocalLLMClient**

В `Govorun/Services/LocalLLMClient.swift`, добавить метод:

```swift
func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else { return trimmedText }

    let baseURL = try validatedBaseURL()
    let model = try validatedModel()

    try await ensureBackendReady(baseURL: baseURL, model: model)

    do {
        let output = try await sendChatCompletion(
            input: trimmedText,
            superStyle: superStyle,
            hints: hints,
            baseURL: baseURL,
            model: model
        )
        await healthState.recordSuccess(now: Date())
        return output
    } catch is CancellationError {
        throw CancellationError()
    } catch {
        await healthState.recordFailure(
            now: Date(),
            cooldown: configuration.failureCooldown
        )
        Self.logger.error("Local LLM request failed: \(String(describing: error), privacy: .public)")
        throw error
    }
}
```

Добавить приватный `sendChatCompletion` с `superStyle`:

```swift
private func sendChatCompletion(
    input: String,
    superStyle: SuperTextStyle,
    hints: NormalizationHints,
    baseURL: URL,
    model: String
) async throws -> String {
    let systemPrompt = superStyle.systemPrompt(
        currentDate: hints.currentDate,
        personalDictionary: hints.personalDictionary,
        snippetContext: hints.snippetContext,
        appName: hints.appName
    )

    let stopSequences = configuration.stopSequences.isEmpty ? nil : configuration.stopSequences
    let requestBody = ChatCompletionRequest(
        model: model,
        temperature: configuration.temperature,
        maxTokens: configuration.maxOutputTokens,
        stop: stopSequences,
        stream: false,
        messages: [
            .init(role: "system", content: systemPrompt),
            .init(role: "user", content: input),
        ]
    )

    var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
    request.httpMethod = "POST"
    request.timeoutInterval = configuration.requestTimeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(requestBody)

    let (data, response) = try await perform(request)
    try validateStatus(response)
    return try parseOutput(data)
}
```

- [ ] **Step 5: Обновить MockLLMClient в TestHelpers.swift**

В `GovorunTests/TestHelpers.swift`, добавить в `MockLLMClient`:

```swift
var normalizeSuperStyleResult: String?
var normalizeSuperStyleError: Error?
private(set) var normalizeSuperStyleCalls: [(text: String, superStyle: SuperTextStyle, hints: NormalizationHints)] = []

func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
    lock.lock()
    normalizeSuperStyleCalls.append((text, superStyle, hints))
    lock.unlock()

    if let error = normalizeSuperStyleError {
        throw error
    }
    return normalizeSuperStyleResult ?? normalizeResult ?? text
}
```

- [ ] **Step 6: Обновить все другие LLMClient conformance**

Проверить `grep -rn "LLMClient" GovorunTests/ Govorun/Services/` — все типы, conforming к `LLMClient`, должны получить новый метод. Если есть `NoOpLLMClient` или подобные — добавить default implementation через protocol extension:

```swift
extension LLMClient {
    // Дефолт для conformers, не знающих про Super.
    // Используем hints.textMode (а не .universal), чтобы не потерять текущий контекст.
    func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String {
        try await normalize(text, mode: hints.textMode, hints: hints)
    }
}
```

Это сохраняет обратную совместимость — существующие conformance не ломаются.

- [ ] **Step 7: Запустить все тесты**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 8: Коммит**

```bash
git add Govorun/Services/LLMClient.swift Govorun/Services/LocalLLMClient.swift GovorunTests/TestHelpers.swift GovorunTests/LLMClientSuperStyleTests.swift
git commit -m "feat: LLMClient.normalize с SuperTextStyle (перегрузка, не замена)"
```

---

### Task 4: SuperStyleEngine (bundleId → стиль)

**Files:**
- Create: `Govorun/Core/SuperStyleEngine.swift`
- Create: `GovorunTests/SuperStyleEngineTests.swift`

- [ ] **Step 1: Написать тесты**

```swift
// GovorunTests/SuperStyleEngineTests.swift
import XCTest
@testable import Govorun

final class SuperStyleEngineTests: XCTestCase {

    // MARK: - Авто режим

    func test_telegram_is_relaxed() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "ru.keepcoder.Telegram"), .relaxed)
    }

    func test_whatsapp_is_relaxed() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "net.whatsapp.WhatsApp"), .relaxed)
    }

    func test_viber_is_relaxed() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "com.viber.osx"), .relaxed)
    }

    func test_vk_messenger_is_relaxed() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "com.vk.messenger"), .relaxed)
    }

    func test_imessage_is_relaxed() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "com.apple.MobileSMS"), .relaxed)
    }

    func test_discord_is_relaxed() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "com.hnc.Discord"), .relaxed)
    }

    func test_mail_is_formal() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "com.apple.mail"), .formal)
    }

    func test_spark_is_formal() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "com.readdle.smartemail-macos"), .formal)
    }

    func test_outlook_is_formal() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "com.microsoft.Outlook"), .formal)
    }

    func test_unknown_app_is_normal() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "com.example.unknown"), .normal)
    }

    func test_chrome_is_normal() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "com.google.Chrome"), .normal)
    }

    func test_xcode_is_normal() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: "com.apple.dt.Xcode"), .normal)
    }

    func test_nil_bundle_id_is_normal() {
        let engine = SuperStyleEngine(mode: .auto)
        XCTAssertEqual(engine.style(for: nil), .normal)
    }

    // MARK: - Ручной режим

    func test_manual_ignores_bundle_id() {
        let engine = SuperStyleEngine(mode: .manual(.formal))
        XCTAssertEqual(engine.style(for: "ru.keepcoder.Telegram"), .formal)
    }

    func test_manual_relaxed_for_all() {
        let engine = SuperStyleEngine(mode: .manual(.relaxed))
        XCTAssertEqual(engine.style(for: "com.apple.mail"), .relaxed)
        XCTAssertEqual(engine.style(for: "com.google.Chrome"), .relaxed)
        XCTAssertEqual(engine.style(for: nil), .relaxed)
    }
}
```

- [ ] **Step 2: Запустить — убедиться что падают**

Expected: FAIL — `SuperStyleEngine` not found

- [ ] **Step 3: Реализовать**

```swift
// Govorun/Core/SuperStyleEngine.swift
import Foundation

enum SuperStyleMode: Equatable {
    case auto
    case manual(SuperTextStyle)
}

struct SuperStyleEngine {
    let mode: SuperStyleMode

    func style(for bundleId: String?) -> SuperTextStyle {
        switch mode {
        case .manual(let fixed):
            return fixed
        case .auto:
            guard let id = bundleId else { return .normal }
            return Self.defaultMapping[id] ?? .normal
        }
    }

    private static let defaultMapping: [String: SuperTextStyle] = [
        // relaxed — мессенджеры
        "ru.keepcoder.Telegram": .relaxed,
        "net.whatsapp.WhatsApp": .relaxed,
        "com.viber.osx": .relaxed,
        "com.vk.messenger": .relaxed,
        "com.apple.MobileSMS": .relaxed,
        "com.hnc.Discord": .relaxed,
        // formal — почта
        "com.apple.mail": .formal,
        "com.readdle.smartemail-macos": .formal,
        "com.microsoft.Outlook": .formal,
    ]
}
```

- [ ] **Step 4: Запустить тесты — убедиться что проходят**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperStyleEngineTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Коммит**

```bash
git add Govorun/Core/SuperStyleEngine.swift GovorunTests/SuperStyleEngineTests.swift
git commit -m "feat: добавить SuperStyleEngine (bundleId → стиль, авто/ручной)"
```

---

### Task 5: SettingsStore — персистенция стиля

**Files:**
- Modify: `Govorun/Storage/SettingsStore.swift`
- Create: `GovorunTests/SuperStyleSettingsTests.swift`

- [ ] **Step 1: Написать тесты**

```swift
// GovorunTests/SuperStyleSettingsTests.swift
import XCTest
@testable import Govorun

final class SuperStyleSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SuperStyleSettingsTests")!
        defaults.removePersistentDomain(forName: "SuperStyleSettingsTests")
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SuperStyleSettingsTests")
        super.tearDown()
    }

    func test_default_super_style_mode_is_auto() {
        XCTAssertEqual(store.superStyleMode, .auto)
    }

    func test_set_super_style_mode_manual() {
        store.superStyleMode = .manual
        XCTAssertEqual(store.superStyleMode, .manual)
    }

    func test_default_manual_super_style_is_normal() {
        XCTAssertEqual(store.manualSuperStyle, .normal)
    }

    func test_set_manual_super_style_persists() {
        store.manualSuperStyle = .relaxed
        XCTAssertEqual(store.manualSuperStyle, .relaxed)
    }

    func test_super_style_mode_round_trip() {
        store.superStyleMode = .manual
        store.manualSuperStyle = .formal
        // Создаём новый store с тем же defaults
        let store2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(store2.superStyleMode, .manual)
        XCTAssertEqual(store2.manualSuperStyle, .formal)
    }

    func test_reset_clears_super_style() {
        store.superStyleMode = .manual
        store.manualSuperStyle = .formal
        store.resetToDefaults()
        XCTAssertEqual(store.superStyleMode, .auto)
        XCTAssertEqual(store.manualSuperStyle, .normal)
    }
}
```

- [ ] **Step 2: Запустить — убедиться что падают**

Expected: FAIL — `superStyleMode` и `manualSuperStyle` не найдены

- [ ] **Step 3: Реализовать**

Добавить в `SettingsStore.swift`:

В enum `Keys` (после строки `static let llmHealthcheckTimeout`):
```swift
static let superStyleMode = "superStyleMode"
static let manualSuperStyle = "manualSuperStyle"
```

В `defaults.register(defaults:)` блок:
```swift
Keys.superStyleMode: "auto",
Keys.manualSuperStyle: SuperTextStyle.normal.rawValue,
```

Новый enum для режима выбора (перед классом `SettingsStore` или в отдельном расширении):
```swift
enum SuperStyleSelectionMode: String {
    case auto
    case manual
}
```

Новые properties (после `llmHealthcheckTimeout`):
```swift
var superStyleMode: SuperStyleSelectionMode {
    get {
        guard let raw = defaults.string(forKey: Keys.superStyleMode) else { return .auto }
        return SuperStyleSelectionMode(rawValue: raw) ?? .auto
    }
    set {
        defaults.set(newValue.rawValue, forKey: Keys.superStyleMode)
        objectWillChange.send()
    }
}

var manualSuperStyle: SuperTextStyle {
    get {
        guard let raw = defaults.string(forKey: Keys.manualSuperStyle) else { return .normal }
        return SuperTextStyle(rawValue: raw) ?? .normal
    }
    set {
        defaults.set(newValue.rawValue, forKey: Keys.manualSuperStyle)
        objectWillChange.send()
    }
}
```

В `resetToDefaults()` добавить:
```swift
defaults.removeObject(forKey: Keys.superStyleMode)
defaults.removeObject(forKey: Keys.manualSuperStyle)
```

- [ ] **Step 4: Запустить тесты — убедиться что проходят**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperStyleSettingsTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Коммит**

```bash
git add Govorun/Storage/SettingsStore.swift GovorunTests/SuperStyleSettingsTests.swift
git commit -m "feat: добавить superStyleMode и manualSuperStyle в SettingsStore"
```

---

### Task 6: Style-aware NormalizationGate

**Files:**
- Modify: `Govorun/Core/NormalizationGate.swift`
- Create: `GovorunTests/NormalizationGateStyleTests.swift`

- [ ] **Step 1: Написать тесты**

```swift
// GovorunTests/NormalizationGateStyleTests.swift
import XCTest
@testable import Govorun

final class NormalizationGateStyleTests: XCTestCase {

    // MARK: - Protected tokens: бренды

    func test_relaxed_accepts_cyrillic_brand() {
        // input от deterministic layer содержит "Slack"
        // LLM в relaxed переписал в "слак" — gate должен принять
        let result = NormalizationGate.evaluate(
            input: "скинь в Slack",
            output: "скинь в слак",
            contract: .normalization,
            superStyle: .relaxed
        )
        XCTAssertTrue(result.accepted, "relaxed должен принимать кириллицу брендов: \(result.failureReason?.description ?? "")")
    }

    func test_normal_rejects_cyrillic_brand() {
        // normal не должен принимать "слак" вместо "Slack"
        let result = NormalizationGate.evaluate(
            input: "скинь в Slack",
            output: "скинь в слак",
            contract: .normalization,
            superStyle: .normal
        )
        XCTAssertFalse(result.accepted, "normal не должен принимать кириллицу брендов")
    }

    func test_relaxed_accepts_cyrillic_tech_term() {
        let result = NormalizationGate.evaluate(
            input: "отправь PDF",
            output: "отправь пдф",
            contract: .normalization,
            superStyle: .relaxed
        )
        XCTAssertTrue(result.accepted, "relaxed должен принимать пдф вместо PDF")
    }

    // MARK: - Protected tokens: без стиля (classic path)

    func test_nil_style_preserves_existing_behavior() {
        // без superStyle gate работает как раньше — "слак" rejected
        let result = NormalizationGate.evaluate(
            input: "скинь в Slack",
            output: "скинь в слак",
            contract: .normalization,
            superStyle: nil
        )
        XCTAssertFalse(result.accepted, "без стиля gate должен отклонить замену Slack→слак")
    }

    // MARK: - Edit distance: стилистические трансформации

    func test_relaxed_lowercase_does_not_inflate_edit_distance() {
        let result = NormalizationGate.evaluate(
            input: "Привет, скинь в Slack",
            output: "привет, скинь в слак",
            contract: .normalization,
            superStyle: .relaxed
        )
        XCTAssertTrue(result.accepted, "relaxed: lowercase + кириллица не должны считаться excessive edits")
    }

    // MARK: - Formal: slang expansion

    func test_formal_accepts_slang_expansion() {
        let result = NormalizationGate.evaluate(
            input: "спс за отчёт",
            output: "Спасибо за отчёт.",
            contract: .normalization,
            superStyle: .formal
        )
        XCTAssertTrue(result.accepted, "formal должен принимать раскрытие сленга спс→спасибо")
    }

    func test_formal_accepts_norm_expansion() {
        let result = NormalizationGate.evaluate(
            input: "всё норм",
            output: "Всё нормально.",
            contract: .normalization,
            superStyle: .formal
        )
        XCTAssertTrue(result.accepted, "formal должен принимать раскрытие норм→нормально")
    }

    func test_normal_rejects_slang_expansion() {
        // normal не раскрывает сленг — gate должен отклонить
        let result = NormalizationGate.evaluate(
            input: "спс за отчёт",
            output: "Спасибо за отчёт",
            contract: .normalization,
            superStyle: .normal
        )
        XCTAssertFalse(result.accepted, "normal не должен принимать раскрытие сленга")
    }
}
```

- [ ] **Step 2: Запустить — убедиться что падают**

Expected: FAIL — `evaluate` не принимает `superStyle` parameter

- [ ] **Step 3: Реализовать style-aware gate**

В `NormalizationGate.swift`:

1. Добавить маппинг брендов (в начале файла или в extension):

```swift
extension NormalizationGate {
    static let brandAliases: [(canonical: String, relaxed: String)] = [
        ("Slack", "слак"), ("Zoom", "зум"), ("Telegram", "телега"),
        ("Jira", "жира"), ("Notion", "ношен"), ("GitHub", "гитхаб"),
        ("YouTube", "ютуб"), ("Google", "гугл"), ("WhatsApp", "вотсап"),
        ("Discord", "дискорд"), ("Figma", "фигма"), ("Docker", "докер"),
        ("Chrome", "хром"), ("Safari", "сафари"), ("Teams", "тимс"),
        ("Trello", "трелло"), ("Confluence", "конфлюенс"), ("Excel", "эксель"),
        ("Word", "ворд"), ("Photoshop", "фотошоп"), ("iPhone", "айфон"),
        ("MacBook", "макбук"), ("Windows", "винда"), ("Linux", "линукс"),
        ("Python", "питон"),
        ("PDF", "пдф"), ("API", "апи"), ("URL", "урл"), ("PR", "пр"),
    ]

    /// Сленг, который formal стиль раскрывает. Gate должен принимать обе формы.
    static let formalSlangExpansions: [(slang: String, expanded: String)] = [
        ("спс", "спасибо"), ("норм", "нормально"), ("плиз", "пожалуйста"),
        ("ок", "хорошо"), ("имхо", "по моему мнению"),
    ]
}
```

2. Обновить сигнатуру `evaluate()` — добавить `superStyle: SuperTextStyle? = nil`:

```swift
static func evaluate(
    input: String,
    output: String,
    contract: LLMOutputContract,
    ignoredOutputLiterals: Set<String> = [],
    superStyle: SuperTextStyle? = nil
) -> NormalizationGateResult
```

3. В `evaluateNormalization()` — передать стиль, в `missingProtectedTokens()` учитывать алиасы:

При проверке protected tokens, если `superStyle == .relaxed`, добавить relaxed-алиасы в `actualCanonical` set. Конкретно: в `missingProtectedTokens()` — если token из expected не найден в output, проверить, есть ли его relaxed-алиас в output.

4. Перед подсчётом edit distance — нормализовать оба текста к style-neutral form:
   - Если `superStyle == .relaxed`: привести к lowercase, заменить кириллицу брендов на canonical.
   - Если `superStyle == .formal`: в input заменить сленг на expanded-форму (спс→спасибо) перед подсчётом distance. Таким образом замена сленга не считается "правкой".
   - Общее: стилистические трансформации (caps, бренды, сленг) приводятся к canonical перед distance calc.

- [ ] **Step 4: Запустить тесты — убедиться что проходят**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/NormalizationGateStyleTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Запустить ВСЕ существующие gate тесты — регрессии нет**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/NormalizationGateTests 2>&1 | tail -5`
Expected: PASS (дефолт `superStyle: nil` сохраняет поведение)

- [ ] **Step 6: Коммит**

```bash
git add Govorun/Core/NormalizationGate.swift GovorunTests/NormalizationGateStyleTests.swift
git commit -m "feat: style-aware NormalizationGate (relaxed принимает кириллицу брендов)"
```

---

### Task 7: Style-aware postflight

**Files:**
- Modify: `Govorun/Core/NormalizationPipeline.swift`
- Modify: `GovorunTests/NormalizationPipelineTests.swift`

- [ ] **Step 1: Написать тесты**

Добавить в `NormalizationPipelineTests.swift` (или создать отдельный файл):

```swift
// MARK: - Super style postflight

func test_postflight_relaxed_strips_period_regardless_of_setting() {
    let result = NormalizationPipeline.postflight(
        deterministicText: "привет",
        llmOutput: "привет",
        textMode: .universal,
        terminalPeriodEnabled: true,
        superStyle: .relaxed
    )
    XCTAssertEqual(result.finalText, "привет")
    XCTAssertFalse(result.finalText.hasSuffix("."))
}

func test_postflight_formal_adds_period_regardless_of_setting() {
    let result = NormalizationPipeline.postflight(
        deterministicText: "Привет",
        llmOutput: "Привет",
        textMode: .universal,
        terminalPeriodEnabled: false,
        superStyle: .formal
    )
    XCTAssertTrue(result.finalText.hasSuffix("."))
}

func test_postflight_normal_no_period() {
    let result = NormalizationPipeline.postflight(
        deterministicText: "Привет",
        llmOutput: "Привет",
        textMode: .universal,
        terminalPeriodEnabled: true,
        superStyle: .normal
    )
    XCTAssertFalse(result.finalText.hasSuffix("."))
}

func test_postflight_nil_style_uses_terminal_period_setting() {
    let withPeriod = NormalizationPipeline.postflight(
        deterministicText: "Привет",
        llmOutput: "Привет",
        textMode: .universal,
        terminalPeriodEnabled: true,
        superStyle: nil
    )
    XCTAssertTrue(withPeriod.finalText.hasSuffix("."))

    let noPeriod = NormalizationPipeline.postflight(
        deterministicText: "Привет",
        llmOutput: "Привет",
        textMode: .universal,
        terminalPeriodEnabled: false,
        superStyle: nil
    )
    XCTAssertFalse(noPeriod.finalText.hasSuffix("."))
}
```

- [ ] **Step 2: Запустить — убедиться что падают**

Expected: FAIL — `postflight` не принимает `superStyle`

- [ ] **Step 3: Реализовать**

В `NormalizationPipeline.postflight()`:

1. Добавить параметр `superStyle: SuperTextStyle? = nil`
2. Передать `superStyle` в `NormalizationGate.evaluate()`
3. Изменить логику terminal period:

```swift
let finalText: String
if let style = superStyle {
    // В Super mode стиль владеет точкой
    finalText = style.terminalPeriod
        ? DeterministicNormalizer.ensureTrailingPeriod(gateResult.output)
        : DeterministicNormalizer.stripTrailingPeriods(gateResult.output)
} else {
    // Classic mode — пользовательская настройка
    finalText = terminalPeriodEnabled
        ? gateResult.output
        : DeterministicNormalizer.stripTrailingPeriods(gateResult.output)
}
```

Примечание: если `ensureTrailingPeriod` не существует — реализовать тривиально: если строка не заканчивается на `.!?`, добавить `.`.

- [ ] **Step 4: Запустить тесты — убедиться что проходят**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/NormalizationPipelineTests 2>&1 | tail -5`
Expected: PASS (новые и существующие)

- [ ] **Step 5: Коммит**

```bash
git add Govorun/Core/NormalizationPipeline.swift GovorunTests/NormalizationPipelineTests.swift
git commit -m "feat: style-aware postflight (стиль владеет точкой в Super mode)"
```

---

### Task 8: Интеграция в PipelineEngine

**Files:**
- Modify: `Govorun/Core/PipelineEngine.swift`
- Modify: `Govorun/App/AppState.swift`

- [ ] **Step 1: Добавить superStyle в PipelineEngine**

В `PipelineEngine` добавить новое поле рядом с `_textMode` (строка ~245):

```swift
private var _superStyle: SuperTextStyle? = nil
```

И thread-safe property:

```swift
var superStyle: SuperTextStyle? {
    get { lock.lock(); defer { lock.unlock() }; return _superStyle }
    set { lock.lock(); defer { lock.unlock() }; _superStyle = newValue }
}
```

- [ ] **Step 2: Обновить snapshotConfig**

Расширить возвращаемый тупл `snapshotConfig()` — добавить `SuperTextStyle?`:

```swift
private func snapshotConfig() -> (ProductMode, TextMode, NormalizationHints, LLMClient, SuperTextStyle?) {
    lock.lock()
    defer { lock.unlock() }
    return (_productMode, _textMode, _hints, _llmClient, _superStyle)
}
```

- [ ] **Step 3: Основной LLM path (строки ~572-646)**

При snapshot: `let (currentProductMode, currentTextMode, currentHints, currentLLMClient, currentSuperStyle) = snapshotConfig()`

В блоке LLM нормализации (строка ~582) — выбор метода:

```swift
if let superStyle = currentSuperStyle {
    llmOutput = try await currentLLMClient.normalize(
        deterministicText, superStyle: superStyle, hints: currentHints
    )
} else {
    llmOutput = try await currentLLMClient.normalize(
        deterministicText, mode: currentTextMode, hints: currentHints
    )
}
```

В postflight (строка ~619) — передать стиль:

```swift
let postflight = NormalizationPipeline.postflight(
    deterministicText: deterministicText,
    llmOutput: llmOutput,
    textMode: currentTextMode,
    terminalPeriodEnabled: terminalPeriodEnabled,
    superStyle: currentSuperStyle
)
```

- [ ] **Step 3.1: Trivial path (строка ~555) — стиль владеет точкой**

Сейчас trivial path возвращает `deterministicText` напрямую. В Super mode с relaxed стилем deterministic text будет с заглавной буквой — стиль не применится.

Решение: если `currentSuperStyle != nil`, применить **детерминированные** стилевые трансформации к deterministicText. Это не только точка — relaxed lowercase критически важен для коротких фраз в мессенджерах ("привет", "ок", "да"), которые массово попадают в trivial path через `isTrivial()` (одно слово без чисел).

Добавить статический метод `SuperTextStyle.applyDeterministic(_:)`:

```swift
// В Govorun/Models/SuperTextStyle.swift
extension SuperTextStyle {
    /// Детерминированные стилевые трансформации для trivial/fallback path (без LLM).
    /// Покрывает: caps, точка. НЕ покрывает: бренды, техтермины, сленг (это задача LLM).
    func applyDeterministic(_ text: String) -> String {
        var result = text
        switch self {
        case .relaxed:
            // Строчная первая буква
            if let first = result.first, first.isUppercase {
                result = first.lowercased() + result.dropFirst()
            }
            // Без точки
            result = DeterministicNormalizer.stripTrailingPeriods(result)
        case .normal:
            // Без точки (заглавная уже стоит от deterministic layer)
            result = DeterministicNormalizer.stripTrailingPeriods(result)
        case .formal:
            // С точкой (заглавная уже стоит от deterministic layer)
            result = DeterministicNormalizer.ensureTrailingPeriod(result)
        }
        return result
    }
}
```

Применение в trivial path:

```swift
if !currentProductMode.usesLLM || !pipelinePreflight.shouldInvokeLLM {
    var outputText = deterministicText
    if let superStyle = currentSuperStyle {
        outputText = superStyle.applyDeterministic(outputText)
    }
    let totalMs = Int((CFAbsoluteTimeGetCurrent() - stopTime) * 1_000)
    return PipelineResult(
        ...
        normalizedText: outputText,
        ...
    )
}
```

**Известное ограничение v1:** бренды ("Slack"→"слак"), техтермины ("PDF"→"пдф") и сленг ("спс"→"спасибо") в trivial path НЕ применяются — для этого нужен LLM. `applyDeterministic()` покрывает только caps и точку.

Текущий `isTrivial()` пропускает одно слово без чисел и самокоррекции. Но условие входа в этот path шире: `!currentProductMode.usesLLM || !shouldInvokeLLM`. Если в будущем `isTrivial()` расширится (или появятся другие причины для `shouldInvokeLLM == false`), gap увеличится. Также LLM failure graceful degradation (строка ~595) тоже возвращает deterministicText без стилевых трансформаций кроме caps/точки.

Это осознанный компромисс v1: полная стилизация требует LLM, deterministic fallback делает минимум. Если gap окажется продуктово заметным — рассмотреть deterministic brand/slang replacements в `applyDeterministic()` как follow-up.

Тесты для `applyDeterministic` добавить в `SuperTextStyleTests.swift`:

```swift
// MARK: - Deterministic transforms

func test_relaxed_deterministic_lowercases_first_char() {
    XCTAssertEqual(SuperTextStyle.relaxed.applyDeterministic("Привет"), "привет")
}

func test_relaxed_deterministic_strips_period() {
    XCTAssertEqual(SuperTextStyle.relaxed.applyDeterministic("Привет."), "привет")
}

func test_normal_deterministic_strips_period() {
    XCTAssertEqual(SuperTextStyle.normal.applyDeterministic("Привет."), "Привет")
}

func test_formal_deterministic_adds_period() {
    XCTAssertEqual(SuperTextStyle.formal.applyDeterministic("Привет"), "Привет.")
}

func test_formal_deterministic_keeps_existing_period() {
    XCTAssertEqual(SuperTextStyle.formal.applyDeterministic("Привет."), "Привет.")
}
```

- [ ] **Step 3.2: Embedded snippet path (строки ~419-551) — стиль в LLM вызове и gate**

В embedded snippet path (строка ~469) — LLM вызов с superStyle:

```swift
if let superStyle = currentSuperStyle {
    let llmOutput = try await currentLLMClient.normalize(
        deterministicText, superStyle: superStyle, hints: hintsWithSnippet
    )
} else {
    let llmOutput = try await currentLLMClient.normalize(
        deterministicText, mode: currentTextMode, hints: hintsWithSnippet
    )
}
```

В gate evaluation (строка ~478) — передать стиль:

```swift
let gateResult = NormalizationGate.evaluate(
    input: deterministicText,
    output: llmOutput,
    contract: currentTextMode.llmOutputContract,
    ignoredOutputLiterals: Set([SnippetPlaceholder.token]),
    superStyle: currentSuperStyle
)
```

В embedded snippet fallback без LLM (строка ~420-445) — применить стилевую точку:

```swift
if !currentProductMode.usesLLM {
    let finalText = SnippetReinserter.mechanicalFallback(...)
    let outputText: String
    if let superStyle = currentSuperStyle {
        outputText = superStyle.terminalPeriod
            ? finalText
            : DeterministicNormalizer.stripTrailingPeriods(finalText)
    } else {
        outputText = terminalPeriodEnabled
            ? finalText
            : DeterministicNormalizer.stripTrailingPeriods(finalText)
    }
    ...
}
```

- [ ] **Step 3.3: LLM failure graceful degradation (строка ~595-616)**

Когда LLM падает, pipeline возвращает deterministicText через `failedPostflight`. Стилевая точка должна применяться и здесь:

```swift
let failedPostflight = NormalizationPipeline.failedPostflight(
    deterministicText: deterministicText,
    failureContext: String(describing: error),
    superStyle: currentSuperStyle
)
```

Обновить `failedPostflight()` — добавить опциональный `superStyle` и применить terminalPeriod логику.

- [ ] **Step 4: Обновить AppState — три точки привязки**

**Инвариант:** `pipelineEngine.superStyle != nil` ТОЛЬКО когда `pipelineEngine.productMode.usesLLM == true`. Во всех остальных случаях — `nil`. Три места в AppState, где это нужно гарантировать:

**4a. `handleActivated()` — установка стиля при начале записи:**

```swift
// В handleActivated(), ПОСЛЕ того как pipelineEngine.productMode уже выставлен
// (он выставляется через handleSuperAssetsChanged → pipelineEngine.productMode = ...)
let appContext = appContextEngine.detectCurrentApp()
pipelineEngine.textMode = appContext.textMode

// superStyle привязан к EFFECTIVE product mode pipeline, не к settings
if pipelineEngine.productMode.usesLLM {
    let styleMode: SuperStyleMode
    if settings.superStyleMode == .manual {
        styleMode = .manual(settings.manualSuperStyle)
    } else {
        styleMode = .auto
    }
    let styleEngine = SuperStyleEngine(mode: styleMode)
    pipelineEngine.superStyle = styleEngine.style(for: appContext.bundleId)
} else {
    pipelineEngine.superStyle = nil
}
```

**4b. `handleSuperAssetsChanged()` — сброс при потере assets:**

В существующем блоке `handleSuperAssetsChanged()`, где `pipelineEngine.productMode` откатывается в `.standard` (строка ~368-375), добавить сброс:

```swift
// Существующий код (строка ~375):
pipelineEngine.productMode = .standard
// ДОБАВИТЬ сразу после:
pipelineEngine.superStyle = nil
```

**4c. `handleSuperAssetsChanged()` — восстановление при появлении assets:**

В блоке где assets ok и `pipelineEngine.productMode` восстанавливается (строка ~395), НЕ выставлять superStyle — он будет выставлен при следующем `handleActivated()`. Это гарантирует что superStyle всегда свежий (с актуальным bundleId).

**Тест-кейс для верификации:**

```swift
func test_super_style_nil_when_assets_missing() {
    // settings.productMode = .superMode, но assets отсутствуют
    // → handleSuperAssetsChanged() откатывает pipeline в .standard
    // → superStyle должен быть nil
    settings.productMode = .superMode
    appState.handleSuperAssetsChanged(state: .modelMissing)
    XCTAssertNil(pipelineEngine.superStyle)
}

func test_super_style_set_only_when_pipeline_is_super() {
    // settings.productMode = .superMode, assets installed
    // → pipeline в .superMode, superStyle выставляется
    settings.productMode = .superMode
    appState.handleSuperAssetsChanged(state: .installed)
    appState.handleActivated()
    XCTAssertNotNil(pipelineEngine.superStyle)
}
```

- [ ] **Step 5: Запустить все тесты**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 6: Коммит**

```bash
git add Govorun/Core/PipelineEngine.swift Govorun/App/AppState.swift
git commit -m "feat: интегрировать SuperTextStyle в PipelineEngine и AppState"
```

---

### Task 9: Menubar UI — вкладка Говорун Супер

**Files:**
- Create: `Govorun/Views/SuperStyleMenuSection.swift`
- Create: `Govorun/Views/SuperModelRequiredAlert.swift`
- Modify: `Govorun/App/StatusBarController.swift`

- [ ] **Step 1: Создать SuperModelRequiredAlert**

```swift
// Govorun/Views/SuperModelRequiredAlert.swift
import SwiftUI

struct SuperModelRequiredAlert: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Говорун Супер")
                .font(.headline)
            Text("Для работы Супер-режима нужна ИИ-модель. Скачайте её в настройках приложения.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Понял") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 320)
    }
}
```

- [ ] **Step 2: Создать SuperStyleMenuSection**

```swift
// Govorun/Views/SuperStyleMenuSection.swift
import SwiftUI

struct SuperStyleMenuSection: View {
    @ObservedObject var settings: SettingsStore
    let superAssetsState: SuperAssetsState
    let currentBundleId: String?
    let currentAppName: String?

    @State private var showModelAlert = false

    var body: some View {
        if superAssetsState == .installed {
            installedView
        } else {
            disabledView
        }
    }

    private var installedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Стиль текста")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Сегмент: Авто | Ручной
            Picker("", selection: Binding(
                get: { settings.superStyleMode },
                set: { settings.superStyleMode = $0 }
            )) {
                Text("Авто").tag(SuperStyleSelectionMode.auto)
                Text("Ручной").tag(SuperStyleSelectionMode.manual)
            }
            .pickerStyle(.segmented)

            if settings.superStyleMode == .auto {
                autoModeLabel
            } else {
                manualModePicker
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var autoModeLabel: some View {
        HStack {
            let engine = SuperStyleEngine(mode: .auto)
            let style = engine.style(for: currentBundleId)
            Text(style.displayName)
                .foregroundStyle(.secondary)
            if let app = currentAppName {
                Text("· \(app)")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
    }

    private var manualModePicker: some View {
        VStack(spacing: 4) {
            ForEach(SuperTextStyle.allCases, id: \.self) { style in
                Button {
                    settings.manualSuperStyle = style
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(style.displayName)
                                .font(.caption)
                            Text(style.shortDescription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.manualSuperStyle == style {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.purple)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var disabledView: some View {
        Button {
            showModelAlert = true
        } label: {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text("Говорун Супер")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showModelAlert) {
            SuperModelRequiredAlert {
                showModelAlert = false
            }
        }
    }
}
```

- [ ] **Step 3: Вставить секцию в StatusBarController через NSHostingView bridge**

`StatusBarController` строит меню на чистом `NSMenu` + `NSMenuItem`. SwiftUI view нужно встроить через `NSHostingView` в кастомный `NSMenuItem.view`.

В `StatusBarController.swift`:

1. Добавить property для хранения hosting view (нужен для обновления state):

```swift
private var styleHostingView: NSHostingView<SuperStyleMenuSection>?
```

2. В методе построения меню (после status item, перед Settings), создать menu item с SwiftUI view:

```swift
private func makeSuperStyleMenuItem() -> NSMenuItem {
    let item = NSMenuItem()

    let rootView = SuperStyleMenuSection(
        settings: appState.settings,
        superAssetsState: appState.superAssetsState,
        currentBundleId: nil,
        currentAppName: nil
    )
    let hosting = NSHostingView(rootView: rootView)

    // NSHostingView в NSMenuItem нуждается в фиксированной ширине, высота — intrinsic
    hosting.translatesAutoresizingMaskIntoConstraints = false
    let container = NSView()
    container.addSubview(hosting)
    NSLayoutConstraint.activate([
        hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        hosting.topAnchor.constraint(equalTo: container.topAnchor),
        hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        hosting.widthAnchor.constraint(equalToConstant: 250),
    ])
    container.frame = hosting.fittingSize.applying(.identity) != .zero
        ? NSRect(origin: .zero, size: hosting.fittingSize)
        : NSRect(x: 0, y: 0, width: 250, height: 120)

    item.view = container
    self.styleHostingView = hosting
    return item
}
```

3. Вставить в меню при построении:

```swift
let superStyleItem = makeSuperStyleMenuItem()
menu.insertItem(NSMenuItem.separator(), at: insertIndex)
menu.insertItem(superStyleItem, at: insertIndex + 1)
```

4. Обновлять state при открытии меню. В `menuWillOpen(_:)` (или при вызове `updateStatusDisplay()`):

```swift
func updateSuperStyleView() {
    guard let hosting = styleHostingView else { return }
    hosting.rootView = SuperStyleMenuSection(
        settings: appState.settings,
        superAssetsState: appState.superAssetsState,
        currentBundleId: appState.appContextEngine.detectCurrentApp().bundleId,
        currentAppName: appState.appContextEngine.detectCurrentApp().appName
    )
}
```

Примечание: `SuperModelRequiredAlert` использует `.sheet()` — в контексте NSMenu sheet не работает. Заменить на `NSAlert` или отдельный `NSPanel`:

```swift
// В disabledView вместо .sheet — вызов через NotificationCenter или callback
private var disabledView: some View {
    Button {
        onShowModelAlert()
    } label: {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text("Говорун Супер")
                .foregroundStyle(.secondary)
        }
    }
    .buttonStyle(.plain)
}
```

И в StatusBarController показать NSAlert:

```swift
private func showModelRequiredAlert() {
    let alert = NSAlert()
    alert.messageText = "Говорун Супер"
    alert.informativeText = "Для работы Супер-режима нужна ИИ-модель. Скачайте её в настройках приложения."
    alert.addButton(withTitle: "Понял")
    alert.alertStyle = .informational
    alert.runModal()
}
```

- [ ] **Step 4: Запустить билд**

Run: `xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Коммит**

```bash
git add Govorun/Views/SuperStyleMenuSection.swift Govorun/Views/SuperModelRequiredAlert.swift Govorun/App/StatusBarController.swift
git commit -m "feat: добавить UI стилей Super в menubar (авто/ручной + модель не скачана)"
```

---

### Task 10: Аналитика

**Files:**
- Modify: файл аналитики (найти по grep `emit.*analytics\|AnalyticsEvent\|logEvent`)

- [ ] **Step 1: Найти где эмитятся события pipeline**

Run: `grep -rn "analytics\|AnalyticsEvent\|logEvent\|emit" Govorun/Core/PipelineEngine.swift Govorun/App/AppState.swift | head -20`

- [ ] **Step 2: Добавить новые поля**

В событие завершения pipeline добавить:
- `style_selection_mode`: `settings.superStyleMode.rawValue` (auto/manual)
- `effective_style`: `superStyle?.rawValue ?? "none"` (relaxed/normal/formal/none)
- `detected_app_bundle`: `appContext.bundleId`

`product_mode` уже должен быть в аналитике.

- [ ] **Step 3: Коммит**

```bash
git add <modified analytics files>
git commit -m "feat: добавить style_selection_mode и effective_style в аналитику"
```

---

### Task 11: Полный прогон тестов + ручное тестирование

**Files:** нет новых

- [ ] **Step 1: Запустить все Swift тесты**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 2: Запустить Python тесты**

Run: `cd ~/Desktop/govorun-app/worker && python3 -m pytest test_server.py -v 2>&1 | tail -10`
Expected: ALL PASS

- [ ] **Step 3: Собрать DMG и протестировать вручную**

Run: `cd ~/Desktop/govorun-app && bash scripts/build-unsigned-dmg.sh 2>&1 | grep '(готов)'`

Проверить:
1. Menubar → Говорун Супер: сегмент Авто/Ручной
2. Авто: подпись стиля + приложение
3. Ручной: три карточки, чекмарк работает
4. Без модели: серый пункт → окно → кнопка "Понял"

- [ ] **Step 4: Коммит финальный (если были фиксы)**

```bash
git add -A
git commit -m "fix: правки после ручного тестирования стилей Super"
```
