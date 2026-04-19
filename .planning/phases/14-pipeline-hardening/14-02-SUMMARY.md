---
# [skip-review: per-plan SUMMARY is a reporting artifact; Codex review happens at end-of-phase cumulative diff (plan 14-04), not per-plan]
phase: 14-pipeline-hardening
plan: 02
subsystem: pipeline
tags: [super-text-style, cloud, system-prompt, snippet, tdd]
requirements: [CLOUD-05]
dependency_graph:
  requires: []
  provides:
    - "SuperTextStyle.systemPrompt(snippetDictionary:)"
    - "NormalizationHints.snippetDictionary"
  affects:
    - "Govorun/Models/SuperTextStyle.swift (systemPrompt signature + ГОЛОСОВЫЕ СОКРАЩЕНИЯ block)"
    - "Govorun/Models/NormalizationHints.swift (new field + init param)"
    - "Govorun/Services/CloudLLMClient.swift (processAudio wiring)"
tech_stack:
  added: []
  patterns:
    - "optional parameter с default value для zero-regression расширения signature"
    - "conditional block в systemPrompt через guard !isEmpty"
    - "swiftformat:disable:next redundantSelf для strict concurrency в Logger macro"
key_files:
  created: []
  modified:
    - path: "Govorun/Models/NormalizationHints.swift"
      change: "+2 строки: let snippetDictionary + init param (default [:])"
    - path: "Govorun/Models/SuperTextStyle.swift"
      change: "+22 строки: systemPrompt param + ГОЛОСОВЫЕ СОКРАЩЕНИЯ block"
    - path: "Govorun/Services/CloudLLMClient.swift"
      change: "+2 строки: snippetDictionary pass-through в processAudio + swiftformat directive"
    - path: "GovorunTests/SuperTextStyleTests.swift"
      change: "+99 строк: 6 тестов SuperTextStyleSnippetDictionaryPromptTests + 3 теста NormalizationHintsSnippetDictionaryTests"
decisions:
  - "Новый параметр snippetDictionary добавлен В КОНЕЦ списка параметров systemPrompt — сохраняет backward compat на уровне именованных вызовов"
  - "Блок ГОЛОСОВЫЕ СОКРАЩЕНИЯ размещён ПОСЛЕ ПОДСТАНОВКА (snippetContext) — ближе к задаче LLM"
  - "CloudLLMClient.normalize(...) НЕ трогается — он обслуживает Super local LLM fallback, не cloud path"
  - "Класс SuperTextStyleSnippetDictionaryPromptTests (а не SuperTextStyleSnippetPromptTests) — избегаем collision с существующим классом того же имени в SnippetEngineTests.swift"
metrics:
  duration: "~7m"
  completed: "2026-04-19T23:17:21+03:00"
  tests_added: 9
  tests_passing: 1263  # full suite
---

# Phase 14 Plan 02: Snippet-Aware System Prompt Summary

**One-liner:** `SuperTextStyle.systemPrompt` получает optional `snippetDictionary: [String: String]` параметр; при непустом словаре в промпт добавляется блок ГОЛОСОВЫЕ СОКРАЩЕНИЯ с инструкциями для cloud LLM на inline-замену с грамматической перестройкой. `NormalizationHints.snippetDictionary` новое поле, `CloudLLMClient.processAudio` пробрасывает его в systemPrompt. Zero regression для normalize path и всех существующих тестов.

## Objective Met

Cloud path (D-01 Option G) теперь принимает snippet словарь в одном round-trip с аудио. LLM делает substitution inline, перестраивая фразу грамматически — отличие от Super local path, где используется placeholder token. Safety net (SnippetReinserter.cleanSubstitute из 14-01) применится в 14-04 если LLM не сделает substitution. Standard/Super режимы не затронуты — их путь через `normalize(...)` использует snippetContext (placeholder token) без изменений.

## Implementation

### 1. `NormalizationHints.snippetDictionary`

```swift
struct NormalizationHints: Equatable {
    let personalDictionary: [String: String]
    let appName: String?
    let currentDate: Date
    let snippetContext: SnippetContext?
    let snippetDictionary: [String: String]  // NEW — trigger → content для cloud inline substitution

    init(
        personalDictionary: [String: String] = [:],
        appName: String? = nil,
        currentDate: Date = Date(),
        snippetContext: SnippetContext? = nil,
        snippetDictionary: [String: String] = [:]  // NEW
    ) { ... }
}
```

Default value `[:]` обеспечивает backward compat: все существующие 14 callsites `NormalizationHints(...)` (в PipelineEngineTests, LocalLLMClientTests, CloudLLMClientTests, PipelineEngine.swift, AppState.swift) компилируются без изменений.

### 2. `SuperTextStyle.systemPrompt(snippetDictionary:)`

