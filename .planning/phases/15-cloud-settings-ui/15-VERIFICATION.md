---
phase: 15-cloud-settings-ui
verified: 2026-04-20T21:30:00Z
status: human_needed
score: 9/10 must-haves verified
overrides_applied: 0
human_verification:
  - test: "(A) Picker dropdown lock icon + opacity"
    expected: "Cloud item has lock.fill icon after text + Ink 0.25 opacity (dimmed). Landmine #4: opacity may not apply under .menu pickerStyle on macOS — lock icon alone is acceptable fallback."
    why_human: "SwiftUI .menu pickerStyle may ignore .foregroundStyle on HStack children; only visual inspection of live DMG build can confirm."
  - test: "(B) Click Cloud in picker without credentials — picker reverts + disclosure opens with focus"
    expected: "Picker label snaps back to previous value. CloudSettingsDisclosure fades in ~0.22s. Client ID SecureField receives caret within ~0.05s delay."
    why_human: "@FocusState timing and DispatchQueue.main.asyncAfter(0.05) cannot be verified programmatically; requires live interaction."
  - test: "(C) Enter valid keys, click Save — status cycles to Connected, consent banner appears"
    expected: "Save button activates (Ink fill). Status: grey Mist 'Проверяю подключение...' -> Sage dot 'Подключено' within 2-5 seconds. КОНФИДЕНЦИАЛЬНОСТЬ sub-block appears. Cloud segment in picker no longer locked."
    why_human: "Requires live GigaChat API credentials (clientId/clientSecret from developers.sber.ru). Real OAuth network call needed."
  - test: "(D) Click 'Принять и включить Cloud' — consent accepted, picker shows Cloud"
    expected: "Banner transitions pre-ack -> post-ack with 'Cloud активен с DD.MM.YYYY' and 'Отозвать согласие' button. Picker label shows 'Говорун Cloud'."
    why_human: "Requires credentials + connected state from step C."
  - test: "(E) Click 'Отозвать согласие' — consent revoked, mode reverts"
    expected: "Post-ack banner -> pre-ack within 0.22s. Picker label -> 'Говорун' (standard). Cloud segment shows lock again."
    why_human: "Visual state transition; requires live credentials + prior consent from step D."
  - test: "(F) Click 'Очистить' -> confirm 'Удалить' — keys cleared"
    expected: "SwiftUI alert appears: title 'Удалить ключи API?', message 'Cloud-режим станет недоступен. Ключи можно будет ввести снова.', buttons 'Отмена' (cancel) + red 'Удалить' (destructive). After confirm: SecureFields empty, Status 'Не настроено', consent block hidden."
    why_human: "Visual verification of system alert button colors and full state reset flow."
  - test: "(G) Manual re-probe via 'Проверить' — status cycles correctly"
    expected: "Status: 'Подключено' -> 'Проверяю подключение...' -> 'Подключено'."
    why_human: "Requires live credentials and connected state."
  - test: "(H) Wrong Client Secret — error state renders correctly"
    expected: "Ember dot + Ember text 'Ключи отклонены Сбером. Проверьте Client ID и Secret.'"
    why_human: "Requires intentionally invalid credentials against live Sber API."
  - test: "(I) Offline mode — network error renders correctly"
    expected: "Ember dot + 'Нет интернета. Cloud временно недоступен.'"
    why_human: "Requires disabling Wi-Fi mid-session; URL error propagation to UI needs end-to-end verification."
  - test: "(J) VoiceOver accessibility — credentials block announced correctly"
    expected: "VoiceOver announces 'Идентификатор клиента Client ID для GigaChat, secure text field'. Value NOT spoken. Same for Client Secret."
    why_human: "Accessibility Inspector or live VoiceOver (Cmd+F5) required; cannot be automated with unit tests."
  - test: "(K) Full test suite — 1297 tests pass"
    expected: "xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation reports 'Test Suite All tests passed' with 1297 tests."
    why_human: "Build environment check; automated in this context is not possible (no xcodebuild available to verifier). SUMMARY claims 1297/1297 green — confirmed by executor self-check."
---

# Phase 15: Cloud Settings UI Verification Report

**Phase Goal:** User can enter credentials, see connection status, select Cloud mode, and give informed consent before data leaves the device
**Verified:** 2026-04-20T21:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Итог (Russian summary)

