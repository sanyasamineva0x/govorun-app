---
phase: 15-cloud-settings-ui
plan: 06
subsystem: ui
tags: [swiftui, disclosure, picker-revert, consent-banner, focus-state, secure-field, alert]
status: pending-human-verification

requires:
  - phase: 15-cloud-settings-ui/01
    provides: SettingsStore.cloudConsentAcceptedAt accessor + clearCloudConsent()
  - phase: 15-cloud-settings-ui/02
    provides: AuthError.networkError(urlError: URLError?, description: String) + Equatable
  - phase: 15-cloud-settings-ui/03
    provides: cloudErrorMessage(for: Error) -> String (9 locked branches)
  - phase: 15-cloud-settings-ui/04
    provides: AppState.saveCloudCredentials / deleteCloudCredentials / probeCloudConnection + authServiceFactory
  - phase: 15-cloud-settings-ui/05
    provides: StatusDot 3-state (idle/connected/error) additive

provides:
  - "Govorun/Views/CloudSettingsDisclosure.swift — 378 строк disclosure view с 3 subviews, ConnectionState enum, @FocusState"
  - "Govorun/Views/SettingsView.swift ProductModeCard — showCloudSetup state, canActivateCloud computed, 2-arg .onChange revert, lock.fill picker item, disclosure render"
  - "Полная UI-поверхность для UI-01 (credential input), UI-02 (status indicator), UI-03 (picker revert + locked Cloud), UI-04 (privacy consent banner)"

affects: [16-tests, 17-polish-rollout]

tech-stack:
  added: []
  patterns:
    - "SwiftUI .alert(role: .destructive) вместо AppKit NSAlert (HistoryView.swift precedent)"
    - "Picker revert via 2-arg .onChange (oldValue, newValue) + @State setup-flag"
    - "Credential-safe UX: SecureField @State draft никогда не пре-заполняется из Keychain, clientSecretDraft очищается сразу после save"
    - "Consent flow через settings.productMode write → wireSettingsChange observer вызывает private applyProductMode"

key-files:
  created:
    - Govorun/Views/CloudSettingsDisclosure.swift
  modified:
    - Govorun/Views/SettingsView.swift

key-decisions:
  - "Deviation: applyProductMode остался private в AppState — consent accept/revoke пишут settings.productMode и полагаются на wireSettingsChange observer"
  - "Landmine #4 (picker dropdown lock icon opacity): HStack + lock.fill + .foregroundStyle(Color.ink.opacity(0.25)) ship-как-есть; lock-иконка сама по себе сигнал, если .menu dropdown не применит opacity на macOS"
  - "D-05 deviation preserved from Plan-level: SwiftUI .alert() destructive вместо AppKit NSAlert (per PATTERNS.md HistoryView precedent)"
  - "Copy fidelity: все 24 locked UI-SPEC строки match byte-for-byte"

patterns-established:
  - "SwiftUI SecureField + @FocusState: Field enum Hashable + DispatchQueue.main.asyncAfter(0.05) для первоначального фокуса (Landmine #5)"
  - "Consent banner two-state ViewBuilder: preAckContent / postAckContent(acceptedAt:) внутри одного Sage-tinted container"
  - "Picker item heterogeneous rendering: ForEach с условным HStack vs plain Text — SwiftUI принимает любой View в .tag()"

requirements-completed: [UI-01, UI-02, UI-03, UI-04]

duration: 5m 36s
completed: 2026-04-20
---

# Phase 15 Plan 06: CloudSettingsDisclosure Summary

**Полная UI-поверхность Говорун Cloud: disclosure-блок с SecureField ввода GigaChat ключей, 3-state статусной строкой, Sage-tinted consent banner pre/post-ack, и guarded picker с locked Cloud-сегментом — всё на готовой backend-поверхности из Waves 1-2.**

## Performance

- **Duration:** 5m 36s
- **Started:** 2026-04-20T17:26:02Z
- **Completed:** 2026-04-20T17:31:38Z
- **Tasks:** 2 из 3 (Task 06-03 — UAT, делегирован пользователю)
- **Files modified:** 2 (1 new, 1 in-place edit)

## Accomplishments