```swift
func systemPrompt(
    currentDate: Date,
    personalDictionary: [String: String] = [:],
    snippetContext: SnippetContext? = nil,
    appName: String? = nil,
    snippetDictionary: [String: String] = [:]  // NEW
) -> String {
    // ... existing blocks ...
    if !snippetDictionary.isEmpty {
        var block = """


        ГОЛОСОВЫЕ СОКРАЩЕНИЯ (inline замена):
        Пользователь может произнести ключевые слова — замени их в выходном тексте на значения, перестраивая фразу грамматически. Сохраняй значение ДОСЛОВНО (не меняй email, номер телефона, имя). Не добавляй оригинальное ключевое слово рядом с замещённым значением.

        Словарь:
        """
        for (trigger, content) in snippetDictionary {
            block += "\n\(trigger) → \(content)"
        }
        block += """


        Примеры применения:
        «скинь на мой имейл» → «Скинь на user@example.com»
        «привет это мой адрес» → «Привет, это Саша Аминева 9»
        «позвони на мой телефон сегодня» → «Позвони на +7 999 123 45 67 сегодня»
        """
        prompt += block
    }
    return prompt
}
```

**Порядок блоков в systemPrompt:**

```
basePrompt → styleBlock → [КОНТЕКСТ ПРИЛОЖЕНИЯ?] → [ПОДСТАНОВКА?] → [ГОЛОСОВЫЕ СОКРАЩЕНИЯ?]  ← NEW
```

Размещение в самом конце — ближе к задаче LLM, меньше риск переопределения стилевым блоком.

### 3. `CloudLLMClient.processAudio` wiring

```swift
let systemPrompt = superStyle.systemPrompt(
    currentDate: hints.currentDate,
    personalDictionary: hints.personalDictionary,
    snippetContext: hints.snippetContext,
    appName: hints.appName,
    snippetDictionary: hints.snippetDictionary   // NEW
)
```

`CloudLLMClient.normalize(...)` (Super local fallback) НЕ трогается — поле `hints.snippetDictionary` там не пробрасывается, т.к. Super использует placeholder token через snippetContext.

## Tests

### `SuperTextStyleSnippetDictionaryPromptTests` (6 тестов)

1. `test_systemPrompt_without_snippets_unchanged_regression` — default call, нет блока
2. `test_systemPrompt_with_empty_snippets_unchanged` — `[:]` → нет блока
3. `test_systemPrompt_with_snippets_includes_block` — блок содержит «мой адрес → Аминева 9» и «Не добавляй оригинальное ключевое слово»
4. `test_systemPrompt_with_multiple_snippets_lists_all` — обе пары в блоке
5. `test_systemPrompt_snippet_dictionary_preserves_style_block` — style=.formal: «АБСОЛЮТНЫЙ ЗАПРЕТ ПЕРЕФРАЗИРОВАНИЯ» И «ГОЛОСОВЫЕ СОКРАЩЕНИЯ» оба присутствуют
6. `test_systemPrompt_snippet_dictionary_ordered_after_snippet_context` — ПОДСТАНОВКА.range.lowerBound < ГОЛОСОВЫЕ СОКРАЩЕНИЯ.range.lowerBound

### `NormalizationHintsSnippetDictionaryTests` (3 теста)

1. `test_normalizationHints_snippet_dictionary_defaults_to_empty` — default init → `[:]`
2. `test_normalizationHints_snippet_dictionary_retains_values` — задание значений сохраняется
3. `test_normalizationHints_equatable_includes_snippet_dictionary` — Equatable включает новое поле

### Итоги выполнения

- **Новые тесты:** 9 PASS (6 SuperTextStyleSnippetDictionaryPromptTests + 3 NormalizationHintsSnippetDictionaryTests)
- **Регрессия:** 1263 теста (full suite) — 0 failures
  - PipelineEngineTests: 37 PASS (NormalizationHints(...) callsites работают через default value)
  - CloudLLMClientTests: 22 PASS (processAudio wiring не ломает existing)
  - LocalLLMClientTests: 10 PASS (нет влияния — Super path не трогался)
  - SuperTextStyleTests: 59 PASS (new class, existing не затронуты)

## Deviations from Plan

### Auto-fixed Issues

**1. `[Rule 3 - Blocking]` Коллизия имени класса теста с существующим в `SnippetEngineTests.swift`**
- **Found during:** Task 1 (RED) первый прогон
- **Issue:** План предписывал создать `final class SuperTextStyleSnippetPromptTests: XCTestCase`, но класс с этим именем уже существует в `GovorunTests/SnippetEngineTests.swift:513` (2 теста для snippetContext placeholder). Swift не позволяет redeclaration.
- **Fix:** Переименовал новый класс в `SuperTextStyleSnippetDictionaryPromptTests` — семантически точнее (подчёркивает `Dictionary` а не `Context` тесты). Существующий класс не затронут.
- **Files modified:** `GovorunTests/SuperTextStyleTests.swift`
- **Commit:** 2c2c231

