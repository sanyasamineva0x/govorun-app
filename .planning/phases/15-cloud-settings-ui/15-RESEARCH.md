# Phase 15 Research

**Researched:** 2026-04-20
**Domain:** Pure-UI SwiftUI phase — Cloud credentials disclosure inside ProductModeCard, connection probe, consent banner, destructive confirmation
**Confidence:** HIGH (CONTEXT.md D-01..D-11.1 locked; UI-SPEC approved by gsd-ui-checker; source code verified in-session)

---

## Summary

Phase 15 adds a **pure-UI disclosure block** inside the existing `ProductModeCard` (`Govorun/Views/SettingsView.swift:291`) that lets the user enter GigaChat `clientId`/`clientSecret` via `SecureField`s, probe the OAuth endpoint, see connection status, give one-time privacy consent, and revoke it. All backend plumbing — `CredentialStoring` protocol (Phase 10), `SberAuthService` actor (Phase 11), `AppState.applyProductMode(.cloud)` guard (Phase 13) — already exists and MUST NOT be touched. The phase boundary is strict: `Views/CloudSettingsDisclosure.swift` (new) + `ProductModeCard` edit + one UserDefaults key added to `SettingsStore` (~350–430 lines total across one new file and two in-place edits).

Three things are genuinely novel for this codebase and the planner must handle them with care: **(1)** this is the **first View-layer consumer of `CredentialStoring`** — today `credentialStore` is `private let` in AppState, so the planner must decide how to expose save/get/delete to the new disclosure (direct injection vs. routing through AppState methods); **(2)** this is the **first `@FocusState` usage** anywhere in the project; **(3)** this is the **first `SecureField` usage** anywhere in the project. All three are standard SwiftUI but unprecedented here, so test-harness patterns don't exist yet. Fortunately the rest of the phase composes existing design-system-v2 tokens (`Color.snow/mist/ink/sage/ember`, `BrandedButton`, `SectionHeader`) without modification.

Two landmines deserve upfront attention and surface in the Known Landmines section: **(a)** `SberAuthService.swift:98` throws `AuthError.networkError(error.localizedDescription)` — the original `URLError` is wrapped into a `String`, so the UI-SPEC D-11 approach of `if let urlErr = error as? URLError` WILL NOT fire against the AuthError payload; planner must re-read the localizedDescription text or accept the generic fallback; **(b)** the existing `StatusDot` component (`SettingsTheme.swift:122`) is binary (Sage when active, Mist when not) — it has no Ember/error state, so the planner must either extend `StatusDot` (minimal additive change — add a third state, keeps the component in the design system) or build a local 3-state StatusLine inline in `CloudStatusBlock`.

