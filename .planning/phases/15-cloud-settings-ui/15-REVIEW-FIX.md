---
phase: 15-cloud-settings-ui
review_source: 15-REVIEW.md (2026-04-20T21:35:59Z)
fixed: 2026-04-22T20:06:30+03:00
findings_addressed: 6
findings_accepted_risk: 1
status: fixed
---

# Phase 15: Cloud Settings UI — Review Fix Report

Закрывает findings из 15-REVIEW.md от 2026-04-20. Sanya поручила пофиксить всё, UAT делает после.

## Итог

| ID | Severity | Статус | Commit |
|----|----------|--------|--------|
| H-01 | High | **FIXED** | `9533b5a` |
| M-01 | Medium | **FIXED** | `2e749f5` |
| M-02 | Medium | **FIXED** | `07fe4d0` |
| L-01 | Low | **FIXED** | `a8ce6e2` |
| I-01 | Info | **ACCEPTED-RISK** | — |
| I-02 | Info | **FIXED** | `4b114d2` |
| I-03 | Info | **FIXED** | `1d70657` |

Tests: **1299/1299 PASS** (baseline 1297 + 2 новых TDD-теста для H-01, нулевой regression).

---

## H-01 (High) — Force unwrap URL в CloudLLMClient

**Commit:** `9533b5a fix(15): H-01 — guard против невалидного baseURLString в Cloud клиенте`

CLAUDE.md §Error Handling: «Нет force unwrap (`!`) в production коде». `uploadAudio` и `sendChatCompletion` строили URL через `URL(string:)!` — при невалидном `baseURLString` (unclosed IPv6 bracket, пробел в scheme) процесс падал с `EXC_BAD_INSTRUCTION`.

**Fix:**
```swift
guard let url = URL(string: configuration.baseURLString + "/files") else {
    throw LLMError.networkError("Некорректный Cloud URL: \(configuration.baseURLString)")
}
var request = URLRequest(url: url)
```

Тот же паттерн в обеих точках (строки 162 и 289 после WAV-wrapper фикса).

**TDD:**
- `test_processAudio_throwsNetworkError_whenBaseURLInvalid`
- `test_normalize_throwsNetworkError_whenBaseURLInvalid`

Оба теста используют `baseURLString = "http://[invalid"` — незакрытая IPv6-скобка, `URL(string:)` возвращает nil (empirически проверено в swift-CLI до написания теста, т.к. `"\n"`/пробел/пустота auto-encode'ятся на macOS 14 и nil не возвращают).

RED → GREEN проверены: без guard тесты падают на `parsingFailed` (MockHTTP возвращает пустую Data и парсер ломается), с guard — `.networkError`.

---

## M-01 (Medium) — StatusDot accessibilityLabel

**Commit:** `2e749f5 fix(15): M-01 — accessibilityLabel «Статус подключения» на CloudStatusBlock`

UI-SPEC §Accessibility: StatusDot (HStack с `.accessibilityElement(.combine)`) должен читаться как «Статус подключения: {title}». Без `.accessibilityLabel(...)` VoiceOver комбинировал только дочерние элементы и читал только текст статуса.

**Fix:** добавлен `statusTitle` computed property + `.accessibilityLabel("Статус подключения: \(statusTitle)")` в `CloudStatusBlock.body`.

**Проверка:** compile clean. Runtime UAT-J (VoiceOver) покроет.

---

## M-02 (Medium) — Cloud Picker accessibility

**Commit:** `07fe4d0 fix(15): M-02 — accessibility-метки для Cloud-сегмента Picker`

UI-SPEC §Accessibility для «Cloud segment when disabled-but-clickable»:
- `.accessibilityLabel` = «Cloud — требуется настройка»
- `.accessibilityHint` = «Нажмите, чтобы открыть настройки облачного режима»

`SettingsView.swift` lines 518-524 (внутри ProductModeCard Picker): HStack с `Text(mode.title)` + `Image(lock.fill)` без accessibility-меток — VoiceOver читал «Cloud, lock, пункт меню».

**Fix:** добавлены обе locked-strings на tag(mode) в if-branch.

---

## L-01 (Low) — Copy drift в accessibilityHint

**Commit:** `a8ce6e2 fix(15): L-01 — выровнять accessibilityHint «Отозвать согласие» с UI-SPEC`

UI-SPEC locked copy: «Отключает облачный режим. Ключи останутся сохранены.»
Код содержал: «Отключает облачный режим **со следующей сессии**. Ключи останутся сохранены.»

Добавленная фраза технически корректна (D-07.1 deferred-to-idle), но нарушает §Copywriting Contract: «Strings below are locked — planner must use exactly these». Откатил на спековый вариант.

---

## I-01 (Info) — fatalError в defaultTokenURL — **accepted-risk**

Review сам отмечает: URL — compile-time литерал, fatalError недостижим; если `URL(staticString:)` недоступен на целевом SDK (macOS 14.0+, оно доступно только в macOS 15.0+), текущий вариант с `fatalError` приемлем. Оставил без изменений.

Документирование: static let с `URL(string:)` + `guard let` + `fatalError("Невалидный defaultTokenURL")` — defensive-pattern для compile-time constants. CLAUDE.md строго запрещает `!` в production, но `fatalError` в `static let` init — это failing-loud-not-silent, и в случае опечатки в литерале падение происходит при первом использовании, что easy-to-diagnose.

---

## I-02 (Info) — Избыточный MainActor.run

**Commit:** `4b114d2 refactor(15): I-02 — убрать избыточный MainActor.run внутри Task`

`Task {}` внутри `@MainActor`-изолированного SwiftUI View наследует MainActor-изоляцию (Swift 5.10, SE-0338 + SwiftUI View protocol markup). Build под `SWIFT_STRICT_CONCURRENCY=complete` без новых warnings после удаления — подтверждает корректность.

**Сэкономлено:** 8 строк boilerplate в `saveAndProbe` и `probeOnly`.

---

## I-03 (Info) — DateFormatter в static let

**Commit:** `1d70657 perf(15): I-03 — DateFormatter в static let на CloudConsentBanner`

DateFormatter — тяжёлый объект (locale, calendar parsing), создавался в `postAckContent` при каждом обновлении SwiftUI body. Вынесен в `private static let consentDateFormatter` — создаётся один раз per struct.

---

## Нулевые регрессии

- 1299/1299 XCTest PASS (baseline 1297 + 2 новых TDD H-01)
- SwiftFormat lint clean
- Нет новых strict-concurrency warnings

## Остаётся для закрытия Phase 15

**15-HUMAN-UAT.md (11 шагов A–K)** — Sanya прогоняет с живыми GigaChat credentials из developers.sber.ru. Шаг K (full xcodebuild test) уже fulfilled этим REVIEW-FIX циклом.

---

*Fixer: Claude (Opus 4.7 1M)*
*Cycle: 2026-04-22 19:51 → 20:06 MSK*