**2. `[Rule 3 - Blocking]` SwiftFormat + Swift strict concurrency конфликт на `self.configuration`**
- **Found during:** Task 2 (GREEN) pre-commit hook
- **Issue:** SwiftFormat `redundantSelf` rule удаляет `self.` из interpolation `Logger.info("...\(self.configuration.retryDelay, privacy: .public)s")`. Но Swift strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`) требует явный `self.` в escaping closure контексте macro `#Predicate`-подобных Logger autoclosure interpolations.
- **Fix:** Добавил `// swiftformat:disable:next redundantSelf` directive перед строкой с `Logger.info`. Предыдущий код (до 14-02 изменений) уже имел `self.configuration.retryDelay` — оно работало, видимо, только благодаря тому что SwiftFormat не применялся к этой строке ранее (был баг). Теперь fix-рельс.
- **Files modified:** `Govorun/Services/CloudLLMClient.swift`
- **Commit:** f3ee6ae

### Non-auto-fix (принятые как-есть)

**3. SwiftFormat преобразовал `200 ..< 300` → `200..<300` (range operator spacing)**
- **Found during:** Task 2 (GREEN) `swiftformat .` run
- **Issue:** SwiftFormat `--no-space-operators ...,..<,/` config rule удалил пробелы вокруг `..<`. Эти строки в `validateStatus(...)` не были изменены этим планом, но SwiftFormat пересобрал весь файл.
- **Fix:** Принят без отката (project convention — `.swiftformat` config). Смысл не меняется, только whitespace. Не затрагивает функциональность.
- **Files modified:** `Govorun/Services/CloudLLMClient.swift` (лина 272, 277)
- **Commit:** f3ee6ae

## TDD Gate Compliance

| Gate     | Commit  | Status |
| -------- | ------- | ------ |
| RED      | 2c2c231 | test(14-02): 9 failing тестов с ожидаемыми compile errors `extra argument 'snippetDictionary'` и `no member 'snippetDictionary'` ✓ |
| GREEN    | f3ee6ae | feat(14-02): snippetDictionary реализован end-to-end — все 9 новых тестов PASS, 0 регрессий в full suite (1263) ✓ |
| REFACTOR | —       | не потребовался (все изменения минимальные, идиоматичные) |

## Commits

1. `2c2c231` — `test(14-02): failing тесты systemPrompt snippetDictionary и NormalizationHints`
2. `f3ee6ae` — `feat(14-02): snippet-aware system prompt для cloud path`

## Known Stubs

Нет. `snippetDictionary` полностью реализован от NormalizationHints до systemPrompt composition до CloudLLMClient wire-up. Поле `snippetDictionary` в текущий момент получает `[:]` в `PipelineEngine.processCloudPath` — это ожидаемое состояние: plan 14-04 (последний плана в фазе) добавит заполнение из SnippetEngine.entries в `stopRecording → processCloudPath` snapshot. До 14-04 cloud path работает идентично текущему поведению (блок ГОЛОСОВЫЕ СОКРАЩЕНИЯ просто не генерируется).

## Threat Flags

Нет. Изменения не создают новой network/auth/file-access поверхности. Snippet словарь — это user-local данные из SwiftData (SnippetStore), уже хранящиеся локально. Передача в system prompt — такой же trust boundary как personal dictionary (который уже был в basePrompt).

## Self-Check: PASSED

- `Govorun/Models/NormalizationHints.swift` FOUND (grep "snippetDictionary: \[String: String\]" → 2 hits: field + init)
- `Govorun/Models/SuperTextStyle.swift` FOUND (grep "snippetDictionary: \[String: String\]" → 1 hit param; grep "ГОЛОСОВЫЕ СОКРАЩЕНИЯ" → 1 hit)
- `Govorun/Services/CloudLLMClient.swift` FOUND (grep "snippetDictionary: hints.snippetDictionary" → 1 hit в processAudio; normalize НЕ трогается — diff подтверждён)
- `GovorunTests/SuperTextStyleTests.swift` FOUND (grep "class SuperTextStyleSnippetDictionaryPromptTests" → 1 hit; grep "class NormalizationHintsSnippetDictionaryTests" → 1 hit; 6 тестов test_systemPrompt_* + 3 теста test_normalizationHints_*)
- Commit 2c2c231 FOUND (git log)
- Commit f3ee6ae FOUND (git log)
- Все тесты PASS: 1263 в full suite, 0 failures (9 новых + 1254 существующих)
- normalize(...) path НЕ изменён: `git diff HEAD~1 HEAD -- CloudLLMClient.swift` показывает ТОЛЬКО processAudio (lines 113-118) + swiftformat директива + range operator spacing cleanup — ни одной строки в `normalize(...)` (lines 72-103)