- **CloudSettingsDisclosure.swift (378 строк)** — top-level disclosure view + 3 private subviews (CloudCredentialsBlock / CloudStatusBlock / CloudConsentBanner) + nested ConnectionState enum + @FocusState focus management. Интегрирован со всеми Wave 1-2 backend-сервисами (AppState shims, cloudErrorMessage, StatusDot 3-state).
- **ProductModeCard в SettingsView.swift (+27 строк)** — Cloud-guard для picker (revert при !canActivateCloud, показ disclosure), lock.fill в locked Cloud сегменте dropdown, disclosure render alongside существующего Super downloadStatusView с 0.22s easeOut анимацией.
- **1297/1297 тестов PASS** — zero regressions относительно baseline после Wave 2 (Plan 04 завершения).
- **Copy fidelity:** все 24 locked UI-SPEC строки (placeholders, buttons, status messages, alert, consent banner pre/post-ack) вставлены byte-for-byte.

## Task Commits

Each task was committed atomically:

1. **Task 06-01: CloudSettingsDisclosure.swift** — `cd31c72` (feat: disclosure view + 3 subviews + ConnectionState enum)
2. **Task 06-02: ProductModeCard integration** — `4659438` (feat: Cloud disclosure branch + picker revert + locked Cloud segment)

**Task 06-03 (UAT checkpoint):** делегирован пользователю — см. §UAT Checkpoint ниже.

## Files Created/Modified

- **`Govorun/Views/CloudSettingsDisclosure.swift` (NEW, 378 строк)** — Disclosure container с @EnvironmentObject AppState, ConnectionState enum (notConfigured/checking/connected/error), 3 private subviews: CloudCredentialsBlock (два SecureField + «Сохранить»/«Проверить»/«Очистить» + SwiftUI .alert destructive), CloudStatusBlock (StatusDot с title+state из 3-state enum), CloudConsentBanner (Sage-tinted card, pre-ack с «Принять и включить Cloud», post-ack с «Cloud активен с DD.MM.YYYY» + «Отозвать согласие»). @FocusState для первоначального фокуса Client ID. T-15-06-01: zero Logger/print/OSLog calls, clientSecretDraft очищается сразу после save.
- **`Govorun/Views/SettingsView.swift` (MODIFIED, +27 строк в ProductModeCard)** — @State showCloudSetup + canActivateCloud computed (cloudAvailable && cloudConsentAcceptedAt != nil), ForEach Picker с условным HStack+lock.fill+Ink 0.25 для Cloud при !cloudAvailable, 2-arg .onChange с branch'ами для .superMode и .cloud (revert + показ disclosure), disclosure render alongside existing downloadStatusView с .animation(.easeOut(0.22)) на productMode и showCloudSetup.

## Decisions Made

- **Consent apply через settings.productMode, не direct applyProductMode** (см. §Deviations) — использует существующий wireSettingsChange observer, честнее уважает D-07.1 pendingProductMode-во-время-активной-сессии rule
- **Lock.fill без opacity fallback принят как ship-as-is** — Landmine #4 говорит .menu dropdown может игнорировать .foregroundStyle на HStack; lock-иконка сама по себе достаточный сигнал. Человеческая проверка в UAT шаг (A).
- **SwiftUI .alert вместо AppKit NSAlert preserved** — плановое отклонение от CONTEXT D-05, обоснованное в PATTERNS.md (HistoryView.swift precedent, единая конвенция Settings-контекста)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `AppState.applyProductMode` оказался private — не вызвать напрямую из View**

- **Found during:** Task 06-01 (первая компиляция `CloudSettingsDisclosure.swift`)
- **Issue:** Плановый текст (15-06-PLAN.md §interfaces:102) и 15-PATTERNS.md §7 утверждали что `AppState.applyProductMode(_:)` публичный и вызывается из View-слоя напрямую. На самом деле метод `private func applyProductMode(_:)` (AppState.swift:729) — недоступен снаружи. Компиляция падала:
  ```
  error: 'applyProductMode' is inaccessible due to 'private' protection level
  ```