**Primary recommendation:** Extract `CloudSettingsDisclosure.swift` as a new file. Extend `StatusDot` with a 3-state API (idle/connected/error) additively. Expose credentials access to the disclosure by adding thin `@MainActor` methods on AppState (`saveCloudCredentials(clientId:secret:) async throws` + `deleteCloudCredentials() throws` + `probeCloudConnection() async throws`) that internally call the existing private `credentialStore` and a freshly-created `SberAuthService`. This keeps the View away from `Security.framework` and the `AuthService` protocol, preserves the `private let credentialStore` encapsulation, and respects the pure-UI boundary. **Alternative: direct injection of `CredentialStoring` into CloudSettingsDisclosure** via environment — cleaner DI but requires touching AppState to surface it. Planner chooses.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Cloud settings live INSIDE `ProductModeCard` as a disclosure block — same pattern as Super's `downloadStatusView`. No new sidebar section. File-split decision (new `CloudSettingsDisclosure.swift` vs. private subview) delegated to planner; UI-SPEC recommends **new file**.
- **D-02:** Keep `Picker(.menu)` style. Cloud-segment click when prerequisites unmet → `.onChange(of: selection)` handler reverts `selection` to previous value AND sets `@State showCloudSetup = true`. Pattern MUST mirror existing Super revert at `SettingsView.swift:518-522`.
- **D-03:** Two `SecureField`s for Client ID and Client Secret. Primary "Сохранить" button active only when both non-empty. Save calls `CredentialStore.save(...)` then immediately triggers OAuth probe (D-04). No auto-save on blur.
- **D-04:** "Подключено" = successful `AuthService.getAccessToken()`. **Do NOT** call `/chat/completions` — it costs GigaChat tokens. Auto-probe after Save + secondary "Проверить" button for manual retest.
- **D-05:** Delete keys = secondary "Очистить" button + destructive confirmation (NSAlert or SwiftUI `.alert()` — see Known Landmines) with title «Удалить ключи API?», body «Cloud-режим станет недоступен. Ключи можно будет ввести снова.», buttons «Удалить» / «Отмена».
- **D-06:** Consent = persistent banner INSIDE disclosure, not modal sheet. Two states: pre-ack (warning + primary "Принять и включить Cloud") and post-ack («Активно с YYYY-MM-DD» + secondary "Отозвать согласие"). Cloud mode NOT activated until pre-ack confirmed.
- **D-07:** One-time acceptance. New `cloudConsentAcceptedAt: Date?` in `SettingsStore` (UserDefaults key `govorun.cloud.consent.acceptedAt`). Revoke clears flag → `productMode = .standard` → banner returns to pre-ack. Keychain keys survive revoke.
- **D-07.1 (revoke-during-dictation race — accept-risk):** `AppState.applyProductMode(.standard)` defers switch until session returns to idle (existing pattern). `PipelineEngine.stopRecording` snapshots `productMode` and `cloudClient` at the start. If user revokes mid-dictation, the current cloud request may still reach Sber. For v2.0 this risk is accepted; revoke takes effect from the next session. Document in UAT/release notes; DO NOT attempt a mid-task cancel (requires Services changes — out of scope).
- **D-08:** Refusal (user backs out without clicking "Принять и включить Cloud") → productMode stays as it was; keys saved in Keychain survive if Save was pressed.
- **D-09:** When `!cloudAvailable`, Cloud segment is grayed (Ink 0.25) + `lock.fill` trailing icon, **but remains clickable** — click opens setup-disclosure via D-02 mechanism. **Do NOT use `.disabled(true)`** on the segment (that would kill the click).
- **D-10:** Runtime/save errors show inline in status-line (Ember dot + specific text). Error mapping `AuthError/URLError → localized Russian string` lives **inside the View** (private `func errorMessage(for: Error) -> String` in `CloudSettingsDisclosure`). **Do NOT** edit `Core/ErrorMessages.swift` — preserves pure-UI boundary.
- **D-11:** Error strings locked in UI-SPEC §Copywriting Contract § Status sub-block. `AuthError.networkError(String)` is mapped via URLError cast fallback (see Known Landmine #3). Unmatched responses → generic «Сбой Cloud. Попробуйте позже.»
- **D-11.1 (out-of-scope errors):** `CloudLLMClient.parsingFailed`, mid-session token-expiry 401, quota/permission exhaustion ≠ 429 → map to generic «Сбой Cloud» without differentiation. Differentiation requires AuthError/LLMError extension in Services/ — explicitly out of scope.

### Claude's Discretion (UI-SPEC resolved — Planner inherits)

- File split: NEW `Govorun/Views/CloudSettingsDisclosure.swift`.
- `SecureField` styling: 1pt Mist border, 8pt radius, 12pt horizontal × 7pt vertical padding, monospaced input font (`.system(size: 12, design: .monospaced)`).
- `lock.fill` position: 4pt AFTER "Cloud" text (trailing).
- Disclosure animation: `.easeOut(duration: 0.22)`.
- Save keyboard shortcut: Return via `.keyboardShortcut(.defaultAction)` on primary button. NO ⌘S.
- Consent UserDefaults key: `"govorun.cloud.consent.acceptedAt"`.
- Error mapping: private `errorMessage(for: Error) -> String` inside `CloudSettingsDisclosure.swift`, NOT in `Core/ErrorMessages.swift`.
- Post-ack date format: absolute short (`DateFormatter.short` → «15.04.2026»), NOT relative.
- `URLError.code` extraction: parse inside `errorMessage(for:)` via `if let urlErr = error as? URLError { ... }`. **WARNING: this cast will fail against `AuthError.networkError(String)` — see Landmine #3.**
- Secondary button wording: «Проверить» / «Очистить» / «Отозвать согласие».

### Deferred Ideas (OUT OF SCOPE — Do Not Research)

- Cloud request log in history/settings (v3 or post-launch)
- GigaChat token balance display (post-launch per REQUIREMENTS §Future)
- Auto-fallback cloud → super on network loss (UX risk, deferred per REQUIREMENTS §Out of Scope)
- Multiple credential profiles (post-launch)
- Cloud-specific text-style temperature knobs (v3)
- Export/import credentials (unneeded — keys obtained from Sber LK on request)

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| UI-01 | Поля ввода clientId и clientSecret | Two `SecureField`s in `CloudCredentialsBlock`. Save → `CredentialStore.save(clientId:clientSecret:)` via AppState shim (Landmine #2 resolution). MockCredentialStore exists for tests. [VERIFIED: `CredentialStore.swift:30-35`] |
| UI-02 | Индикатор статуса подключения (not configured / connected / error) | Extend `StatusDot` (binary today) → 3-state (Landmine #1) or build local. `connectionState` @State enum in disclosure; state machine per UI-SPEC §State machine. |
| UI-03 | ProductMode picker с тремя вариантами (Говорун / Super / Cloud); Cloud disabled когда credentials missing | Existing Picker at `SettingsView.swift:511-517`. Extend existing `.onChange(of: selection)` at `SettingsView.swift:518-522` with second branch for `.cloud` prerequisite check (mirror Super pattern exactly). |
| UI-04 | Privacy consent при первом enable | `CloudConsentBanner` subview, 2 states. New `SettingsStore.cloudConsentAcceptedAt: Date?` + `clearCloudConsent()`. `registerDefaults()` + migrate* pattern verified against existing code at `SettingsStore.swift:36-57`. |

---

## Existing Patterns Inventory

### Pattern 1: `.onChange(of: selection)` revert for Super (D-02 template)

**Location:** `Govorun/Views/SettingsView.swift:516-522`

```swift
Picker("", selection: $selection) {
    ForEach(ProductMode.allCases, id: \.self) { mode in
        Text(mode.title).tag(mode)
    }
}
.pickerStyle(.menu)
.frame(width: 180)
.onChange(of: selection) { _, newValue in
    if newValue == .superMode, !superAvailable {
        selection = .standard
    }
}
```

`superAvailable` is a computed property on `ProductModeCard` (`SettingsView.swift:295-302`) that returns `false` only for `.runtimeMissing`. When the user picks `.superMode` without assets, `selection` immediately snaps back to `.standard`. No animation, no toast. The revert works because SwiftUI picks up the assignment on the next render.

**Extension pattern for D-02 Cloud (planner must mirror):**

```swift
@State private var showCloudSetup: Bool = false

// ...
.onChange(of: selection) { oldValue, newValue in
    if newValue == .superMode, !superAvailable {
        selection = .standard
        return
    }
    if newValue == .cloud, !canActivateCloud {
        selection = oldValue            // revert — NOT hardcoded .standard
        showCloudSetup = true           // open disclosure anyway
    }
}
```

Where `canActivateCloud = appState.cloudAvailable && appState.settings.cloudConsentAcceptedAt != nil`. Note: Super pattern reverts to hardcoded `.standard`, but for Cloud the spec requires reverting to **previous non-cloud value** so the user keeps whatever they had. Capture `oldValue` — it's the first arg of the macOS 14+ 2-arg `.onChange(of:)` closure.

[VERIFIED: `SettingsView.swift:518-521` inspected in-session]

### Pattern 2: `downloadStatusView` disclosure pattern (D-01 template)

**Location:** `Govorun/Views/SettingsView.swift:331-490` (ViewBuilder body), rendered at `SettingsView.swift:525-530`:

```swift
VStack(alignment: .leading, spacing: 6) {
    // ВАЖНО: settings.productMode (выбранный в picker), НЕ effectiveProductMode
    if appState.settings.productMode == .superMode {
        downloadStatusView
    }
}
```

`downloadStatusView` is a `@ViewBuilder` private computed property that switches on `appState.superAssetsState` and renders different content per state (`.installed` → Sage label; `.error` → red label + retry buttons; `.modelMissing` → download progress UI).

**Cloud analog (planner):**

```swift
VStack(alignment: .leading, spacing: 6) {
    if appState.settings.productMode == .cloud || showCloudSetup {
        CloudSettingsDisclosure()
            .transition(.opacity)       // fade, consistent with existing
    }
}
.animation(.easeOut(duration: 0.22), value: appState.settings.productMode)
.animation(.easeOut(duration: 0.22), value: showCloudSetup)
```

**Animation timing verification:** `SettingsView.swift` uses `.easeOut(duration: 0.25)` at line 36 (section switch), `.easeOut(duration: 0.2)` at line 163 (sidebar item hover). UI-SPEC resolution says 0.22s — that value is NOT already in the codebase but falls within the existing 0.15–0.35 band. Acceptable. `downloadStatusView` itself does NOT declare its own animation — it rides the parent `SettingsView` transition at line 36. [VERIFIED: full file read]

### Pattern 3: `SettingsStore.Keys` enum + `registerDefaults()` + migrate* (D-07 template)

**Location:** `Govorun/Storage/SettingsStore.swift:9-57`

```swift
private enum Keys {
    static let productMode = "productMode"
    static let superStyleMode = "superStyleMode"
    // ...
    static let llmHealthcheckTimeout = "llmHealthcheckTimeout"
}

init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    registerDefaults()
    migrateRecordingMode()
}

private func registerDefaults() {
    defaults.register(defaults: [
        Keys.productMode: ProductMode.standard.rawValue,
        // ...
    ])
}

/// Миграция: v0.1.8 хранил recordingMode как "hold", теперь enum "pushToTalk"
private func migrateRecordingMode() {
    if defaults.string(forKey: Keys.recordingMode) == "hold" {
        defaults.set(RecordingMode.pushToTalk.rawValue, forKey: Keys.recordingMode)
    }
}
```

**Cloud consent additions (planner):**

```swift
private enum Keys {
    // ... existing ...
    static let cloudConsentAcceptedAt = "govorun.cloud.consent.acceptedAt"
}

// В registerDefaults() — НЕ добавляем (default = nil, отсутствие ключа = pre-ack)

// Migration — не требуется (новый ключ, пустое значение семантически правильно)

var cloudConsentAcceptedAt: Date? {
    get { defaults.object(forKey: Keys.cloudConsentAcceptedAt) as? Date }
    set {
        if let newValue {
            defaults.set(newValue, forKey: Keys.cloudConsentAcceptedAt)
        } else {
            defaults.removeObject(forKey: Keys.cloudConsentAcceptedAt)
        }
        objectWillChange.send()
    }
}

func clearCloudConsent() {
    cloudConsentAcceptedAt = nil
}
```

**Important gotchas:**
- Do NOT add this key to `registerDefaults()` — registering `nil` is an error in UserDefaults, and the "absence = pre-ack" semantics already give us the default.
- Do ADD removal to `resetToDefaults()` (`SettingsStore.swift:255-271`): `defaults.removeObject(forKey: Keys.cloudConsentAcceptedAt)`.
- `Date` in UserDefaults is first-class (`defaults.set(Date(), forKey:)` stores as plist Date). No JSON encoding needed.
- `objectWillChange.send()` is the project convention in every setter — do NOT omit.

[VERIFIED: `SettingsStore.swift:9-57, 255-271` read in-session]

### Pattern 4: Destructive confirmation dialog (D-05 template)

**Location:** `Govorun/Views/HistoryView.swift:54-61` — SwiftUI `.alert()` with `.destructive` role (NOT NSAlert):

```swift
.alert("Очистить историю?", isPresented: $showClearConfirmation) {
    Button("Отмена", role: .cancel) {}
    Button("Очистить", role: .destructive) {
        clearHistory()
    }
} message: {
    Text("Ваши записи будут удалены навсегда")
}
```

**Alternative AppKit NSAlert usage** — found ONLY at `Govorun/GovorunApp.swift:27-31` for a fatal-error database failure; uses `alertStyle = .critical` + `runModal()`. Imperative and blocks the thread — NOT suitable for settings UI.

**Recommendation for planner:** Use SwiftUI `.alert()` pattern (matches HistoryView convention, integrates with the settings window's event loop, red "Удалить" text drawn natively by AppKit via `.destructive` role). The UI-SPEC/CONTEXT both say "NSAlert" but the existing codebase precedent for Settings-window destructive confirmations is SwiftUI `.alert()`. Document this deviation or follow precedent.

```swift
@State private var showClearKeysAlert: Bool = false

// ... in CloudCredentialsBlock:
Button("Очистить") { showClearKeysAlert = true }
    .alert("Удалить ключи API?", isPresented: $showClearKeysAlert) {
        Button("Отмена", role: .cancel) {}
        Button("Удалить", role: .destructive) { deleteCloudKeys() }
    } message: {
        Text("Cloud-режим станет недоступен. Ключи можно будет ввести снова.")
    }
```

[VERIFIED: `HistoryView.swift:54-61`, `GovorunApp.swift:27-31` read in-session]

### Pattern 5: `@FocusState` — NO existing usage

**Grep result:** `@FocusState` / `FocusState` / `.focused(` — **0 matches** across entire `Govorun/` directory.

Phase 15 will introduce the first `@FocusState` in the project. Standard SwiftUI pattern:

```swift
private enum CloudField: Hashable { case clientId, clientSecret }

@FocusState private var focus: CloudField?

// ...
SecureField("Введите Client ID", text: $clientIdDraft)
    .focused($focus, equals: .clientId)
SecureField("Введите Client Secret", text: $clientSecretDraft)
    .focused($focus, equals: .clientSecret)

.onAppear { focus = .clientId }
```

No existing pattern to reference — rely on SwiftUI docs. Unit-testing focus is brittle (requires UI tests, XCUITest). Since the project uses XCTest-only (986 tests, 0 XCUITest — verified via TESTING.md), **focus behavior is UAT-only**, not automated.

### Pattern 6: `BrandedButton.Style.primary` / `.secondary` usage

**Location:** `Govorun/Views/SettingsTheme.swift:201-231` (component definition)

```swift
struct BrandedButton: View {
    let title: String
    let style: Style
    let action: () -> Void

    enum Style {
        case primary
        case secondary
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(style == .primary ? .white : Color.ink.opacity(0.5))
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(style == .primary ? Color.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Group {
                        if style == .secondary {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.mist, lineWidth: 1)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
}
```

**Real call sites** (all `Govorun/Views/OnboardingView.swift` + `TextStyleSettingsView.swift`):

| File | Line | Style | Title |
|------|------|-------|-------|
| `OnboardingView.swift` | 224 | primary | «Разрешить доступ» |
| `OnboardingView.swift` | 292 | secondary | «Открыть настройки системы» |
| `OnboardingView.swift` | 387 | primary | «Повторить» |
| `OnboardingView.swift` | 390 | secondary | «Отмена» |
| `OnboardingView.swift` | 406 | primary | «Скачать (~900 МБ)» |
| `OnboardingView.swift` | 510 | secondary | «Пропустить» |
| `OnboardingView.swift` | 586 | primary | «Готово» |
| `TextStyleSettingsView.swift` | 190 | primary | variable `ctaText` |

**No `disabled` state in `BrandedButton`.** If the Save button is disabled when fields are empty, the planner must either wrap the button in `.disabled(!canSave)` modifier (SwiftUI default — greys the whole thing via system tinting) or build a custom disabled variant. UI-SPEC (line 111) says "Ink 0.25 label" for disabled Save — that's a NEW state for `BrandedButton`. **Option A: `.disabled(!canSave).opacity(canSave ? 1 : 0.4)`** is the minimal solution and matches the system look; **Option B:** extend `BrandedButton.Style` with a `.primaryDisabled` case. Prefer Option A to avoid modifying `SettingsTheme.swift`.

[VERIFIED: `SettingsTheme.swift:201-231`, grep output]

### Pattern 7: `StatusDot` usage and capability gap

**Location:** `Govorun/Views/SettingsTheme.swift:120-136`:

```swift
struct StatusDot: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Color.sage : Color.mist)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.ink.opacity(0.5))
        }
    }
}
```

**Call sites:** grep for `StatusDot(` across `Govorun/` returns **ZERO matches**. The component is defined but unused anywhere. This is actually good news — we can safely extend the API without regression fear.

**UI-SPEC requires 3 states (idle/connected/error):** Mist dot + Ink-0.5 text, Sage dot + Ink-0.5 text, Ember dot + Ember text. Current `isActive: Bool` gives only 2 states and can't swing the text color to Ember for error.

**Recommendation — extend the component (minimal additive):**

```swift
struct StatusDot: View {
    enum State { case idle, active, error }

    let title: String
    let state: State

    /// Backward-compat initializer (preserves current `isActive: Bool` API in case of future use)
    init(title: String, isActive: Bool) {
        self.title = title
        self.state = isActive ? .active : .idle
    }

    init(title: String, state: State) {
        self.title = title
        self.state = state
    }

    private var dotColor: Color {
        switch state {
        case .idle: .mist
        case .active: .sage
        case .error: .ember
        }
    }

    private var textColor: Color {
        switch state {
        case .idle, .active: Color.ink.opacity(0.5)
        case .error: .ember
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
            Text(title).font(.caption).foregroundStyle(textColor)
        }
    }
}
```

Alternative: build `CloudStatusBlock` as a bespoke HStack inline (no StatusDot reuse) — violates the "compose existing components without modification" principle from UI-SPEC §Existing Assets Reused. The additive extension is a smaller delta and serves future status-line UI. The planner can scope this change to a separate commit boundary (Wave 0 prep) or include it in the disclosure plan.

[VERIFIED: grep `StatusDot(` returned 0 call sites; `SettingsTheme.swift:120-136` read in-session]

### Pattern 8: `CredentialStoring` save/get/delete call sites — AppState-only

**Grep result:** `credentialStore.save` / `credentialStore.get` / `credentialStore.delete` — all matches are inside `Govorun/App/AppState.swift`:

| Line | Context |
|------|---------|
| 212-213 | Production init: `let credentialStore = CredentialStore(); self.credentialStore = credentialStore` |
| 242 | `cloudAvailable = credentialStore.get() != nil` (init tail) |
| 300 | Test init: `self.credentialStore = credentialStore ?? MockCredentialStore()` |
| 307 | `cloudAvailable = self.credentialStore.get() != nil` |
| 478 | `if currentProductMode.isCloud, credentialStore.get() == nil { ... }` (auto-downgrade on launch) |
| 710 | `guard credentialStore.get() != nil else { ... }` in `applyProductMode(.cloud)` |
| 715 | `credentialProvider: { [credentialStore] in credentialStore.get() }` (SberAuthService init) |
| 730 | `cloudAvailable = credentialStore.get() != nil` (applyProductMode tail) |

**Key finding:** `credentialStore: CredentialStoring` is declared `private let` at `AppState.swift:36`. The View layer has **zero direct access** today. No `save()` or `delete()` call exists from Views — only `get()` reads, and those live entirely in AppState.

**Options for Phase 15 (planner chooses in plan review):**

**Option A (recommended): AppState shim methods** — add thin `@MainActor` methods on AppState that Views call:

```swift
// AppState extensions (no protocol change, no layer violation)
@MainActor
extension AppState {
    func saveCloudCredentials(clientId: String, clientSecret: String) async throws {
        try credentialStore.save(clientId: clientId, clientSecret: clientSecret)
        cloudAvailable = true
    }

    func deleteCloudCredentials() throws {
        try credentialStore.delete()
        cloudAvailable = false
        // settings.cloudConsentAcceptedAt stays — consent is independent of keys
    }

    func probeCloudConnection() async throws {
        // свежий SberAuthService каждый раз — ключи могли обновиться
        let auth = SberAuthService(
            credentialProvider: { [credentialStore] in credentialStore.get() }
        )
        _ = try await auth.getAccessToken()
    }
}
```

Pros: Keeps `credentialStore` private. No Views/Services coupling. Testable via test init (`MockCredentialStore`). Zero new protocols.
Cons: AppState grows 3 methods (currently ~1300 lines — small delta).

**Option B: Direct injection via environment** — surface `credentialStore: CredentialStoring` as `@Published` or via an `EnvironmentKey`. Views inject it directly. More "SwiftUI idiomatic" but requires exposing the protocol to the View layer and deciding the test-time substitution story (which CloudSettingsDisclosure_Previews uses?).

**Option C: Mixed** — AppState exposes `credentialStore` via a read-only property (`var credentialStoreRead: CredentialStoring { credentialStore }`). Simplest but leaks the abstraction.

Planner should pick Option A for the pure-UI boundary. The planner should also check whether `AppState` already has `@MainActor` on the class (YES — `AppState.swift:8: @MainActor final class AppState`) so extensions don't need the attribute repeated.

[VERIFIED: all grep hits read in-session; `AppState.swift:8` confirmed `@MainActor`]

### Pattern 9: `AuthService.getAccessToken()` call sites — CloudLLMClient-only

**Grep result:** `getAccessToken` / `AuthService` — called exclusively by `CloudLLMClient`:

| File | Line | Context |
|------|------|---------|
| `Govorun/Services/SberAuthService.swift` | 6 | Protocol definition: `func getAccessToken() async throws -> String` |
| `Govorun/Services/SberAuthService.swift` | 72 | Implementation start |
| `Govorun/Services/CloudLLMClient.swift` | 146 | `return try await authService.getAccessToken()` (upload + chat calls fetch token here) |
| `Govorun/App/AppState.swift` | 714 | `let authService = SberAuthService(credentialProvider: ...)` (construction only, not call) |

**Phase 15 will be the first direct View-to-AuthService probe.** No existing `AuthError` handling in Views. `ErrorMessages.swift` (`Govorun/Core/ErrorMessages.swift`) does NOT map `AuthError` (it maps `URLError`, `PipelineError`, `STTError`, `LLMError`, `AudioCaptureError`, `WorkerError`, `TextInsertionError` — no auth entry). Per CONTEXT D-10, the phase-15 error mapping is local to `CloudSettingsDisclosure.swift` and must NOT touch `Core/ErrorMessages.swift`.

**Planner note:** A fresh `SberAuthService` instance per probe is cheap (actor, no init side effects) but bypasses the cached token from the production `cloudLLMClient`. This is fine — probe is for "are these keys accepted?", not "do we have a valid session now?". AppState's cached `cloudLLMClient` may still have a stale token from a previous session; the probe answers a fresher question.

[VERIFIED: grep output in-session]

---

## Architectural Responsibility Map

Single-tier macOS app (no browser/server split). All Phase 15 work is in the Views tier. Explicitly listing the capability→tier mapping for the planner's sanity-check:

| Capability | Tier | Rationale |
|------------|------|-----------|
| Credential input (SecureField binding) | Views | User-facing input; SwiftUI state |
| Credential persistence (Keychain write) | Storage (via AppState shim) | `CredentialStoring` protocol already owns this; Views MUST NOT import `Security.framework` |
| OAuth connection probe | Services (via AppState shim) | `SberAuthService` actor; Views MUST NOT import `HTTPClient` or construct `URLRequest` |
| Connection status state machine | Views | `@State connectionState` enum; pure UI derived state |
| Consent persistence | Storage (`SettingsStore`) | UserDefaults accessor; project convention |
| Mode picker revert logic | Views (ProductModeCard) | Existing pattern at `SettingsView.swift:518-521`; extend in-place |
| Privacy banner rendering | Views | Pure SwiftUI composition |
| Destructive confirmation dialog | Views (SwiftUI `.alert()`) | System-drawn by AppKit via `.destructive` role |
| Error mapping `AuthError → Russian` | Views (local helper) | CONTEXT D-10 explicitly places this in View layer; pure-UI boundary |

**Forbidden touches (explicit boundary):**
- `Govorun/Core/` — any file (including `ErrorMessages.swift`)
- `Govorun/Services/` — any file
- `Govorun/Models/ProductMode.swift`, `CredentialStore.swift`, `SberAuthService.swift`, `CloudLLMClient.swift`, `PipelineEngine.swift`
- `Govorun/Storage/` — only `SettingsStore.swift` may grow by ~15-20 lines for consent accessor

**Permitted touches:**
- `Govorun/Views/CloudSettingsDisclosure.swift` — new file
- `Govorun/Views/SettingsView.swift` — in-place edit of `ProductModeCard` struct only (+30-40 lines)
- `Govorun/Views/SettingsTheme.swift` — additive `StatusDot.State` enum if planner picks that path (optional; +15 lines)
- `Govorun/Storage/SettingsStore.swift` — Keys.cloudConsentAcceptedAt + accessor + reset removal (+15-20 lines)
- `Govorun/App/AppState.swift` — 3 thin shim methods (if Option A chosen) in a new extension block (+20-30 lines). Planner decides whether AppState edit is in-scope — the pure-UI CONTEXT boundary is about NOT editing Core/Services/Models, and AppState is App-tier composition root, not Services. Adding shim methods there is idiomatic.

---

## Implementation Sequencing

### Wave 0 — prerequisites (if StatusDot extension chosen)

- [ ] **Wave-0 task:** Extend `StatusDot` in `SettingsTheme.swift` additively with `State` enum (idle/active/error). Keep `init(title:isActive:)` for backward compatibility. Add `init(title:state:)`. No test coverage needed (pure declarative view). ~15 lines.

### Wave 1 — independent pieces (PARALLEL)

- [ ] **Plan A: SettingsStore consent accessor** — independent of all other work. TDD-friendly (pure UserDefaults logic). Files: `SettingsStore.swift`, `GovorunTests/SettingsStoreTests.swift`.
- [ ] **Plan B: Error mapping helper + probe shim on AppState** — independent; `errorMessage(for:)` is a pure function testable in isolation. Files: new `GovorunTests/CloudSettingsErrorMessageTests.swift` + AppState extension + `GovorunTests/AppStateCloudShimTests.swift`.
- [ ] **Plan C: StatusDot extension** (Wave 0 alternative) — if planner defers to Wave 1, no dependents until Plan D.

### Wave 2 — disclosure body (depends on Wave 1)

- [ ] **Plan D: CloudSettingsDisclosure.swift body** — depends on Wave 1 (errorMessage + consent accessor + probe shim). Contains `CloudCredentialsBlock`, `CloudStatusBlock`, `CloudConsentBanner`, `ConnectionState` enum, `errorMessage(for:)` helper. Mostly pure SwiftUI rendering — limited TDD surface. Files: new `Govorun/Views/CloudSettingsDisclosure.swift`.

### Wave 3 — integration (depends on Wave 2)

- [ ] **Plan E: ProductModeCard integration** — depends on CloudSettingsDisclosure existing. Edits `SettingsView.swift:291+` to add `@State showCloudSetup`, `.onChange(of: selection)` second branch, conditional render. Files: `SettingsView.swift` in-place.

### Waves could compress to 2 if planner judges risk low:

- **Alternative:** Wave 1 (Plans A+B+C+D in parallel since D only needs the error signatures) → Wave 2 (Plan E). But Plan D depends on Plan A's `settings.cloudConsentAcceptedAt` accessor existing as an API surface. If the planner stubs the accessor first (empty file with signatures) and parallelizes, 2 waves work. Otherwise 3.

### TDD candidates (unit-testable logic)

| Piece | Why testable | Approach |
|-------|--------------|----------|
| `SettingsStore.cloudConsentAcceptedAt` accessor + `clearCloudConsent()` | Pure UserDefaults round-trip | Existing `SettingsStoreTests.swift` pattern: UUID-suffixed suite (`UserDefaults(suiteName: "test-\(UUID())")`), set → get → clear → assert nil. Match lines in existing `SettingsStoreTests.swift` (29 tests already). |
| `errorMessage(for: Error) -> String` | Pure function, 10+ branches | Table-driven: one XCTestCase method per AuthError case + URLError cast paths + fallback. |
| `AppState.saveCloudCredentials` / `deleteCloudCredentials` / `probeCloudConnection` | Test init supports `credentialStore: CredentialStoring? = nil` and `trustPolicy: nil` already (`AppState.swift:267-268`) | Inject `MockCredentialStore` + verify `saveCalls`/`stored` + `cloudAvailable` flips. For `probeCloudConnection` — can't easily mock `SberAuthService` since it's concrete-typed inside the method; consider making AuthService injectable OR just smoke-test the throws behavior with `MockCredentialStore` returning nil → `AuthError.credentialsNotFound`. |
| `connectionState` state-machine transitions | State enum with explicit transitions | Only testable if extracted from the SwiftUI view. If inlined, only UAT. Recommend keeping inline — transitions are simple and covered by integration feedback. |
| `.onChange(of: selection)` revert guard logic | Mostly UI, but `canActivateCloud` boolean is pure | Extract as a computed property on `ProductModeCard`; test via unit-style assertion (give mock AppState → assert value). Limited ROI. |

### Non-TDD (pure SwiftUI rendering — preview-driven only)

- `CloudCredentialsBlock` layout and `SecureField` binding behavior
- `CloudConsentBanner` pre/post-ack visual switching
- Disclosure animation timing and transitions
- Focus initial placement
- `.alert()` dialog triggering

SwiftUI Previews + manual UAT cover these. The codebase has 0 XCUITest files — don't introduce XCUITest for Phase 15 (infrastructure overhead > value).

---

## Threat Model Inputs

Phase 15 handles API credentials and consent — security-sensitive surface. Threats enumerated per D-06, D-07, D-07.1 for the planner's `<threat_model>` block and for security review during plan-check:

### T-01: Credential leakage via accidental logging

**Vector:** Dev adds `Self.logger.debug("saved clientSecret=\(clientSecret)")` or `print()` during debugging; ships to production.
**Impact:** GigaChat API keys exposed in `~/Library/Logs/DiagnosticReports/` or OSLog store. Attacker with local read access sees them. Violates `CredentialStoring` contract (Keychain-only).
**Mitigation:**
- Code-review rule: no `Logger` / `print` / `Self.logger` inside `CloudSettingsDisclosure.swift` that interpolates `clientIdDraft` or `clientSecretDraft` state.
- `@State var clientSecretDraft: String = ""` MUST never be passed to `String(describing:)` or `\(...)` in OSLog.
- UI-SPEC §Accessibility already specifies VoiceOver label «Секретный ключ Client Secret для GigaChat» — does NOT read the value (VoiceOver respects SecureField masking).
- Residual risk: LOW — project convention forbids inline comments/debug prints (CLAUDE.md "минимальные комментарии на русском"), and the closed review (Codex) will flag this.

### T-02: Consent tampering via UserDefaults plist edit

**Vector:** Adversary with write access to `~/Library/Preferences/com.govorun.app.plist` sets `govorun.cloud.consent.acceptedAt` to an arbitrary Date → Cloud mode activates silently next launch without real user consent.
**Impact:** Bypasses the "informed consent before data leaves device" requirement (REQUIREMENTS UI-04).
**Mitigation accepted:** Low sensitivity. Consent is a user-facing UX gate, not a cryptographic attestation of policy consent. UserDefaults is already the durability layer for 13 other settings (`productMode`, `launchAtLogin`, etc.) and their integrity is similarly unverified. Adding HMAC-signed consent records would require a Keychain-stored signing key and is out of scope.
**Document in UAT:** user who tampers their own plist circumvents UX but doesn't bypass TLS/cert pinning (Phase 10 SberTrustPolicy enforces that independently). Sber API itself doesn't need client consent — this flag is a govorun-app gate, not a Sber-side guarantee.

### T-03: Revoke-during-active-dictation race (documented in D-07.1)

**Vector:** User revokes consent while a cloud dictation session is in-flight. `PipelineEngine.stopRecording` already snapshotted `productMode = .cloud` and `_cloudClient` at session start; the upload + chat call continues and lands on Sber servers AFTER the revoke toggle.
**Impact:** One last audio+text payload reaches GigaChat servers after user intent to revoke. Maximum one payload per revoke event.
**Mitigation accepted for v2.0:** per D-07.1.
- Defer-to-idle pattern in `AppState.applyProductMode(.standard)` already exists.
- UI copy MUST be honest: «Отозвать согласие» tooltip/hint explains "вступает в силу со следующей сессии". UI-SPEC line 294 says hint «Отключает облачный режим. Ключи останутся сохранены.» — planner should consider adding timing language here. Planner may propose: «Отключает облачный режим со следующей сессии. Ключи останутся сохранены.» (slightly longer but honest).
- Document in UAT + release notes.
- Out-of-scope for Phase 15: hard-cancelling the in-flight CloudLLMClient task (requires Services/ changes).

### T-04: SecureField state leakage across view instances

**Vector:** SwiftUI re-creates view structs freely; `@State var clientSecretDraft = ""` persists across re-renders of the same identity but could behave unexpectedly during disclosure-open/close cycles.
**Impact:** Stale secret from a previous failed Save attempt lingers in memory; user might see typed characters if disclosure re-opens without reset.
**Mitigation:**
- On successful Save: clear `clientSecretDraft = ""` immediately after `CredentialStore.save` returns success. Client ID can remain (less sensitive; same value gets read back from Keychain anyway).
- On disclosure open (via Cloud-segment click): read stored keys and pre-fill `clientIdDraft` from `credentialStore.get()?.clientId` (so user sees what's stored) but keep `clientSecretDraft = ""` (never echo back the secret — UI-SPEC placeholder behavior).
- On "Очистить" confirmation: reset both drafts to `""` immediately (before the async delete).
- Planner should enumerate these 3 clear points in the plan.

### T-05: Accessibility exposure — VoiceOver reading stored secret

**Vector:** SwiftUI `SecureField` by default masks typed characters as bullets. VoiceOver reads "secure text field" role but MUST NOT speak the value. If developer overrides with a custom `TextField` + `.privacySensitive()` accidentally, or uses a non-SecureField, VoiceOver would speak the value.
**Impact:** Over-the-shoulder exposure if VoiceOver is on during setup.
**Mitigation:**
- Use `SecureField`, not `TextField`. (UI-SPEC line 154 mandates SecureField.)
- UI-SPEC §Accessibility (line 285-295) specifies labels that do NOT include the value itself — only "Идентификатор клиента Client ID для GigaChat" etc.
- No further action needed. SwiftUI SecureField default behavior is correct.
- Residual risk: LOW.

### T-06: Error message leaking internal details

**Vector:** `errorMessage(for: Error)` fallback uses `error.localizedDescription` → might reveal internal URLs, stack fragments, header names, or Client ID substrings.
**Impact:** Information disclosure. Specifically: `AuthError.networkError(String)` carries `error.localizedDescription` from the underlying URLSession error — that's typically opaque ("A network error occurred") but in edge cases URLSession localizes error messages in ways that include URLs.
**Mitigation:**
- UI-SPEC locks ALL error strings in the status table (lines 165-175). The `errorMessage(for:)` helper MUST map to those fixed strings — no `error.localizedDescription` passthrough.
- Fallback branch «Сбой Cloud. Попробуйте позже.» catches everything unmapped.
- Residual risk: LOW provided planner follows the locked copy table.

---

## Validation Architecture

> Required per project config (nyquist_validation not disabled).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest, Swift 5.10 |
| Config file | `Govorun.xctestplan` |
| Baseline count | 1280 tests (Phase 14 shipped) |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SettingsStoreTests -only-testing:GovorunTests/CloudSettingsErrorMessageTests -only-testing:GovorunTests/AppStateCloudShimTests` |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| Estimated runtime | Quick ~15s, Full ~60s |
| XCUITest? | No (0 UI tests in project — VERIFIED via `.planning/codebase/TESTING.md`). Accessibility checks are UAT-only. |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| UI-01 | Keychain save via AppState shim preserves clientId/secret, `cloudAvailable = true` | unit | `xcodebuild test -only-testing:GovorunTests/AppStateCloudShimTests/test_saveCloudCredentials_writesToStore` | ❌ Wave 0 (new file) |
| UI-01 | Keychain delete via AppState shim flips `cloudAvailable = false`, consent untouched | unit | `xcodebuild test -only-testing:GovorunTests/AppStateCloudShimTests/test_deleteCloudCredentials_clearsStoreKeepsConsent` | ❌ Wave 0 (new file) |
| UI-02 | `errorMessage(for: AuthError.credentialsNotFound)` → «Введите ключи API. Без них Cloud недоступен.» | unit | `xcodebuild test -only-testing:GovorunTests/CloudSettingsErrorMessageTests/test_credentialsNotFound` | ❌ Wave 0 (new file) |
| UI-02 | `errorMessage(for: AuthError.invalidResponse(statusCode: 401))` → «Ключи отклонены Сбером. Проверьте Client ID и Secret.» | unit | Same file, `test_invalidResponse_401` | ❌ Wave 0 |
| UI-02 | `errorMessage(for: AuthError.invalidResponse(statusCode: 429))` → «Слишком много запросов. Попробуйте через минуту.» | unit | Same file, `test_invalidResponse_429` | ❌ Wave 0 |
| UI-02 | 500-series → «Ошибка на стороне Сбера. Попробуйте позже.» (test 500, 503, 599) | unit | Same file, `test_invalidResponse_5xx` | ❌ Wave 0 |
| UI-02 | Unknown status/parsing failures → generic fallback | unit | Same file, `test_invalidResponse_other_and_parsingFailed` | ❌ Wave 0 |
| UI-02 | `AuthError.networkError` fallback to generic when cast fails | unit | Same file, `test_networkError_genericFallback` — **see Landmine #3** | ❌ Wave 0 |
| UI-02 | `URLError.timedOut` mapped directly (if thrown to errorMessage before SberAuthService wrapping) | unit | Same file, `test_urlError_timeout` | ❌ Wave 0 |
| UI-03 | `ProductModeCard` picker revert — unit-testable only if `canActivateCloud` extracted. UAT for end-to-end. | UAT | Manual | n/a |
| UI-04 | `SettingsStore.cloudConsentAcceptedAt` round-trip (set Date → get Date → persists across reload) | unit | `xcodebuild test -only-testing:GovorunTests/SettingsStoreTests/test_cloudConsentAcceptedAt_persists` | ✅ extend existing (SettingsStoreTests.swift 29 tests already) |
| UI-04 | `SettingsStore.clearCloudConsent()` sets nil and persists | unit | Same file, `test_clearCloudConsent_removesValue` | ✅ extend |
| UI-04 | `resetToDefaults()` clears cloud consent | unit | Same file, `test_resetToDefaults_clearsCloudConsent` | ✅ extend |

### Sampling Rate

- **Per task commit:** `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/<affected>`
- **Per wave merge:** Full suite (`xcodebuild test ...` without `-only-testing`)
- **Phase gate:** Full suite green + manual UAT checklist (see UI-SPEC §Interaction States rows 1-8) before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `GovorunTests/CloudSettingsErrorMessageTests.swift` — new file, ~9 test methods covering AuthError + URLError branches
- [ ] `GovorunTests/AppStateCloudShimTests.swift` — new file, ~4 test methods covering saveCloudCredentials / deleteCloudCredentials / probeCloudConnection happy + sad paths (using existing MockCredentialStore + test init pattern)
- [ ] Extend `GovorunTests/SettingsStoreTests.swift` — add 3-4 methods for cloudConsentAcceptedAt

No new framework install. No new mocks needed — `MockCredentialStore` (`CredentialStore.swift:112`) and `MockAuthService` (`SberAuthService.swift:160`) exist and are production-grade (thread-safe, configurable).

### Manual-Only Verifications

| Behavior | Why Manual | Instructions |
|----------|-----------|--------------|
| Disclosure animation timing feels right | Animation frames can't be unit-tested; humans judge | Build DMG → Settings → Main → click Cloud segment → observe fade/expand ~0.22s |
| `@FocusState` lands on Client ID on open | XCUITest only; not available | Open disclosure via Cloud segment → cursor caret should be blinking in Client ID field |
| Return key inside SecureField submits Save | XCUITest only | Type keys → press Return (not Tab) → expect Save to fire |
| SwiftUI `.alert()` destructive button renders red on macOS | Visual only | «Удалить» button appears red |
| VoiceOver reads labels without speaking secret value | Accessibility Inspector | Enable VO → tab through fields → verify "Client Secret secure text field" announcement, no value readout |
| `lock.fill` icon placement + Ink 0.25 opacity looks right | Visual | Inspect Cloud segment when `!cloudAvailable` |
| 3-state StatusDot colors (Mist/Sage/Ember) match design-system-v2 | Visual | Walk through connectionState transitions manually |
| Revoke-during-dictation race behavior | Requires live GigaChat + timing | Start dictation → open settings → revoke → confirm last segment still inserts (accepted risk) |

---

## Known Landmines

### Landmine 1: `StatusDot` is 2-state, UI-SPEC requires 3

**Evidence:** `SettingsTheme.swift:122-136`:
```swift
struct StatusDot: View {
    let title: String
    let isActive: Bool
    // Sage-or-Mist dot, Ink-0.5 text. No error/Ember path.
}
```

**Impact:** Compile-time break if planner tries `StatusDot(title:"Подключено", state: .error)` without first extending.

**Resolution:** Planner must EITHER (a) extend `StatusDot` additively with a `State` enum (recommended; ~15-line additive change in SettingsTheme.swift), OR (b) build a local 3-state HStack inside `CloudStatusBlock` without using `StatusDot` (UI-SPEC §Existing Assets Reused line 340 explicitly mentions reusing StatusDot — going local would contradict the contract). Option (a) wins on both design-system compliance and reuse.

Planner's decision scope: this extension is permitted by the pure-UI boundary (SettingsTheme.swift is `Views/`). Grep showed zero existing call sites, so regression risk = 0.

### Landmine 2: `credentialStore` is `private let` in AppState — Views have no access

**Evidence:** `AppState.swift:36: private let credentialStore: CredentialStoring`. Grep confirmed 0 View-layer access today.

**Impact:** `CloudSettingsDisclosure` cannot call `save()` / `delete()` without a bridge. Naïvely making it `public let` leaks the protocol to Views and couples the View to `Security.framework` abstractions (violation of "Services/ not imported from Views/" convention per CLAUDE.md layer rules and `CONVENTIONS.md:63`).

**Resolution:** Add three @MainActor shim methods on AppState (Option A in Existing Patterns §Pattern 8): `saveCloudCredentials`, `deleteCloudCredentials`, `probeCloudConnection`. Views call `appState.saveCloudCredentials(...)` via the existing `@EnvironmentObject private var appState: AppState` binding — fully idiomatic, fully testable via `AppState` test init's `credentialStore: CredentialStoring?` parameter at `AppState.swift:267`.

This is the only case where Phase 15 touches App-tier code outside Views/. Justify in the plan: AppState is the Composition Root — it's where protocol wiring happens. We're adding shim methods, not new protocols.

### Landmine 3: `AuthError.networkError` swallows the original `URLError`

**Evidence:** `SberAuthService.swift:95-99`:
```swift
let (data, response): (Data, URLResponse)
do {
    (data, response) = try await self.httpClient.data(for: request)
} catch {
    throw AuthError.networkError(error.localizedDescription)   // ← String, not URLError
}
```

**Impact:** UI-SPEC line 174 says:
> `error(AuthError.networkError(URLError.notConnectedToInternet))` → «Нет интернета. Cloud временно недоступен.»

This CANNOT be written literally — the associated value is `String`, not `URLError`. CONTEXT §Claude's Discretion line 62 says:
> Parse `URLError` directly inside `errorMessage(for:)` — `if let urlErr = error as? URLError { ... }`.

But by the time `errorMessage(for:)` receives the error from the catch site, it's `AuthError.networkError(String)` — the `if let urlErr = error as? URLError` cast FAILS because the type IS `AuthError`, not `URLError`.

**Two paths to a working URLError mapping:**

**Path A (recommended):** Keep the error mapping "best-effort" — match only the cases the AuthError payload can tell us:
- `AuthError.credentialsNotFound` → specific message
- `AuthError.invalidResponse(401/429/5xx/other)` → specific messages per status
- `AuthError.tokenParsingFailed` → generic fallback
- `AuthError.networkError(let description)` → **generic fallback** «Сервис Сбера недоступен. Попробуйте позже.» (do not parse the String — it is `NSLocalizedDescription` which is ALREADY localized by URLSession, unstable, and could include private info per Threat T-06).

This is simpler and more honest. Document in `errorMessage(for:)` doc-comment the intentional loss of URLError granularity.

**Path B (enrichment):** Expand the catch in `SberAuthService.swift:98` to preserve URLError: `throw AuthError.networkError(urlError: error as? URLError, description: error.localizedDescription)`. But this requires editing `SberAuthService.swift` + propagating through `AuthError`'s Equatable + updating CloudLLMClient call sites. Contradicts pure-UI boundary and CONTEXT D-11.1 "Дифференциация требует расширения AuthError / LLMError (Services-слой) — out of scope."

**Path C (string-sniff — NOT recommended):** Parse the `NSLocalizedDescription` string for substrings like "offline" or "timed out". Fragile, locale-dependent (NSLocalizedDescription is user's locale), rejected.

**Resolution:** Planner MUST choose Path A. The UI-SPEC §State sub-block table rows for `AuthError.networkError(URLError.notConnectedToInternet)` etc. are therefore ASPIRATIONAL — the actual Phase-15 implementation will only map connection-layer subtypes when they propagate to `errorMessage(for:)` through routes that preserve URLError (e.g., probe code that throws URLError directly before wrapping). Since `probeCloudConnection` calls `SberAuthService.getAccessToken()` and catches only `AuthError`, Path A is the honest answer.

**Test plan adjustment:** `test_networkError_genericFallback` must assert that `errorMessage(for: AuthError.networkError("Internet connection appears to be offline"))` returns the GENERIC «Сервис Сбера недоступен. Попробуйте позже.» string — NOT the specific «Нет интернета…» string. Update UI-SPEC or accept test-to-spec delta.

**Action for planner:** Flag this in plan review. Consider whether discussion-phase should relax UI-SPEC state table (acceptable — pre-execute adjustments are permitted) or accept generic mapping for all networkError cases. Low-friction answer: loosen UI-SPEC and ship Path A.

### Landmine 4: `.menu` Picker cannot render inline lock icon per-segment

**Evidence:** `SettingsView.swift:511-517` uses `Picker("", selection: $selection) { ForEach(ProductMode.allCases, ...) { Text(mode.title).tag(mode) } }.pickerStyle(.menu)`. The `Text(mode.title)` is a plain Text — SwiftUI's `.menu` style renders dropdown list items natively with no custom styling hooks per-item (no `.foregroundStyle(...)` on a specific tag, no inline icon).

**Impact:** UI-SPEC §Interaction States row 1 and §Color line 111 say the Cloud segment must render at Ink 0.25 + trailing `lock.fill` icon. With a `.menu` picker, you can render an HStack inside the `Text(...)` label — SwiftUI DOES accept any View in the picker's item label if you use `Label(...)` or an HStack:

```swift
Picker("", selection: $selection) {
    ForEach(ProductMode.allCases, id: \.self) { mode in
        if mode == .cloud, !appState.cloudAvailable {
            HStack(spacing: 4) {
                Text(mode.title)
                Image(systemName: "lock.fill").font(.caption)
            }
            .foregroundStyle(Color.ink.opacity(0.25))
            .tag(mode)
        } else {
            Text(mode.title).tag(mode)
        }
    }
}
.pickerStyle(.menu)
```

**However** — `.menu` style may ignore `.foregroundStyle` on an HStack item; macOS renders menu items with system text color. Testing required. If the tint doesn't apply, the planner may need to fall back to prefixing the title with «🔒 Cloud» as a unicode string, or accept that the dropdown-LIST item doesn't visually distinguish the state (but the PICKER BUTTON showing the current selection does — only Cloud-selected-and-disabled is the broken visual, and that state shouldn't exist because revert fires).

**Actual question:** WHICH visual state needs Ink-0.25 + lock? Only the INACTIVE dropdown entry "Cloud" visible when the menu is OPEN (user clicks chevron → sees three options). The currently-selected picker LABEL (what the user sees before clicking) always matches `selection`, which never rests on `.cloud` when `!cloudAvailable` (revert fires). So:

- **Menu open, dropdown visible:** Cloud item needs lock icon + Ink 0.25 text.
- **Menu closed, picker button showing "Стандарт":** no lock icon needed (selection is on Standard because revert fired).
- **Menu closed, picker button showing "Cloud":** requires `cloudAvailable && cloudConsentAcceptedAt != nil`. No lock needed.

With this framing, the HStack-inside-Picker-item approach works for the dropdown view. Verify in preview that `.foregroundStyle(Color.ink.opacity(0.25))` actually applies to `.menu` pickerStyle items on macOS 14+.

**Planner action:** Test in SwiftUI Preview early. If `.menu` doesn't honor opacity, accept a small fallback (lock icon without opacity change, relying on the icon alone as the signal). Document decision in plan.

### Landmine 5: `@FocusState` + animation timing

**Evidence:** UI-SPEC line 302-303 says "Use `@FocusState` + `.onAppear { focus = .clientId }`" and the disclosure appears via `.easeOut(duration: 0.22)` animation.

**Concern:** On macOS, `.onAppear` fires as soon as the view enters the hierarchy — typically BEFORE the animation completes. Setting focus during an opacity/scale transition can be jarring (caret blinks into a still-invisible field). The first typed character may be dropped if focus fires before NSTextField is fully mounted.

**Mitigation:**
```swift
.onAppear {
    // даём SwiftUI настроиться и NSTextField смонтироваться
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        focus = .clientId
    }
}
```

or use `.task` with a `try? await Task.sleep(nanoseconds: 100_000_000)`. Not critical — try the simple `.onAppear` first, fix if real UAT shows dropped first character.

### Landmine 6: Monospaced font on `SecureField`

**Evidence:** UI-SPEC line 77 mandates `.font(.system(size: 12, weight: .regular, design: .monospaced))` for SecureField input.

**Concern:** On macOS, `SecureField` (backed by `NSSecureTextField`) uses bullet `•` glyphs for masked characters. Whether the `design: .monospaced` modifier applies to the MASKED (bullet) display and not just the visible-character path is implementation-dependent. Most users will never see their real characters (SecureField doesn't offer a reveal toggle), so the monospaced visual is all-bullets. Monospaced bullets render the same as proportional bullets in most fonts since SF Pro's `•` glyph is identical.

**Practical impact:** likely zero — bullets look the same regardless. But don't over-promise "monospaced grid for secret tokens" if the only thing users ever see is dots.

**Mitigation:** Include `.font(.system(size: 12, design: .monospaced))`, accept that it's visually a no-op for masked bullets, move on. UI-SPEC's rationale (line 298) is "consistent with Keychain Access.app" — that's aspirational design, not functional requirement.

### Landmine 7: `.keyboardShortcut(.defaultAction)` scope

**Evidence:** UI-SPEC line 247 says Return submits Save via `.keyboardShortcut(.defaultAction)` on the primary button.

**Concern:** `.defaultAction` is window-scoped. The Settings window already has a primary Picker + other buttons (History's Clear, Snippets Add, etc.). If another button elsewhere in the visible Settings tab also uses `.defaultAction`, Return triggers ambiguously. Grep needed to confirm no other `.defaultAction` is in `GeneralSettingsContent` body.

**Check:** The GeneralSettingsContent view currently renders WorkerStatusLine, KeyRecorderView, ProductModeCard, behavior toggles, reset button. None of those declare `.keyboardShortcut(.defaultAction)` (verified via grep earlier — no hits). So the new Save button can safely own Return inside the Cloud disclosure.

**But:** Return while typing inside a SecureField also fires the default-action button — this is THE desired behavior here. SwiftUI inherits the default action from the enclosing form/window when focused.

Mitigation: no action needed, but don't add a second `.defaultAction` button in the same disclosure (e.g., don't put it on «Принять и включить Cloud» too — the primary action changes with state, and the consent banner renders only after connected so they never co-exist, but verify).

### Landmine 8: Cloud Picker label refresh when `cloudAvailable` changes

**Evidence:** `appState.cloudAvailable` is `@Published`. The `ProductModeCard` reads it to decide whether to lock the Cloud segment. When user saves credentials, AppState's shim flips `cloudAvailable = true` — the Picker should re-render with the Cloud segment un-locked.

**Concern:** SwiftUI Picker items are evaluated inside the `ForEach` closure. If the locked-variant `HStack` branch captures `appState.cloudAvailable` via `@EnvironmentObject`, the Picker re-renders when `cloudAvailable` publishes a change — but menu-item closures sometimes capture values at render-time. Verify in preview that flipping `cloudAvailable` does cause the dropdown to re-render without closing/reopening. Likely fine (SwiftUI diffs and re-renders on @Published), but worth a preview check.

---

## Project Constraints (from CLAUDE.md)

Planner must verify every plan satisfies these:

- Swift 5.10+, macOS 14.0+, Apple Silicon only — Phase 15 adds no version-gated API.
- `@MainActor` only for UI code — `CloudSettingsDisclosure`, all subviews, AppState shim methods need `@MainActor`.
- No force unwrap (`!`) in production code — no `credentialStore.get()!.clientId` etc.
- Strict concurrency `complete` — `MockCredentialStore`, `MockAuthService` are already `Sendable` / `@unchecked Sendable`. New AppState methods should declare `async throws` not completion handlers (per CONVENTIONS §Async/Concurrency).
- No `Co-Authored-By` in commits.
- Russian commit messages: `feat: добавить Cloud Settings disclosure`, `feat: cloud consent в SettingsStore`, `test: errorMessage mapping для AuthError`.
- Comments in Russian, minimal.
- Views/ imports only SwiftUI (not AppKit unless needed for NSAlert — but we're using SwiftUI `.alert()`).
- Errors are typed enums with Equatable — `ConnectionState` enum with `.error(String)` case.
- TDD order: test (red) → code (green) → refactor. Writes SettingsStoreTests expansion first, then SettingsStore accessor; writes CloudSettingsErrorMessageTests first, then helper.
- SwiftFormat enforces `.swiftformat` rules (5.10 target, 3,4 decimal grouping, wrap-collections before-first). Pre-commit hook may convert `//` to `///` — project accepts this (see STATE.md Phase 14-01 note).

---

## Open Questions for Planner (RESOLVED)

All 8 Claude's Discretion items are resolved in UI-SPEC. Three planner questions surfaced and were resolved before planning:

1. **Landmine #3 — URLError mapping.** **RESOLVED: Path B chosen by user 2026-04-20.** Services/ edit approved, CONTEXT §D-11.2 records the override. Implementation lives in Plan 15-02 (AuthError.networkError now carries `URLError?` + description). Plan 15-03 maps `urlError?.code` via switch into the 3 UI-SPEC-locked strings (offline / timeout / generic). Granular UX preserved.

2. **Landmine #2 — AppState shim vs. EnvironmentKey.** **RESOLVED: AppState shim (Option A).** Implementation lives in Plan 15-04 (3 `@MainActor` shim methods: saveCloudCredentials / deleteCloudCredentials / probeCloudConnection). Matches existing `settingsBinding(\.keyPath)` idiom. Views never touch `credentialStore` / `authService` directly.

3. **Landmine #4 — inline lock icon inside `.menu` pickerStyle dropdown.** **RESOLVED: preview-verify + fallback accept-risk.** Plan 15-06 Task 06-02 Edit 3 ships `HStack + lock.fill + .foregroundStyle(Color.ink.opacity(0.25))` and UAT Step (A) verifies in preview. If `.foregroundStyle` does not apply to menu-item composites on macOS 14, fallback is lock icon alone (no opacity change — icon is the visual signal on its own). Documented in Plan 15-06 success criteria.

---

## Assumptions Log

All claims were verified against source code in-session or cited from locked CONTEXT/UI-SPEC. This table is empty.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|

---

## Sources

### Primary (HIGH confidence — direct file inspection in-session)

- `Govorun/Views/SettingsView.swift` — complete 627-line file read; ProductModeCard structure, onChange revert, downloadStatusView all verified
- `Govorun/Views/SettingsTheme.swift` — complete 359-line file read; all tokens, StatusDot, BrandedButton verified
- `Govorun/Storage/SettingsStore.swift` — complete 272-line file read; Keys enum, registerDefaults, migrate pattern verified
- `Govorun/Storage/CredentialStore.swift` — complete 139-line file read; protocol + mock verified
- `Govorun/Services/SberAuthService.swift` — complete 177-line file read; AuthError cases + URLError swallow point verified
- `Govorun/Models/ProductMode.swift` — complete 43-line file read; `.cloud` case with isCloud/usesLLM verified
- `Govorun/App/AppState.swift` — targeted reads (lines 1-100, 200-268, 299-320, 470-500, 670-730) + grep for credentialStore/cloudAvailable/applyProductMode
- `Govorun/Views/HistoryView.swift` — SwiftUI `.alert()` destructive pattern lines 54-61
- `Govorun/Views/SnippetListView.swift` — destructive delete + context menu pattern
- `Govorun/Core/ErrorMessages.swift` — tone-of-voice reference for Russian error copy (lines 1-80)
- `.planning/phases/15-cloud-settings-ui/15-CONTEXT.md` — all D-01..D-11.1 decisions
- `.planning/phases/15-cloud-settings-ui/15-UI-SPEC.md` — approved design contract
- `.planning/phases/13-mode-routing/13-RESEARCH.md` — research format reference + cloud wiring patterns
- `.planning/phases/13-mode-routing/13-VALIDATION.md` — Nyquist validation pattern template
- `.planning/phases/14-pipeline-hardening/14-04-PLAN.md` — most recent completed plan for plan-structure reference
- `.planning/codebase/CONVENTIONS.md` — layer boundaries, async/concurrency, naming
- `.planning/codebase/TESTING.md` — test count baseline (986 Swift tests), XCTest-only, no XCUITest
- `CLAUDE.md` — project-wide mandates

### Secondary (MEDIUM confidence)

- `.planning/REQUIREMENTS.md` — UI-01..UI-04 cross-check
- `.planning/ROADMAP.md` §Phase 15 — goal + success criteria cross-check
- `.planning/STATE.md` — Phase 14 baseline (1280 tests)

### Tertiary (LOW confidence — not consulted, none needed)

- None — internal research only; Swift/SwiftUI APIs referenced are stable and project-local patterns sufficed.

---

## Metadata

**Confidence breakdown:**

- User constraints: HIGH — verbatim copy from CONTEXT.md
- Existing patterns: HIGH — all excerpts quoted from source with file:line
- Implementation sequencing: HIGH — derived from code structure + dependency graph
- Threat model: HIGH — all threats evidenced by file inspection (credentialStore privacy, AuthError wrapping)
- Validation architecture: HIGH — test count and framework verified from TESTING.md; test commands follow Phase 13/14 pattern
- Known landmines: HIGH — all 8 grounded in concrete source evidence, not speculation

**Research date:** 2026-04-20
**Valid until:** 2026-05-20 (pure-UI boundary, no external dependency drift expected; Phase 14 merged 1 day ago so codebase is current)

## RESEARCH COMPLETE
