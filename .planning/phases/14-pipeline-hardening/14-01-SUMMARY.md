---
# [skip-review: per-plan SUMMARY is a reporting artifact; Codex review happens at end-of-phase cumulative diff (plan 14-04), not per-plan]
phase: 14-pipeline-hardening
plan: 01
subsystem: pipeline
tags: [snippet, reinserter, cloud, pipeline, tdd]
requirements: [CLOUD-05]
dependency_graph:
  requires: []
  provides:
    - "SnippetReinserter.cleanSubstitute(text:trigger:content:)"
  affects:
    - "Govorun/Core/PipelineEngine.swift (SnippetReinserter enum)"
tech_stack:
  added: []
  patterns:
    - "reuse существующего private triggerRange через same-enum scope"
    - "direct String.replacingCharacters(in:with:) без prefix/capitalization"
key_files:
  created:
    - path: "(добавлено в существующий GovorunTests/SnippetReinserterTests.swift)"
      purpose: "unit-тесты cleanSubstitute + regression mechanicalFallback"
  modified:
    - path: "Govorun/Core/PipelineEngine.swift"
      change: "+18 строк: static func cleanSubstitute в enum SnippetReinserter"
    - path: "GovorunTests/SnippetReinserterTests.swift"
      change: "+96 строк: 7 cleanSubstitute тестов + 2 regression mechanicalFallback"
decisions:
  - "Новый helper живёт в enum SnippetReinserter — triggerRange остаётся private (same-enum scope доступен без видимости через internal)"
  - "empty text guard перед triggerRange — защищает от NSRange на пустой строке и возвращает nil явно"
  - "Тесты добавлены в существующий SnippetReinserterTests.swift вместо создания нового файла (файл уже существовал с тестами reinsert/mechanicalFallback)"
metrics:
  duration: "3m 14s"
  completed: "2026-04-19T20:08:35Z"
  tests_added: 9
  tests_passing: 64  # 27 SnippetReinserterTests + 37 PipelineEngineTests
---

# Phase 14 Plan 01: SnippetReinserter.cleanSubstitute Summary

**One-liner:** Добавлен `SnippetReinserter.cleanSubstitute` — чистая подстановка trigger→content без `trigger:` префикса для cloud path fallback через TDD RED→GREEN цикл.

## Objective Met

Cloud path (D-04) теперь имеет собственный embedded-snippet fallback, который отличается от `mechanicalFallback` отсутствием визуального префикса `trigger:`. LLM в cloud режиме должен сам делать substitution грамматически; если не сделал — `cleanSubstitute` вставляет content чисто, без диагностического маркера. Standard режим не затронут: `mechanicalFallback` остался нетронутым.

## Implementation

### `SnippetReinserter.cleanSubstitute(text:trigger:content:) -> String?`

```swift
static func cleanSubstitute(
    text: String,
    trigger: String,
    content: String
) -> String? {
    guard !text.isEmpty else { return nil }
    guard let range = triggerRange(in: text, trigger: trigger) else {
        return nil
    }
    return text.replacingCharacters(in: range, with: content)
}
```

- Расположение: `Govorun/Core/PipelineEngine.swift`, внутри `enum SnippetReinserter`, между `mechanicalFallback` и `triggerRange`.
- 5 строк логики (не считая guard) — reuse существующего word-boundary matcher `triggerRange`.
- Case/diacritic insensitivity унаследована через `triggerRange` (уже имеет эти опции в NSRegularExpression).

### Отличия от `mechanicalFallback`

| Aspect           | mechanicalFallback                         | cleanSubstitute                  |
| ---------------- | ------------------------------------------ | -------------------------------- |
| Output prefix    | `trigger: content` (диагностический)       | только `content`                 |
| Capitalization   | `result.prefix(1).uppercased()`            | нет (cloud output уже форматнут) |
| No-match result  | `"Capitalized Trigger: content"` fallback  | `nil`                            |
| Whitespace trim  | `.whitespacesAndNewlines` вокруг trigger   | нет (сохраняется исходный)       |

## Tests

### cleanSubstitute (7 unit-тестов)