- **Fix:** Убраны прямые вызовы `appState.applyProductMode(.cloud)` и `appState.applyProductMode(.standard)` из `acceptConsent()` / `revokeConsent()`. Вместо них написание `appState.settings.productMode = .cloud/.standard` триггерит существующий observer `wireSettingsChange → handleSettingsChanged` (AppState.swift:649-686), который и так вызывает `applyProductMode` (или откладывает в `pendingProductMode` если `sessionManager.state != .idle` — что как раз честнее уважает D-07.1 revoke-during-dictation race rule).
- **Files modified:** `Govorun/Views/CloudSettingsDisclosure.swift`
- **Verification:** build succeeded + 1297/1297 tests pass
- **Committed in:** `cd31c72` (Task 06-01 commit)
- **Impact:** grep-based acceptance criterion `grep -c 'appState.applyProductMode' returns 2` больше не выполняется (возвращает 0). Это СТРОЖЕ plan'а — View-слой теперь не трогает private API. Настоящее поведение сохраняется через observer.

---

**Total deviations:** 1 auto-fixed (Rule 3 — blocking compilation error, privately-declared method)
**Impact on plan:** Минимальный. Функциональный результат идентичен: consent accept/revoke всё равно вызывает `applyProductMode` — теперь через sanctioned observer pipeline, а не через новый public API. Это соответствует существующей архитектуре (все другие mode-changing actions в проекте идут через settings mutation + observer).

## Issues Encountered

- **SwiftFormat pre-commit hook** отформатировал комментарий-блок рядом с `// MARK: - Cloud Settings Disclosure` (вставил пустую строку). Это project convention (видно в проекте через memory `feedback_superpowers_full_mode`), не блокер — повторил commit после `swiftformat Govorun/Views/CloudSettingsDisclosure.swift`.

## User Setup Required

**GigaChat API credentials для UAT (§Task 06-03):** clientId + clientSecret из ЛК Сбера — https://developers.sber.ru/studio/workspaces/. Без них нельзя верифицировать happy path Save → Connected → Accept consent → Cloud mode active.

## UAT Checkpoint

Plan 15-06 автоматизированная часть (Tasks 06-01, 06-02) shipped в main. Task 06-03 — human UAT — делегирован пользователю. Ниже — 11 шагов для ручной верификации (из 15-06-PLAN.md §Task 06-03 + 15-VALIDATION.md §Manual-Only Verifications).

**Pre-requisites:**

1. Получить Sber GigaChat API ключи из https://developers.sber.ru/studio/workspaces/
2. Собрать DMG и установить:
   ```bash
   pkill -f Govorun 2>/dev/null; sleep 1
   bash scripts/build-unsigned-dmg.sh 2>&1 | grep 'готов'
   rm -rf /Applications/Govorun.app
   hdiutil attach build/Govorun.dmg -nobrowse 2>/dev/null
   MOUNT=$(hdiutil info | grep "Говорун" | awk '{print $NF}')
   cp -R "$MOUNT/Govorun.app" /Applications/
   hdiutil detach "$MOUNT" 2>/dev/null
   xattr -cr /Applications/Govorun.app
   open /Applications/Govorun.app
   ```
3. Разрешить Accessibility при запросе.

**Шаги верификации:**

