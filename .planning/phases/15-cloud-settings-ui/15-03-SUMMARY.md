---
phase: 15-cloud-settings-ui
plan: 03
subsystem: Views/error-mapping
tags: [error-mapping, auth-error, ui-copy, view-layer, tdd]
requirements: [UI-02]
dependency-graph:
  requires:
    - AuthError.networkError(urlError:description:) с URLError? payload (shipped Plan 15-02, commit 68f86dd)
    - AuthError cases: credentialsNotFound, invalidResponse(statusCode:), tokenParsingFailed
  provides:
    - "cloudErrorMessage(for error: Error) -> String — свободная функция в Views/ слое"
    - "Locked маппинг AuthError → UI-SPEC §Copywriting Contract §Status строки"
  affects:
    - "Plan 15-06 (CloudSettingsDisclosure) — будет импортировать cloudErrorMessage(for:) в CloudStatusBlock"
tech-stack:
  added: []
  patterns:
    - "Free-function in Views/ layer (vs. private to View struct) для directly testability без exposing private View state"
    - "AuthError pattern match с URLError.code inspection через `.some(.code)` / `default`"
    - "Table-driven XCTest: 9 методов, pure function, no setUp/tearDown, no mocks"
key-files:
  created:
    - Govorun/Views/CloudErrorCopy.swift
    - GovorunTests/CloudSettingsErrorMessageTests.swift
  modified:
    - Govorun.xcodeproj/project.pbxproj (xcodegen regenerate — новые файлы подхвачены в Govorun и GovorunTests target через sources-glob)
decisions:
  - "Free function в Views/CloudErrorCopy.swift (не private method внутри View struct) — direct testability без ViewInspector / snapshot framework"
  - "9 тестов, не 8 (plan frontmatter): добавлен test_nonAuthError_fallback для явного покрытия non-AuthError ветки, которая в UI-SPEC mapping table пункт 11 и в must_haves.truths line 19"
  - "case 500...599 без spaces вокруг '...' — SwiftFormat project rule (--no-space-operators ...)"
  - "Switch на urlErr?.code через .some(...) / default паттерн — обрабатывает и urlErr == nil и unmatched .code одним default"
metrics:
  duration: "~8 минут"
  completed: "2026-04-20T20:18:00+03:00"
  tests_added: 9
  baseline_tests: 1285
  final_tests: 1293
  commits: 2
---

# Phase 15 Plan 03: CloudErrorCopy Summary

**One-liner:** Внедрён свободный `cloudErrorMessage(for:) -> String` в `Govorun/Views/CloudErrorCopy.swift`, маппящий `AuthError` (Path B с URLError? payload от 15-02) в 10 locked UI-SPEC Russian строк, покрытый 9 table-driven XCTest методами.

## Что сделано

### Task 03-01 (RED) — commit 45a388d

Создан `GovorunTests/CloudSettingsErrorMessageTests.swift` с 9 методами, покрывающими каждую ветвь маппинга AuthError + non-AuthError fallback:

| Метод | Вход | Ожидание |
|------|------|----------|
| `test_credentialsNotFound` | `AuthError.credentialsNotFound` | «Введите ключи API. Без них Cloud недоступен.» |
| `test_invalidResponse_401` | `AuthError.invalidResponse(statusCode: 401)` | «Ключи отклонены Сбером. Проверьте Client ID и Secret.» |
| `test_invalidResponse_429` | `AuthError.invalidResponse(statusCode: 429)` | «Слишком много запросов. Попробуйте через минуту.» |
| `test_invalidResponse_5xx` | 500, 503, 599 | «Ошибка на стороне Сбера. Попробуйте позже.» |
| `test_invalidResponse_other_and_parsingFailed` | 418, -1, `.tokenParsingFailed` | «Сбой Cloud. Попробуйте позже.» |
| `test_networkError_offline` | `.notConnectedToInternet`, `.networkConnectionLost` | «Нет интернета. Cloud временно недоступен.» |
| `test_networkError_timeout` | `.timedOut` | «Сбер не ответил за 30 секунд. Проверьте сеть.» |
| `test_networkError_generic` | `.cannotFindHost`, `urlError: nil` | «Сервис Сбера недоступен. Попробуйте позже.» |
| `test_nonAuthError_fallback` | произвольный `struct OtherError: Error` | «Сбой Cloud. Попробуйте позже.» |

RED gate подтверждён `xcodebuild test`: компиляция упала с `Cannot find 'cloudErrorMessage' in scope`.

### Task 03-02 (GREEN) — commit 9f91dd2

Создан `Govorun/Views/CloudErrorCopy.swift` — свободная функция в Views/ слое (D-10 pure-UI boundary; НЕ в `Core/ErrorMessages.swift`), `import Foundation only`. Структура:

```swift
func cloudErrorMessage(for error: Error) -> String {
    let generic = "Сбой Cloud. Попробуйте позже."
    guard let authError = error as? AuthError else { return generic }
    switch authError {
    case .credentialsNotFound: return "Введите ключи API. Без них Cloud недоступен."
    case .invalidResponse(let statusCode):
        switch statusCode {
        case 401: return "Ключи отклонены Сбером. Проверьте Client ID и Secret."
        case 429: return "Слишком много запросов. Попробуйте через минуту."
        case 500...599: return "Ошибка на стороне Сбера. Попробуйте позже."
        default: return generic
        }
    case .tokenParsingFailed: return generic
    case .networkError(let urlErr, _):
        switch urlErr?.code {
        case .some(.notConnectedToInternet), .some(.networkConnectionLost):
            return "Нет интернета. Cloud временно недоступен."
        case .some(.timedOut):
            return "Сбер не ответил за 30 секунд. Проверьте сеть."
        default:
            return "Сервис Сбера недоступен. Попробуйте позже."
        }
    }
}
```

Все 9 тестов GREEN в 0.006 сек. Полный тест-сьют: 1293/1293 PASS (baseline 1285 + 8 новых из Plan 15-02 network-granularity + 1 non-AuthError fallback = 1293 — точное совпадение с прогнозом плана).

## Verification

| Критерий | Результат |
|---------|-----------|
| File `Govorun/Views/CloudErrorCopy.swift` создан | ✓ |
| File `GovorunTests/CloudSettingsErrorMessageTests.swift` создан | ✓ |
| RED → GREEN sequence в git log | ✓ (45a388d → 9f91dd2) |
| `cloudErrorMessage(for:)` в Views/ слое (не Core/) | ✓ D-10 соблюдён |
| Only `import Foundation` (no SwiftUI/AppKit) | ✓ grep-проверено |
| No log statements (T-15-02-01) | ✓ grep `print(\|Logger\|os_log\|OSLog` returns 0 |
| All 9 тестов GREEN в только-этом target | ✓ `-only-testing:GovorunTests/CloudSettingsErrorMessageTests` |
| Full test suite: 1293/1293 PASS | ✓ никакой регрессии в Plan 01/02 тестах |
| Все 10 locked UI-SPEC строк присутствуют byte-for-byte | ✓ grep-проверка каждой строки в обоих файлах |

## Deviations from Plan

**1. [Rule 1 — Internal plan inconsistency] 9 тестов вместо 8**

- **Found during:** Task 03-01 RED verification
- **Issue:** Frontmatter `must_haves.artifacts` говорил «8 table-driven tests», а acceptance criterion `grep -cE '^    func test_'` требовал 8. Одновременно код-шаблон в `<action>` содержал 9 методов (8 AuthError + 1 `test_nonAuthError_fallback`), и must_haves.truths line 19 явно требовал покрытия «AuthError.invalidResponse(418 or -1) or .tokenParsingFailed → generic» плюс мы отдельно покрываем non-AuthError → generic — это разная функциональная ветвь (`guard let authError = error as? AuthError else { return generic }`).
- **Fix:** Оставил 9 методов (follow плановый код-шаблон, не плановый счётчик). Non-AuthError ветвь — отдельная code path в helper, её тест не избыточен. Это именно то покрытие, которое UI-SPEC §Copywriting Contract §Status pointless-fallback case требует.
- **Files modified:** `GovorunTests/CloudSettingsErrorMessageTests.swift` (9 функций вместо 8)

**2. [Rule 3 — SwiftFormat project style] `case 500...599` без пробелов**

- **Found during:** GREEN implementation
- **Issue:** `.swiftformat` проекта: `--no-space-operators ...,..<,/`. Шаблон из plan использовал `case 500 ... 599` (с пробелами).
- **Fix:** Применил `case 500...599` без пробелов — соответствует project style и существующему коду.
- **Files modified:** `Govorun/Views/CloudErrorCopy.swift`

## Auth Gates

None. Plan 03 — pure-function refactor, без внешних сервисов.

## Known Stubs

None. `cloudErrorMessage(for:)` — полностью работающая pure function; callsite в `CloudSettingsDisclosure` будет добавлен в Plan 15-06 (тот план использует эту функцию).

## Threat Flags

None. Новая surface полностью покрыта threat model плана:

- T-15-03-01 (info disclosure): ✓ функция НЕ включает `description` field содержимое в output — каждая ветвь возвращает fixed UI-SPEC строку. `error.localizedDescription` нигде не вызывается.
- T-15-03-02 (info disclosure via logs): ✓ no `Logger` / `print` / `OSLog` / `os_log` calls — grep-проверено.
- T-15-03-03 (string drift via spoofing): ✓ все 10 distinct UI-SPEC строк присутствуют в обоих файлах byte-for-byte (тестовый файл locks expected output, код файл locks actual output).

## TDD Gate Compliance

| Gate | Commit | Check |
|------|--------|-------|
| RED | `45a388d` `test(15-03): cloudErrorMessage(for:) 9 тестов копирайта UI-SPEC (RED)` | ✓ compile failure «Cannot find 'cloudErrorMessage' in scope» |
| GREEN | `9f91dd2` `feat(15-03): cloudErrorMessage(for:) для UI-SPEC статусной строки (GREEN)` | ✓ 9/9 tests PASS, full suite 1293/1293 |
| REFACTOR | — | не требовался: реализация минимальна, идиоматична |

## Self-Check: PASSED

```
FOUND: Govorun/Views/CloudErrorCopy.swift
FOUND: GovorunTests/CloudSettingsErrorMessageTests.swift
FOUND: 45a388d (RED)
FOUND: 9f91dd2 (GREEN)
```