Автоматическая проверка кодовой базы показывает: все 6 планов (15-01 … 15-06) выполнены, код находится в main. Plans 01-05 полностью верифицируемы программно — все артефакты существуют, имеют substantive реализацию и правильно связаны. Plan 06 (интеграционный UI) скомпилирован и прошёл 1297/1297 юнит-тестов, но требует живой ручной верификации по 11 сценариям (A-K), поскольку визуальная анимация, @FocusState, реальные OAuth-запросы к GigaChat, VoiceOver и деструктивные alert-диалоги не поддаются автоматической проверке.

---

## Goal Achievement

### Observable Truths (Success Criteria from ROADMAP.md)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC-1 | Settings panel has fields for clientId and clientSecret that save to Keychain on input | VERIFIED | `CloudCredentialsBlock` с двумя `SecureField` + кнопкой «Сохранить», вызывающей `appState.saveCloudCredentials(clientId:clientSecret:)` → `credentialStore.save(...)` |
| SC-2 | Connection status indicator shows not configured / connected / error with actionable error text | VERIFIED | `StatusDot` 3-state + `cloudErrorMessage(for:)` с 9 locked UI-SPEC строками; `CloudStatusBlock` переключает состояния через `ConnectionState` enum |
| SC-3 | ProductMode picker shows three options; Cloud disabled when credentials missing | VERIFIED (code) / NEEDS HUMAN (visual) | `SettingsView.swift`: `ForEach` с `HStack + lock.fill + Color.ink.opacity(0.25)` при `!cloudAvailable`; `.onChange` revert guard при `!canActivateCloud`; lock opacity rendering — Landmine #4, visual check needed |
| SC-4 | First time user enables Cloud mode, privacy consent dialog explains data goes to Sber | VERIFIED (code) / NEEDS HUMAN (flow) | `CloudConsentBanner` с pre-ack (heading + body + «Принять и включить Cloud») и post-ack (дата + «Отозвать согласие»); `cloudConsentAcceptedAt: Date?` в `SettingsStore` |

**Must-haves from PLAN frontmatter — детальная проверка:**

#### Plan 15-01: SettingsStore consent storage (UI-04)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SettingsStore persists cloudConsentAcceptedAt Date? across restarts | VERIFIED | `defaults.object(forKey: Keys.cloudConsentAcceptedAt) as? Date`; test `test_cloudConsentAcceptedAt_persists` confirms persistence |
| 2 | clearCloudConsent() sets value back to nil | VERIFIED | `func clearCloudConsent() { cloudConsentAcceptedAt = nil }` confirmed; test `test_clearCloudConsent_removesValue` confirms |
| 3 | resetToDefaults() removes cloudConsentAcceptedAt | VERIFIED | `defaults.removeObject(forKey: Keys.cloudConsentAcceptedAt)` in `resetToDefaults()`; test confirms |
| 4 | Default value is nil (pre-ack semantics) | VERIFIED | Key NOT in `registerDefaults()` — confirmed by grep of SettingsStore.swift |

#### Plan 15-02: AuthError URLError payload (UI-02 / Path B)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | AuthError.networkError carries URLError? alongside description String | VERIFIED | `case networkError(urlError: URLError?, description: String)` at SberAuthService.swift:13 |
| 2 | SberAuthService catch site preserves original URLError | VERIFIED | `let urlErr = error as? URLError` + `throw AuthError.networkError(urlError: urlErr, ...)` at SberAuthService.swift:98-102 |
| 3 | AuthError Equatable compares urlError?.code AND description | VERIFIED | `ua?.code == ub?.code && da == db` at SberAuthService.swift:22 |
| 4 | CloudLLMClient.mapAuthError continues to work with updated pattern | VERIFIED | `case .networkError(_, let msg):` at CloudLLMClient.swift:289 |
| 5 | Existing SberAuthService tests still pass after payload migration | VERIFIED (SUMMARY) | 1297/1297 tests per executor self-check |