| Шаг | Что проверить | Ожидаемое поведение | Риск при провале |
|-----|---------------|---------------------|------------------|
| (A) | Открыть Settings → Main, кликнуть dropdown-чеврон picker'а. | Три пункта: «Говорун», «Говорун Super», «Говорун Cloud». Cloud имеет `lock.fill` icon + Ink 0.25 opacity (dimmed). | Если opacity не применяется — accept-risk per Landmine #4; icon достаточный сигнал. |
| (B) | Кликнуть «Говорун Cloud» в dropdown без ключей. | Picker snap'ается обратно на предыдущий выбор. Disclosure fades+expands в ~0.22s. Client ID SecureField получает caret через ~0.05s. | — |
| (C) | Ввести Client ID + Client Secret, нажать «Сохранить». | «Сохранить» активируется (Ink fill). Status: grey «Проверяю подключение…» → Sage «Подключено» за 2-5с. Consent-банер появляется с «КОНФИДЕНЦИАЛЬНОСТЬ» label. Cloud-сегмент в dropdown больше не залочен. | — |
| (D) | Кликнуть «Принять и включить Cloud». | Banner → post-ack с «Cloud активен с {DD.MM.YYYY}» + «Отозвать согласие». Picker label = «Говорун Cloud». | — |
| (E) | Кликнуть «Отозвать согласие». | Banner → pre-ack. Picker label → «Говорун». Cloud-сегмент снова с lock. | — |
| (F) | С сохранёнными ключами кликнуть «Очистить» → подтвердить «Удалить». | Появляется SwiftUI .alert с title «Удалить ключи API?», message «Cloud-режим станет недоступен. Ключи можно будет ввести снова.», две кнопки «Отмена» и красный destructive «Удалить». После «Удалить»: оба SecureField пустые, Status: grey «Не настроено». | — |
| (G) | После «Сохранить» при валидных ключах нажать «Проверить». | Status: «Подключено» → «Проверяю…» → «Подключено». | — |
| (H) | Ввести валидный Client ID + **невалидный** Client Secret → «Сохранить». | Ember dot + Ember text «Ключи отклонены Сбером. Проверьте Client ID и Secret.» | — |
| (I) | При валидных ключах выключить Wi-Fi → «Проверить». | Ember dot + «Нет интернета. Cloud временно недоступен.» | — |
| (J) | Включить VoiceOver (Cmd+F5), Tab через Credentials. | VO читает «Идентификатор клиента Client ID для GigaChat, secure text field» (label), значение НЕ произносится. Same для Client Secret. | — |
| (K) | Полный тест-запуск: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 \| tail -5` | `Test Suite 'All tests' passed` с 1297 тестами. | Уже верифицировано автоматом. |

**Accepted-risk items (НЕ блокируют approval):**

- **Revoke-during-dictation race** — per CONTEXT D-07.1: одна последняя cloud-передача после revoke допустима. Документировано в релиз-ноутах. Для строгой верификации нужна живая Cloud-диктовка в момент revoke.
- **`.foregroundStyle` на .menu dropdown items не dim'ит на macOS 14.x** — per Landmine #4: lock-иконка сама по себе сигнал.

**Ожидаемый resume-signal:**

- `approved` — все 11 шагов (A-K) прошли
- `approved with notes: <notes>` — прошли с одной визуальной оговоркой (e.g., "lock opacity не рендерится на .menu dropdown — accept per Landmine #4")
- `failed: <шаг + issue>` — нужно debug + пересдача

После `approved` orchestrator должен:
1. Флипнуть ROADMAP checkbox для 15-06 с `[ ]` → `[x]` и убрать пометку `(pending UAT)`
2. Обновить STATE.md status до `Phase 15 complete — Cloud Settings UI ready for Phase 16 tests`

## Next Phase Readiness

- **Phase 15 полностью shipped pending UAT approval** — все 4 requirements (UI-01..UI-04) имеют видимое UI-доказательство
- **Phase 16 (Tests) blocker снят** — зависит от Phase 14 и Phase 15; обе завершены
- **Phase 17 (Polish & Rollout)** может начинать планирование после UAT approval: analytics events для cloud path, credential-gated launch, error message polish через ErrorMessages.swift для runtime cloud ошибок (out-of-scope для 15, помечено в CONTEXT D-10)

## Self-Check: PASSED

**Files created/modified verified on disk:**

- `Govorun/Views/CloudSettingsDisclosure.swift` — FOUND (378 строк)
- `Govorun/Views/SettingsView.swift` — FOUND (modified in-place, +27 строк в ProductModeCard)

**Commits verified in git log:**

- `cd31c72` feat(15-06): CloudSettingsDisclosure SwiftUI (UI-01, UI-02, UI-04) — FOUND
- `4659438` feat(15-06): ProductModeCard — Cloud disclosure + picker revert (UI-03) — FOUND

**Build + test verified:**

- `xcodebuild build -scheme Govorun` — SUCCESS (exit 0)
- `xcodebuild test -scheme Govorun` — 1297/1297 PASS, zero regressions

**Copy fidelity verified:**

- 17 locked UI-SPEC string greps returned expected counts (1-2 each, verified individually)
- 8 accessibility label/hint greps returned expected counts
- 7 token greps (Sage 0.07, Sage 0.7, Ink 0.28, cornerRadius 8/14, easeOut 0.22, monospaced) returned expected counts

**Security hygiene verified:**

- `grep -c 'Logger\|os_log\|OSLog\|print('` — 0 (no credential leakage paths)
- `grep -c 'import AppKit\|import Cocoa'` — 0 (pure SwiftUI)
- `grep -c 'credentialStoreSnapshot'` — 0 (negative criterion — method never introduced)

---

*Phase: 15-cloud-settings-ui*
*Plan: 06*
*Completed: 2026-04-20 (pending UAT approval)*