1. `test_cleanSubstitute_returns_nil_when_trigger_not_found` — без trigger → nil
2. `test_cleanSubstitute_replaces_embedded_trigger_without_prefix` — «лена вот мой адрес» → «лена вот Аминева 9» (assert НЕТ «мой адрес:»)
3. `test_cleanSubstitute_preserves_surrounding_whitespace` — embedded substitution сохраняет контекст
4. `test_cleanSubstitute_handles_punctuation_after_trigger` — trigger перед запятой работает
5. `test_cleanSubstitute_case_insensitive_trigger_lookup` — «Мой Адрес» найден при trigger="мой адрес"
6. `test_cleanSubstitute_does_not_add_trigger_prefix` — явная проверка отсутствия «trigger:» substring
7. `test_cleanSubstitute_empty_text_returns_nil` — guard на empty

### mechanicalFallback regression (2 теста)

1. `test_mechanicalFallback_still_uses_trigger_prefix_regression` — assert contains «мой адрес: Аминева 9»
2. `test_mechanicalFallback_unchanged_for_no_match_regression` — «привет» без trigger → «Мой адрес: Аминева 9» (существующее поведение)

### Итоги выполнения

- **SnippetReinserterTests:** 27 тестов (18 существующих + 9 новых) — все PASS
- **PipelineEngineTests:** 37 тестов — все PASS (regression-нулевой)
- **Общий итог:** 64 теста, 0 failures

## Deviations from Plan

### `[Rule 3 - Blocking]` Файл `SnippetReinserterTests.swift` уже существовал

- **Found during:** Task 1 (RED)
- **Issue:** План предписывал «Создать новый test file GovorunTests/SnippetReinserterTests.swift», но файл уже существовал с 18 тестами для `reinsert` и `mechanicalFallback`.
- **Fix:** Вместо создания нового файла (который привёл бы к дубликату `final class SnippetReinserterTests: XCTestCase` и compile error) новые 9 тестов были добавлены в существующий файл в дополнительных MARK-секциях. Имена тестов уникальны; существующие тесты не затронуты.
- **Files modified:** `GovorunTests/SnippetReinserterTests.swift`
- **Commit:** 4d17e33

### SwiftFormat преобразовал комментарии в doc comments

- **Found during:** Task 2 commit (pre-commit hook failed с SwiftFormat lint)
- **Issue:** Обычные `//` комментарии перед `cleanSubstitute` были переформатированы в `///` (doc comments) хук-линтером.
- **Fix:** Принял формат SwiftFormat (project convention). Smysловое содержание комментариев не изменилось.
- **Files modified:** `Govorun/Core/PipelineEngine.swift`
- **Commit:** ccd5582

## TDD Gate Compliance

| Gate     | Commit  | Status |
| -------- | ------- | ------ |
| RED      | 4d17e33 | test(14-01): failing тесты cleanSubstitute — compile fails с 'has no member' ✓ |
| GREEN    | ccd5582 | feat(14-01): cleanSubstitute реализован — 9 новых тестов PASS ✓ |
| REFACTOR | —       | не потребовался (5 строк, ясный код) |

## Commits

1. `4d17e33` — `test(14-01): добавить failing тесты SnippetReinserter.cleanSubstitute`
2. `ccd5582` — `feat(14-01): добавить SnippetReinserter.cleanSubstitute для cloud path`

## Known Stubs

Нет. `cleanSubstitute` полностью реализован; никаких placeholder-значений или TODO в коде.

## Threat Flags

Нет. Новая функция — чистая substitution в локальной памяти, не создаёт новой network/auth/file-access поверхности.

## Self-Check: PASSED

- `Govorun/Core/PipelineEngine.swift` FOUND (grep "static func cleanSubstitute" → 1 hit)
- `GovorunTests/SnippetReinserterTests.swift` FOUND (grep "func test_cleanSubstitute" → 7 hits)
- Commit 4d17e33 FOUND (git log)
- Commit ccd5582 FOUND (git log)
- mechanicalFallback не изменён: `git diff HEAD~2 HEAD` показывает ТОЛЬКО добавленный блок cleanSubstitute, никаких модификаций существующих методов
- Все тесты PASS: 27 SnippetReinserterTests + 37 PipelineEngineTests = 64 тестов, 0 failures