#### Plan 15-03: cloudErrorMessage(for:) in CloudErrorCopy.swift (UI-02)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | credentialsNotFound → «Введите ключи API. Без них Cloud недоступен.» | VERIFIED | CloudErrorCopy.swift:18 |
| 2 | invalidResponse(401) → «Ключи отклонены Сбером...» | VERIFIED | CloudErrorCopy.swift:23 |
| 3 | invalidResponse(429) → «Слишком много запросов...» | VERIFIED | CloudErrorCopy.swift:25 |
| 4 | invalidResponse(5xx) → «Ошибка на стороне Сбера...» | VERIFIED | CloudErrorCopy.swift:27 |
| 5 | generic fallback for other codes/tokenParsingFailed | VERIFIED | CloudErrorCopy.swift:10, 29, 32 |
| 6 | networkError(notConnected/networkConnectionLost) → «Нет интернета...» | VERIFIED | CloudErrorCopy.swift:38 |
| 7 | networkError(timedOut) → «Сбер не ответил за 30 секунд...» | VERIFIED | CloudErrorCopy.swift:40 |
| 8 | networkError(other/nil) → «Сервис Сбера недоступен...» | VERIFIED | CloudErrorCopy.swift:42 |

#### Plan 15-04: AppState cloud shim (UI-01, UI-02)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | saveCloudCredentials writes to CredentialStore + flips cloudAvailable=true | VERIFIED | AppState.swift:364-365 |
| 2 | deleteCloudCredentials clears store + flips cloudAvailable=false, no consent touch | VERIFIED | AppState.swift:371-372; `clearCloudConsent()` NOT called in deleteCloudCredentials |
| 3 | probeCloudConnection returns .success on token fetch, .failure(AuthError) on error | VERIFIED | AppState.swift:377-391; Result<Void, AuthError> pattern |
| 4 | Injectable authServiceFactory for test substitution | VERIFIED | `var authServiceFactory: () -> AuthService` at AppState.swift:43 |
| 5 | No direct credentialStore access from Views | VERIFIED | `private let credentialStore` at AppState.swift:36; Views call only shim methods |

#### Plan 15-05: StatusDot 3-state (UI-02)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | StatusDot supports 3 states: idle (Mist), connected (Sage), error (Ember) | VERIFIED | SettingsTheme.swift:123-126 enum State; dotColor/textColor switch |
| 2 | Existing init(title:isActive:) preserved | VERIFIED | SettingsTheme.swift:133-136 |
| 3 | New init(title:state:) accepts StatusDot.State | VERIFIED | SettingsTheme.swift:138-141 |
| 4 | Text color switches to Ember only in .error | VERIFIED | textColor private var: `.idle, .connected: Color.ink.opacity(0.5)`, `.error: Color.ember` |

