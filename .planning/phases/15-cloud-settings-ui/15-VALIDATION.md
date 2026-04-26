---
phase: 15
slug: cloud-settings-ui
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-20
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Derived from 15-RESEARCH.md §Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest, Swift 5.10 |
| **Config file** | `Govorun.xctestplan` |
| **Quick run command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SettingsStoreTests -only-testing:GovorunTests/CloudSettingsErrorMessageTests -only-testing:GovorunTests/AppStateCloudShimTests -only-testing:GovorunTests/SberAuthServiceTests` |
| **Full suite command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Estimated runtime** | Quick ~20s, Full ~70s |
| **Baseline** | 1280 tests (Phase 14 shipped 2026-04-19) |

---

## Sampling Rate

- **After every task commit:** Run quick run command (affected test classes)
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green + manual UAT (UI-SPEC §Interaction States rows 1-8)
- **Max feedback latency:** 70 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | UI-04 | T-02 | SettingsStore persists `cloudConsentAcceptedAt: Date?` across restart; `registerDefaults()` registers nil | unit | `xcodebuild test -only-testing:GovorunTests/SettingsStoreTests/test_cloudConsentAcceptedAt_persists` | ✅ extend | ⬜ pending |
| 15-01-02 | 01 | 1 | UI-04 | T-02 | `clearCloudConsent()` sets nil and persists | unit | `xcodebuild test -only-testing:GovorunTests/SettingsStoreTests/test_clearCloudConsent_removesValue` | ✅ extend | ⬜ pending |
| 15-01-03 | 01 | 1 | UI-04 | — | `resetToDefaults()` clears cloud consent | unit | `xcodebuild test -only-testing:GovorunTests/SettingsStoreTests/test_resetToDefaults_clearsCloudConsent` | ✅ extend | ⬜ pending |
| 15-02-01 | 02 | 1 | CLOUD-06 | T-03 | `AuthError.networkError` preserves `URLError?` alongside description (Path B override — see CONTEXT D-11.2) | unit | `xcodebuild test -only-testing:GovorunTests/SberAuthServiceTests/test_networkError_preservesURLError` | ✅ extend | ⬜ pending |
| 15-02-02 | 02 | 1 | CLOUD-06 | T-03 | `AuthError.networkError` Equatable compares both urlError and description | unit | `xcodebuild test -only-testing:GovorunTests/SberAuthServiceTests/test_networkError_equatable` | ✅ extend | ⬜ pending |
| 15-03-01 | 03 | 2 | UI-02 | T-03 | `errorMessage(for: AuthError.credentialsNotFound)` → «Введите ключи API. Без них Cloud недоступен.» | unit | `xcodebuild test -only-testing:GovorunTests/CloudSettingsErrorMessageTests/test_credentialsNotFound` | ❌ W0 | ⬜ pending |
| 15-03-02 | 03 | 2 | UI-02 | T-03 | `AuthError.invalidResponse(401)` → «Ключи отклонены Сбером. Проверьте Client ID и Secret.» | unit | Same file, `test_invalidResponse_401` | ❌ W0 | ⬜ pending |
| 15-03-03 | 03 | 2 | UI-02 | T-03 | `AuthError.invalidResponse(429)` → «Слишком много запросов. Попробуйте через минуту.» | unit | Same file, `test_invalidResponse_429` | ❌ W0 | ⬜ pending |
| 15-03-04 | 03 | 2 | UI-02 | T-03 | 500-series (500, 503, 599) → «Ошибка на стороне Сбера. Попробуйте позже.» | unit | Same file, `test_invalidResponse_5xx` | ❌ W0 | ⬜ pending |
| 15-03-05 | 03 | 2 | UI-02 | T-03 | Unknown status / parsingFailed → generic «Сбой Cloud. Попробуйте позже.» | unit | Same file, `test_invalidResponse_other_and_parsingFailed` | ❌ W0 | ⬜ pending |
| 15-03-06 | 03 | 2 | UI-02 | T-03 | `AuthError.networkError(URLError.notConnectedToInternet / .networkConnectionLost)` → «Нет интернета. Cloud временно недоступен.» | unit | Same file, `test_networkError_offline` | ❌ W0 | ⬜ pending |
| 15-03-07 | 03 | 2 | UI-02 | T-03 | `AuthError.networkError(URLError.timedOut)` → «Сбер не ответил за 30 секунд. Проверьте сеть.» | unit | Same file, `test_networkError_timeout` | ❌ W0 | ⬜ pending |
| 15-03-08 | 03 | 2 | UI-02 | T-03 | `AuthError.networkError(URLError other / nil)` → «Сервис Сбера недоступен. Попробуйте позже.» | unit | Same file, `test_networkError_generic` | ❌ W0 | ⬜ pending |
| 15-04-01 | 04 | 2 | UI-01 | T-01, T-02 | `AppState.saveCloudCredentials(id, secret)` writes to CredentialStore, updates `cloudAvailable = true` | unit | `xcodebuild test -only-testing:GovorunTests/AppStateCloudShimTests/test_saveCloudCredentials_writesToStore` | ❌ W0 | ⬜ pending |
| 15-04-02 | 04 | 2 | UI-01 | T-01, T-02 | `AppState.deleteCloudCredentials()` clears CredentialStore, `cloudAvailable = false`, consent untouched | unit | Same file, `test_deleteCloudCredentials_clearsStoreKeepsConsent` | ❌ W0 | ⬜ pending |
| 15-04-03 | 04 | 2 | UI-02 | T-03 | `AppState.probeCloudConnection()` calls AuthService.getAccessToken, returns success/error | unit | Same file, `test_probeCloudConnection_happyPath` + `test_probeCloudConnection_authError` | ❌ W0 | ⬜ pending |
| 15-05-01 | 05 | 3 | UI-01, UI-02, UI-03, UI-04 | T-04, T-05 | CloudSettingsDisclosure renders without crash; connectionState transitions; consent banner visibility matches state machine | UAT | Manual — see UI-SPEC §Interaction States rows 1-8 | n/a | ⬜ pending |
| 15-05-02 | 05 | 3 | UI-03 | T-06 | ProductModeCard picker revert guard — `.onChange(of: selection)` reverts when Cloud unavailable / consent missing | UAT | Manual DMG build; click Cloud in Picker without creds → observe revert + disclosure appears | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

New test files (created in Wave 1 alongside first TDD cycle, not a separate Wave 0):
- [ ] `GovorunTests/CloudSettingsErrorMessageTests.swift` — ~8 test methods covering AuthError + URLError mapping branches (Plan 03 RED gate)
- [ ] `GovorunTests/AppStateCloudShimTests.swift` — ~4 test methods for save / delete / probe (Plan 04 RED gate)
- [ ] Extend `GovorunTests/SettingsStoreTests.swift` — 3 methods for cloudConsentAcceptedAt (Plan 01 RED gate)
- [ ] Extend `GovorunTests/SberAuthServiceTests.swift` — 2 methods for Path B AuthError URLError preservation (Plan 02 RED gate)

**Mocks reused (no new mocks needed):** `MockCredentialStore` (CredentialStore.swift:112), `MockAuthService` (SberAuthService.swift:160).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Disclosure animation timing (~0.22s easeOut) feels right | UI-02, UI-04 | Animation frames can't be unit-tested | DMG → Settings → Main → click Cloud segment → observe fade/expand |
| `@FocusState` lands on Client ID on disclosure open | UI-01 | No XCUITest in project | Open via Cloud segment → caret blinking in Client ID field |
| Return key inside SecureField submits «Сохранить» | UI-01 | No XCUITest | Type keys → press Return → expect Save to fire |
| SwiftUI `.alert()` destructive «Удалить» button renders red | UI-01 | Visual only | Trigger «Очистить» → macOS system alert → «Удалить» is red |
| VoiceOver reads labels without speaking secret value | UI-01 | Accessibility Inspector required | Enable VO → tab through fields → verify "secure text field" announcement, no value readout |
| `lock.fill` icon + Ink 0.25 opacity in disabled Cloud segment | UI-03 | Visual; `.foregroundStyle` may or may not apply to `.menu` Picker items (Landmine #4) | Inspect Cloud segment when `!cloudAvailable` in SwiftUI preview and DMG |
| 3-state StatusDot colors (Mist/Sage/Ember) match v2 tokens | UI-02 | Visual | Walk connectionState transitions manually |
| Revoke-during-dictation race — one last transfer allowed | UI-04, CONTEXT D-07.1 | Requires live GigaChat + timing | Start dictation → open Settings → «Отозвать согласие» → confirm last segment still inserts (accepted risk) |
| Consent banner pre-ack → post-ack state transition | UI-04 | Visual + state verification | Enter creds → Save → see «Подключено» → tap «Принять и включить Cloud» → banner changes to post-ack with date |
| Picker re-renders when `cloudAvailable` flips (Landmine #8) | UI-03 | SwiftUI @Published → menu-item re-render timing | Save creds → observe Cloud segment unlock without closing/reopening menu |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or documented Wave 0/UAT deps
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (4 new/extended test files listed)
- [ ] No watch-mode flags (no `--watch` / `xcpretty` interactive)
- [ ] Feedback latency < 70s
- [ ] `nyquist_compliant: true` set in frontmatter after planner confirms

**Approval:** pending (planner signs off after plan-checker gate passes)