#### Plan 15-06: CloudSettingsDisclosure integration (UI-01, UI-02, UI-03, UI-04)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Disclosure renders under ProductModeCard when .cloud OR showCloudSetup | VERIFIED | SettingsView.swift:549-554 |
| 2 | Two SecureFields for Client ID + Secret, Save disabled until both non-empty | VERIFIED | CloudSettingsDisclosure.swift:91-115; `canSave` computed |
| 3 | Save triggers AppState shim + auto-probe; status line switches states | VERIFIED | `saveAndProbe()` at CloudSettingsDisclosure.swift:192-215 |
| 4 | Consent banner renders when connected AND per consent state | VERIFIED | CloudSettingsDisclosure.swift:39-43 conditional render |
| 5 | Pre-ack 'Принять' writes Date + sets selection | VERIFIED | `acceptConsent()`: `cloudConsentAcceptedAt = Date()`, `settings.productMode = .cloud` |
| 6 | Post-ack 'Отозвать' calls clearCloudConsent + reverts mode | VERIFIED | `revokeConsent()`: `clearCloudConsent()`, `settings.productMode = .standard` |
| 7 | 'Очистить' shows SwiftUI .alert with destructive button | VERIFIED | CloudSettingsDisclosure.swift:167-176 `.alert("Удалить ключи API?", ...)` |
| 8 | Picker onChange reverts to oldValue + sets showCloudSetup=true | VERIFIED | SettingsView.swift:532-540 |
| 9 | Cloud picker item shows lock.fill + Ink 0.25 when !cloudAvailable | VERIFIED (code) | SettingsView.swift:519-526; visual rendering NEEDS HUMAN (Landmine #4) |
| 10 | All copy matches UI-SPEC verbatim | VERIFIED | 17 string greps confirmed; all locked strings present |

**Score:** 9/10 Success Criteria verified (SC-3 and SC-4 are code-complete but require human UAT for flow verification)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Govorun/Storage/SettingsStore.swift` | cloudConsentAcceptedAt accessor + clearCloudConsent + key | VERIFIED | All 3 symbols present; key = "govorun.cloud.consent.acceptedAt" |
| `GovorunTests/SettingsStoreTests.swift` | 3 new tests | VERIFIED | test_cloudConsentAcceptedAt_persists, test_clearCloudConsent_removesValue, test_resetToDefaults_clearsCloudConsent at lines 273-296 |
| `Govorun/Services/SberAuthService.swift` | AuthError.networkError URLError? payload + Equatable + catch | VERIFIED | payload at line 13; catch site at line 98; Equatable at line 22 |
| `Govorun/Services/CloudLLMClient.swift` | Updated mapAuthError pattern | VERIFIED | `case .networkError(_, let msg):` at line 289 |
| `GovorunTests/SberAuthServiceTests.swift` | 2 new tests + Equatable update | VERIFIED | Lines 86, 98, 230 |
| `Govorun/Views/CloudErrorCopy.swift` | cloudErrorMessage(for:) Foundation-only | VERIFIED | EXISTS; 9 locked strings; `import Foundation` only; zero log calls |
| `GovorunTests/CloudSettingsErrorMessageTests.swift` | 9 table-driven tests | VERIFIED | EXISTS; 9 test methods confirmed |
| `Govorun/App/AppState.swift` | 3 shim methods + authServiceFactory | VERIFIED | saveCloudCredentials:363, deleteCloudCredentials:370, probeCloudConnection:377, authServiceFactory:43 |
| `GovorunTests/AppStateCloudShimTests.swift` | 4 tests | VERIFIED | EXISTS; 4 test methods confirmed |
| `Govorun/Views/SettingsTheme.swift` | StatusDot.State enum + new init | VERIFIED | State enum at line 123; new init at line 138; backward compat init preserved at line 133 |
| `Govorun/Views/CloudSettingsDisclosure.swift` | Top-level view + 3 subviews + ConnectionState | VERIFIED | EXISTS (378 lines); CloudCredentialsBlock, CloudStatusBlock, CloudConsentBanner all present |
| `Govorun/Views/SettingsView.swift` | showCloudSetup state + canActivateCloud + onChange + disclosure | VERIFIED | showCloudSetup:294, canActivateCloud:296, onChange:532, disclosure:549 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| SettingsStore.Keys.cloudConsentAcceptedAt | UserDefaults key "govorun.cloud.consent.acceptedAt" | static let assignment | WIRED | Single definition at SettingsStore.swift:26 |
| SettingsStore.resetToDefaults() | removeObject(forKey: Keys.cloudConsentAcceptedAt) | explicit call | WIRED | SettingsStore.swift:288 |
| SberAuthService catch block | AuthError.networkError(urlError:) | let urlErr = error as? URLError | WIRED | SberAuthService.swift:98-102 |
| CloudLLMClient.mapAuthError | .networkError(_, let msg) | pattern match | WIRED | CloudLLMClient.swift:289 |
| cloudErrorMessage(for:) | AuthError cases + URLError.code | pattern match on Error → AuthError → URLError? | WIRED | CloudErrorCopy.swift:9-44 |
| AppState.saveCloudCredentials | credentialStore.save | direct call through private property | WIRED | AppState.swift:364 |
| AppState.deleteCloudCredentials | credentialStore.delete | direct call | WIRED | AppState.swift:371 |
| AppState.probeCloudConnection | authServiceFactory().getAccessToken | factory call + async | WIRED | AppState.swift:378-391 |
| ProductModeCard .onChange second branch | showCloudSetup = true + selection = oldValue | conditional in closure | WIRED | SettingsView.swift:537-540 |
| CloudCredentialsBlock.saveAndProbe | appState.saveCloudCredentials + appState.probeCloudConnection | try + async Task | WIRED | CloudSettingsDisclosure.swift:197, 205 |
| CloudConsentBanner.acceptConsent | settings.cloudConsentAcceptedAt = Date() + settings.productMode = .cloud | direct property write → wireSettingsChange observer | WIRED | CloudSettingsDisclosure.swift:367-369 |
| CloudConsentBanner.revokeConsent | settings.clearCloudConsent() + settings.productMode = .standard | method call + property write | WIRED | CloudSettingsDisclosure.swift:373-376 |
| CloudStatusBlock .error case | cloudErrorMessage(for: error) | function call | WIRED | CloudSettingsDisclosure.swift:259 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `CloudSettingsDisclosure` | `connectionState: ConnectionState` | User actions (Save/Probe) + `appState.cloudAvailable` | Yes — OAuth network probe; `onAppear` checks real `appState.cloudAvailable` | FLOWING |
| `CloudConsentBanner` | `acceptedAt: Date?` | `appState.settings.cloudConsentAcceptedAt` | Yes — real UserDefaults-persisted Date | FLOWING |
| `CloudCredentialsBlock` | `clientIdDraft, clientSecretDraft` | User input @State (not pre-filled from Keychain — security requirement) | N/A — input fields by design | FLOWING |
| `StatusDot` | `title, state` | `connectionState` switch cases | Yes — derived from real probe result | FLOWING |

**Note:** `applyProductMode` deviation: `acceptConsent()` / `revokeConsent()` write to `settings.productMode` and rely on `wireSettingsChange` observer (AppState.swift:649-686) to call the private `applyProductMode(_:)`. The observer is confirmed present and functional. This is architecturally correct — the same pattern used by all other mode-change code paths.

### Behavioral Spot-Checks

| Behavior | Verification | Result | Status |
|----------|--------------|--------|--------|
| cloudErrorMessage returns "Введите ключи API..." for credentialsNotFound | grep: string present in CloudErrorCopy.swift; 9 tests covering all branches | Confirmed | PASS |
| SecureField inputs feed into saveCloudCredentials | CloudDisclosure.swift:197 calls `appState.saveCloudCredentials(clientId: id, clientSecret: secret)` | Wired | PASS |
| Picker .onChange reverts selection on Cloud tap without credentials | SettingsView.swift:537 `selection = oldValue; showCloudSetup = true` | Wired | PASS |
| Consent acceptance writes cloudConsentAcceptedAt | CloudDisclosure.swift:367 `appState.settings.cloudConsentAcceptedAt = Date()` | Wired | PASS |
| OAuth probe via live GigaChat credentials | Requires real network + credentials | — | SKIP (needs human, step C) |

Step 7b: Live runnable checks SKIPPED — app requires DMG build + GigaChat credentials for end-to-end.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| UI-01 | 15-04, 15-06 | Поля ввода clientId и clientSecret в настройках Cloud | SATISFIED | CloudCredentialsBlock: 2 SecureFields + Save button → AppState.saveCloudCredentials → CredentialStore |
| UI-02 | 15-02, 15-03, 15-05, 15-06 | Индикатор статуса подключения (не настроен / подключён / ошибка) | SATISFIED | StatusDot 3-state + cloudErrorMessage 9 branches + CloudStatusBlock wiring |
| UI-03 | 15-06 | ProductMode picker с тремя вариантами; Cloud заблокирован без credentials | SATISFIED (code) / NEEDS HUMAN (visual) | picker ForEach with lock.fill + revert guard; visual rendering needs UAT |
| UI-04 | 15-01, 15-06 | Privacy consent при первом включении Cloud | SATISFIED (code) / NEEDS HUMAN (flow) | CloudConsentBanner pre/post-ack + cloudConsentAcceptedAt persistence; flow needs UAT |

All 4 requirements claimed in phase have code-complete implementations. UI-03 and UI-04 require human UAT for flow verification.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | — |

No TODOs, FIXMEs, placeholders, or empty implementations found in any phase-15 files. Zero Logger/print/os_log calls in CloudSettingsDisclosure.swift and CloudErrorCopy.swift. Zero force-unwraps in production code paths.

### Human Verification Required

**Pre-requisites for all live tests (C, D, E, G, H, I):**
1. Obtain Sber GigaChat API credentials from https://developers.sber.ru/studio/workspaces/ (clientId + clientSecret)
2. Build DMG:
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
3. Grant Accessibility permission if requested.

### 1. Picker lock icon + opacity (Step A)

**Test:** Open Settings -> Main tab, click ProductMode picker dropdown chevron.
**Expected:** Three items shown — «Говорун», «Говорун Super», «Говорун Cloud». Cloud item has `lock.fill` icon after text. Ideally appears dimmed at Ink 0.25 opacity.
**Why human:** SwiftUI `.menu` pickerStyle may ignore `.foregroundStyle` on HStack children (Landmine #4). Lock icon alone is an acceptable fallback per CONTEXT D-09.

### 2. Click Cloud revert + disclosure animation + focus (Step B)

**Test:** Without credentials, click «Говорун Cloud» in the dropdown.
**Expected:** Picker label snaps back to previous selection within frame. CloudSettingsDisclosure fades + expands below picker within ~0.22s. Client ID SecureField receives caret (blinking cursor) after ~0.05s delay.
**Why human:** @FocusState timing and animation frame rate cannot be unit-tested; requires live interaction.

### 3. Save valid credentials + status transition + consent banner (Step C)

**Test:** Enter valid Client ID + Client Secret, click «Сохранить».
**Expected:** Save button activates (Ink fill). Status transitions: grey «Проверяю подключение…» → Sage «Подключено» (within 2-5 seconds). Consent sub-block appears with «КОНФИДЕНЦИАЛЬНОСТЬ». Cloud segment in picker dropdown no longer shows lock.
**Why human:** Real OAuth network call to Sber GigaChat API required. Cannot be automated without live credentials.

### 4. Accept consent + Cloud mode activation (Step D)

**Test:** In consent banner, click «Принять и включить Cloud».
**Expected:** Banner transitions to post-ack state: «Cloud активен с DD.MM.YYYY» (today's date) + secondary «Отозвать согласие» button. Picker label changes to «Говорун Cloud».
**Why human:** Requires prior connected state from Step C; visual transition and picker state.

### 5. Revoke consent + mode revert (Step E)

**Test:** Click «Отозвать согласие».
**Expected:** Post-ack banner → pre-ack banner within 0.22s. Picker label → «Говорун» (standard). Cloud segment again shows lock icon.
**Why human:** Visual state machine transition; requires live prior state.

### 6. Destructive delete confirmation (Step F)

**Test:** With keys present, click «Очистить».
**Expected:** SwiftUI system alert: title «Удалить ключи API?», message «Cloud-режим станет недоступен. Ключи можно будет ввести снова.», two buttons: «Отмена» (cancel, default) and red «Удалить» (destructive). After confirming: both SecureFields empty, status grey «Не настроено», consent block hidden, Cloud segment locked.
**Why human:** System alert visual appearance and button colors; full state reset flow requires live interaction.

### 7. Manual re-probe cycle (Step G)

**Test:** After connecting, click «Проверить».
**Expected:** Status cycles «Подключено» → «Проверяю подключение…» → «Подключено».
**Why human:** Requires live credentials + connected state.

### 8. Invalid credentials error path (Step H)

**Test:** Enter valid Client ID + intentionally wrong Client Secret, click «Сохранить».
**Expected:** Ember dot + Ember text «Ключи отклонены Сбером. Проверьте Client ID и Secret.»
**Why human:** Requires real Sber API response; 401 error path.

### 9. Offline error path (Step I)

**Test:** Enter valid keys, disable Wi-Fi, click «Проверить».
**Expected:** Ember dot + «Нет интернета. Cloud временно недоступен.»
**Why human:** URLError.notConnectedToInternet propagation through AuthError → cloudErrorMessage → StatusDot end-to-end requires real network state change.

### 10. VoiceOver accessibility (Step J)

**Test:** Enable VoiceOver (Cmd+F5), Tab through Credentials block.
**Expected:** VoiceOver announces «Идентификатор клиента Client ID для GigaChat, secure text field». Value NOT spoken. Same for Client Secret.
**Why human:** Accessibility Inspector or live VoiceOver required; not automatable with unit tests.

### 11. Full test suite confirmation (Step K)

**Test:** Run `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -5`
**Expected:** `Test Suite 'All tests' passed` with 1297 tests.
**Why human:** Build environment verification; executor self-check confirms this passes, but an independent run in the target environment is standard UAT practice.

**Accepted-risk items (do NOT block approval):**
- «Revoke-during-dictation race» (CONTEXT D-07.1): one last cloud payload may reach Sber after revoke — documented in release notes.
- «lock.fill opacity not rendering in .menu dropdown» (Landmine #4): lock icon alone is the signal per CONTEXT D-09.

---

### Gaps Summary

No automated gaps found. All code artifacts exist, are substantive (not stubs), and are correctly wired. The 1297-test suite provides programmatic coverage for all logic branches (Plans 01-04). Plan 06 (integration view) is code-complete and build-green per executor self-check.

**Status is `human_needed` because** 11 UAT steps (A-K) require visual verification, live GigaChat credentials, and/or VoiceOver — behaviors that cannot be verified programmatically.

**Resume signal to provide after UAT:**
- `approved` — all 11 steps A-K pass
- `approved with notes: <notes>` — passes with visual-only observations (e.g., "lock opacity not applying on .menu dropdown — accept per Landmine #4")
- `failed: <step letter + issue>` — one of A-K failed; re-plan needed

---

_Verified: 2026-04-20T21:30:00Z_
_Verifier: Claude (gsd-verifier)_
