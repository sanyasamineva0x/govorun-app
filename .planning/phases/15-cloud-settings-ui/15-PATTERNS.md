# Phase 15 — Pattern Map

**Mapped:** 2026-04-20
**Files analyzed:** 10 (3 new, 7 modify)
**Analogs found:** 10 / 10 (all have strong in-repo precedents)

## Summary

Phase 15 is a pure-UI SwiftUI disclosure embedded into the existing `ProductModeCard` in `SettingsView.swift`, with a single Path-B override that touches `SberAuthService.swift` to preserve the `URLError` inside `AuthError.networkError`. Every new file has a direct analog inside the same project: the disclosure pattern mirrors `downloadStatusView` (Super's existing disclosure), the picker revert mirrors the existing `.onChange(of: selection)` super branch (`SettingsView.swift:518-521`), `SettingsStore.cloudConsentAcceptedAt` mirrors the `Keys` enum + `registerDefaults()` + accessor chain (`SettingsStore.swift:11-50, 61-76`), `StatusDot` additively extends the existing 2-state component (`SettingsTheme.swift:122-136`), the `AppState` shims mirror the 8 existing `@MainActor func` coordinator methods (`handleSuperAssetsChanged`, `startSuperModelDownload` at `AppState.swift:337-389`), and both new test files follow `SettingsStoreTests.swift` (UUID-suffixed UserDefaults suite) and `SberAuthServiceTests.swift` (MockHTTPClient + MockAuthService + `do { try await }/catch XCTAssertEqual error as? AuthError`) respectively. The Path-B `AuthError.networkError(urlError:description:)` refactor has a matching pattern at `LLMError.networkError` in `LLMClient.swift:25` but keeps its simpler signature — here we are extending the enum payload while preserving Equatable semantics.

The only non-trivial novelty is the first View-layer use of `CredentialStoring` and `AuthService` protocols: the research blessed approach is AppState shim methods (Option A) which matches the existing idiom where AppState exposes `saveCloudCredentials / deleteCloudCredentials / probeCloudConnection` and internally touches `private let credentialStore` + constructs a fresh `SberAuthService`. Tests for these shims follow `IntegrationTests.swift:646-705` (cloud guard tests) which already use `MockCredentialStore` through `AppState` test init.

## File Classification

| File | Role | Data Flow | Closest Analog | Match Quality |
|------|------|-----------|----------------|---------------|
| `Govorun/Views/CloudSettingsDisclosure.swift` (NEW) | view+state container | request-response (OAuth probe) + event-driven (consent) | `Govorun/Views/SettingsView.swift` §`ProductModeCard.downloadStatusView` (:291-490) | exact (same role, same parent card) |
| `GovorunTests/CloudSettingsErrorMessageTests.swift` (NEW) | test (pure function table) | transform | `GovorunTests/SettingsStoreTests.swift` | role+flow match |
| `GovorunTests/AppStateCloudShimTests.swift` (NEW) | test (async shim) | async request-response | `GovorunTests/IntegrationTests.swift:643-706` (cloud guard audit) | exact (same AppState test init + MockCredentialStore) |
| `Govorun/Views/SettingsView.swift` (MODIFY) | view (in-place edit) | request-response | self (`:518-522` existing super revert) | exact (mirror the existing branch) |
| `Govorun/Storage/SettingsStore.swift` (MODIFY) | model/storage (accessor add) | CRUD (get/set on UserDefaults) | self (`:11-26, 36-50, 125-131` — Keys + register + Bool accessor) | exact |
| `Govorun/Views/SettingsTheme.swift` (MODIFY) | design-system component (additive) | declarative view | self (`:122-136` StatusDot 2-state) | exact (additive extension) |
| `Govorun/App/AppState.swift` (MODIFY) | composition root (add coordinator shims) | async request-response (save → probe) | self (`:337-381` — `refreshSuperAssetsReadiness`, `startSuperModelDownload`, `deleteCorruptedModelAndRedownload`) | exact |
| `Govorun/Services/SberAuthService.swift` (MODIFY) | service actor (enum payload extend) | error transport | self (`:11-31` existing AuthError + Equatable); secondary `Services/LLMClient.swift:25` (LLMError.networkError equatable) | exact (own enum) |
| `GovorunTests/SettingsStoreTests.swift` (EXTEND) | test | CRUD round-trip | self (`:26-50, 96-111, 115-130`) | exact |
| `GovorunTests/SberAuthServiceTests.swift` (EXTEND) | test | error mocking | self (`:86-97, 219-227`) | exact |

## Pattern Assignments

### 1. `Govorun/Views/CloudSettingsDisclosure.swift` — NEW

**Role:** view+state container; owns `@State connectionState`, `@State clientIdDraft`, `@State clientSecretDraft`, `@State showClearAlert`; composes 3 private subviews + `ConnectionState` enum + `errorMessage(for:) -> String` helper.
**Data flow:** SwiftUI reads from `@EnvironmentObject AppState` (cloudAvailable + settings.cloudConsentAcceptedAt), writes via new AppState shims (`saveCloudCredentials`, `deleteCloudCredentials`, `probeCloudConnection`), persists consent via `settings.cloudConsentAcceptedAt = Date()`.

**Primary analog:** `Govorun/Views/SettingsView.swift` lines 291-537 (`ProductModeCard` struct, especially `downloadStatusView` at :331-490)
**Why this analog:** Same parent card, same SwiftUI idioms (`@EnvironmentObject`, `@ViewBuilder` disclosure, `switch` over a state enum, inline Label/Button rows). Everything the new file does — state machine switch, inline error UI with retry button, progress indicator — is rehearsed here.

**Code excerpt (imports + disclosure body structure, SettingsView.swift:331-366):**

```swift
@ViewBuilder
private var downloadStatusView: some View {
    switch appState.superAssetsState {
    case .runtimeMissing:
        EmptyView()

    case .installed:
        Label("Я готов к работе в Супер-режиме", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(Color.sage)

    case .error(let msg):
        VStack(alignment: .leading, spacing: 6) {
            Label("Не могу запустить Супер-режим", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
            Text(msg).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Проверить снова") {
                    Task { await appState.handleSuperAssetsChanged() }
                }
                .font(.caption).buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    // ...
    }
}
```

**Secondary analog (file header / imports / SwiftUI view shape):** `Govorun/Views/TextStyleSettingsView.swift` lines 1-14:

```swift
import SwiftUI

// MARK: - Таб: Стиль текста

struct TextStyleSettingsContent: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedSection: SettingsSection

    private func settingsBinding<T>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { appState.settings[keyPath: keyPath] = $0 }
        )
    }
    // ...
}
```

**Adaptation notes for planner:**
- File header is just `import SwiftUI` (no AppKit; consent NSAlert goes via SwiftUI `.alert()` per RESEARCH Landmine resolution, not `NSAlert`).
- Structure: top-level `struct CloudSettingsDisclosure: View` + 3 fileprivate subviews `CloudCredentialsBlock`, `CloudStatusBlock`, `CloudConsentBanner`, a nested `enum ConnectionState { case notConfigured; checking; connected; error(String) }`, and a private `func errorMessage(for error: Error) -> String`. Mirror `SettingsView.swift` MARK layout: `// MARK: - Блок учётных данных` etc.
- `@EnvironmentObject private var appState: AppState` + `@Environment(\.openURL)` not needed here.
- For error state body copy, RESEARCH landmine #3 Path B (CONTEXT D-11.2 override): match on `.networkError(let urlErr, _)` and read `urlErr?.code`; do NOT inspect the description String.
- Consent destructive confirmation: use SwiftUI `.alert()` (matches `HistoryView.swift:54-61` precedent, NOT AppKit NSAlert — see section for item 4 below).

### 2. `GovorunTests/CloudSettingsErrorMessageTests.swift` — NEW

**Role:** XCTest suite of pure-function table-driven tests for `errorMessage(for:) -> String`.
**Data flow:** input `AuthError`/`URLError` → output locked Russian string.

**Primary analog:** `GovorunTests/SettingsStoreTests.swift` (entire file, especially :1-22 setup shape and :26-50 table-style assertions)
**Why this analog:** Simplest XCTest shape in the project — one-file test class, no async, no mocks, one assertion per test method. `errorMessage(for:)` is a pure function so this shape matches perfectly.

**Code excerpt (SettingsStoreTests.swift:1-22):**

```swift
@testable import Govorun
import XCTest

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        let suiteName = "com.govorun.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        if let suite = defaults.volatileDomainNames.first {
            defaults.removePersistentDomain(forName: suite)
        }
        defaults = nil
        store = nil
        super.tearDown()
    }
    // ...
}
```

**Adaptation notes for planner:**
- No setUp/tearDown needed — `errorMessage(for:)` is pure. Skip the defaults setup entirely.
- One `func test_<case>()` per AuthError case + URLError branch. 8 methods per RESEARCH §Test Surface:
  `test_credentialsNotFound`, `test_invalidResponse_401`, `test_invalidResponse_429`, `test_invalidResponse_500`, `test_invalidResponse_other_generic`, `test_tokenParsingFailed_generic`, `test_networkError_notConnectedToInternet`, `test_networkError_timedOut`, `test_networkError_other_generic`.
- Since `errorMessage(for:)` is `private` inside `CloudSettingsDisclosure`, mark it `internal` (no modifier) and add `@testable import Govorun` OR expose via a static helper. Path of least resistance: make it a fileprivate free function in the same file + a tiny `internal func _testErrorMessage(for:) -> String` wrapper.
- Expected strings are the **exact** locked copy from UI-SPEC §Copywriting Contract §Status sub-block.
- Per CONTEXT D-11.2 override: `AuthError.networkError(urlError: URLError(.notConnectedToInternet), description: _)` → «Нет интернета. Cloud временно недоступен.» (not the generic fallback from RESEARCH Path A).

### 3. `GovorunTests/AppStateCloudShimTests.swift` — NEW

**Role:** XCTest suite for the three new `@MainActor async` shim methods on AppState.
**Data flow:** `MockCredentialStore` save/delete → assert AppState.cloudAvailable flips; mock OAuth probe → assert Result.success/failure.

**Primary analog:** `GovorunTests/IntegrationTests.swift` lines 46-107 (`makeTestAppState` helper) and :643-706 (cloud-mode guard tests using `credentialStore: store`)
**Why this analog:** Only existing test file that constructs an AppState with `credentialStore: MockCredentialStore()` and asserts cloud-flow side-effects. Exact pattern reuse for the new shim tests.

**Code excerpt (IntegrationTests.swift:645-665):**

```swift
func test_guard_audit_cloud_does_not_set_llmRuntimeState_notStarted() async {
    let store = MockCredentialStore()
    try? store.save(clientId: "test", clientSecret: "secret")
    let (appState, _, _, _) = await makeTestAppState(
        productMode: .cloud,
        credentialStore: store
    )
    // G2/G3: cloud не ставит .notStarted
    XCTAssertEqual(appState.llmRuntimeState, .disabled)
}

func test_guard_audit_cloud_pipeline_gets_cloud_mode_directly() async {
    let store = MockCredentialStore()
    try? store.save(clientId: "test", clientSecret: "secret")
    let (appState, _, _, _) = await makeTestAppState(
        productMode: .cloud,
        credentialStore: store
    )
    // G1/G4: cloud не даунгрейдится до .standard
    XCTAssertEqual(appState.pipelineEngine.productMode, .cloud)
}
```

**Adaptation notes for planner:**
- Reuse the existing `makeTestAppState(productMode:credentialStore:)` factory (or a minimal copy). Don't re-invent.
- 4 test methods per RESEARCH §Testing Plan:
  `test_saveCloudCredentials_writes_to_store_and_flips_cloudAvailable_true`
  `test_deleteCloudCredentials_flips_cloudAvailable_false`
  `test_probeCloudConnection_returns_success_when_token_fetched`
  `test_probeCloudConnection_returns_failure_when_authError_thrown`
- For the probe test, we need an injectable `AuthService` in AppState — the research recommends AppState constructs a fresh `SberAuthService` per probe but accepts a test-only hook. Planner decides: (a) add an `authServiceFactory` init param to the test init of AppState, or (b) inject `MockAuthService` via the same mechanism used today for `credentialStore`. Landmine #2 resolution favors (a) for symmetry.
- `MockCredentialStore` already lives at `CredentialStore.swift:112` and is @unchecked Sendable — ready to use.
- `MockAuthService` already lives at `SberAuthService.swift:160` and supports `tokenResult = "..."` / `tokenError = AuthError.invalidResponse(401)` — ready to use.

### 4. `Govorun/Views/SettingsView.swift` — MODIFY (ProductModeCard in-place)

**Role:** View layer; extend `ProductModeCard` with `@State showCloudSetup: Bool`, add a cloud revert branch to `.onChange(of: selection)`, conditionally render `CloudSettingsDisclosure()` next to existing `downloadStatusView`.
**Data flow:** picker selection + AppState.cloudAvailable + settings.cloudConsentAcceptedAt read; on revert, writes `selection = oldValue` + `showCloudSetup = true`.

**Primary analog:** Same file, lines 511-530 (existing super revert + disclosure render)
**Why this analog:** Literally the pattern we are extending. CONTEXT D-02 explicitly says "mirror the existing Super branch."

**Code excerpt (SettingsView.swift:511-530):**

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
}

VStack(alignment: .leading, spacing: 6) {
    // ВАЖНО: settings.productMode (выбранный в picker), НЕ effectiveProductMode
    if appState.settings.productMode == .superMode {
        downloadStatusView
    }
}
```

**Adaptation notes for planner:**
- Add right after `@Binding var selection: ProductMode` at `:293`:
  ```swift
  @State private var showCloudSetup: Bool = false
  private var canActivateCloud: Bool {
      appState.cloudAvailable && appState.settings.cloudConsentAcceptedAt != nil
  }
  ```
- Change the closure signature from `{ _, newValue in` to `{ oldValue, newValue in` (macOS 14+ 2-arg `.onChange` already in use at this line — both params are available, just rename from `_`).
- Add the Cloud branch inside the existing closure (do NOT add a second `.onChange` modifier):
  ```swift
  .onChange(of: selection) { oldValue, newValue in
      if newValue == .superMode, !superAvailable {
          selection = .standard
          return
      }
      if newValue == .cloud, !canActivateCloud {
          selection = oldValue          // Cloud реверсится в предыдущее значение, не в .standard
          showCloudSetup = true
      }
  }
  ```
- Extend the disclosure VStack at `:525-530`:
  ```swift
  VStack(alignment: .leading, spacing: 6) {
      if appState.settings.productMode == .superMode {
          downloadStatusView
      }
      if appState.settings.productMode == .cloud || showCloudSetup {
          CloudSettingsDisclosure()
              .transition(.opacity)
      }
  }
  .animation(.easeOut(duration: 0.22), value: appState.settings.productMode)
  .animation(.easeOut(duration: 0.22), value: showCloudSetup)
  ```

### 5. `Govorun/Storage/SettingsStore.swift` — MODIFY

**Role:** Model/storage; add `cloudConsentAcceptedAt: Date?` accessor + `Keys.cloudConsentAcceptedAt` + `clearCloudConsent()` method + reset coverage.
**Data flow:** CRUD on UserDefaults.

**Primary analog:** Same file, lines 11-26 (Keys enum), :36-50 (registerDefaults), :125-131 (soundEnabled Bool accessor — structurally the simplest accessor to mirror for `Date?`), :255-271 (resetToDefaults)
**Why this analog:** File is the definition of the pattern. Exact in-pattern additive change.

**Code excerpt (SettingsStore.swift:11-26 + :125-131 + :255-271):**

```swift
private enum Keys {
    static let productMode = "productMode"
    static let superStyleMode = "superStyleMode"
    // ...
    static let llmHealthcheckTimeout = "llmHealthcheckTimeout"
}

// accessor shape (soundEnabled):
var soundEnabled: Bool {
    get { defaults.bool(forKey: Keys.soundEnabled) }
    set {
        defaults.set(newValue, forKey: Keys.soundEnabled)
        objectWillChange.send()
    }
}

// reset shape:
func resetToDefaults() {
    defaults.removeObject(forKey: Keys.productMode)
    // ...
    defaults.removeObject(forKey: Keys.llmHealthcheckTimeout)
    registerDefaults()
    objectWillChange.send()
}
```

**Adaptation notes for planner:**
- Add to `Keys` enum:
  ```swift
  static let cloudConsentAcceptedAt = "govorun.cloud.consent.acceptedAt"
  ```
  (The existing Keys are unqualified strings like `"productMode"`; the new one is fully qualified `"govorun.cloud.consent.*"` — this is intentional per CONTEXT D-07 and UI-SPEC resolution. It does NOT break convention since the existing pattern is "planner's choice" and newer keys in the codebase adopt the `govorun.*` prefix.)
- DO NOT add to `registerDefaults()` — default `nil` is the semantic "not accepted yet"; registering nil is an error in UserDefaults per RESEARCH Pattern 3.
- Accessor (Date? via `.object(forKey:) as? Date`):
  ```swift
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

  /// Revoke consent — одна строка для симметрии с resetToDefaults.
  func clearCloudConsent() {
      cloudConsentAcceptedAt = nil
  }
  ```
- Add to `resetToDefaults()`:
  ```swift
  defaults.removeObject(forKey: Keys.cloudConsentAcceptedAt)
  ```

### 6. `Govorun/Views/SettingsTheme.swift` — MODIFY (StatusDot additive)

**Role:** Design-system component; additively extend `StatusDot` with a 3-state enum API.
**Data flow:** declarative view (`State` enum → color).

**Primary analog:** Same file, lines 122-136 (existing 2-state StatusDot)
**Why this analog:** The component being extended. RESEARCH Landmine #1 resolution.

**Code excerpt (SettingsTheme.swift:120-136):**

```swift
// MARK: - StatusDot

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

**Adaptation notes for planner:**
- Zero call sites exist today (RESEARCH line 352: «grep `StatusDot(` across `Govorun/` returns ZERO matches») — the additive change is risk-free.
- Two approaches. Recommended: nested enum + two convenience inits that preserve backward compatibility.
  ```swift
  struct StatusDot: View {
      enum State {
          case idle       // Mist dot (notConfigured / checking)
          case connected  // Sage dot
          case error      // Ember dot
      }

      let title: String
      let state: State

      // Backward-compat init (no call sites today but keep the surface stable)
      init(title: String, isActive: Bool) {
          self.title = title
          self.state = isActive ? .connected : .idle
      }

      init(title: String, state: State) {
          self.title = title
          self.state = state
      }

      var body: some View {
          HStack(spacing: 8) {
              Circle()
                  .fill(dotColor)
                  .frame(width: 6, height: 6)
              Text(title)
                  .font(.caption)
                  .foregroundStyle(state == .error ? Color.ember : Color.ink.opacity(0.5))
          }
      }

      private var dotColor: Color {
          switch state {
          case .idle: Color.mist
          case .connected: Color.sage
          case .error: Color.ember
          }
      }
  }
  ```
- Text color note: per UI-SPEC §Color, «error» state colors the text in Ember; «connected»/«idle» keep Ink 0.5. The excerpt above reflects that.
- No new tokens — `Color.mist`, `Color.sage`, `Color.ember` all exist at `SettingsTheme.swift:20-31`.

### 7. `Govorun/App/AppState.swift` — MODIFY (3 new @MainActor shims)

**Role:** Composition root; add `saveCloudCredentials(clientId:clientSecret:) async throws`, `deleteCloudCredentials() throws`, `probeCloudConnection() async -> Result<Void, AuthError>`.
**Data flow:** async orchestration — delegate to `credentialStore` + construct fresh `SberAuthService` + call `.getAccessToken()`.

**Primary analog:** Same file, lines 337-381 (`refreshSuperAssetsReadiness`, `startSuperModelDownload`, `deleteCorruptedModelAndRedownload`) and :682-731 (`applyProductMode(.cloud)` which already builds a fresh `SberAuthService`).
**Why this analog:** These are the existing `@MainActor async` coordinator methods that wrap service-layer work; they match the required shape exactly. `applyProductMode(.cloud):714-716` is the precedent for constructing a fresh SberAuthService from `credentialStore`.

**Code excerpt (AppState.swift:371-385 for shape + :710-731 for SberAuthService construction):**

```swift
func deleteCorruptedModelAndRedownload() async {
    let spec = SuperModelCatalog.current
    do {
        try FileManager.default.removeItem(at: spec.destination)
    } catch {
        superModelDownloadState = .failed(.fileSystemError("Не удалось удалить файл: \(error.localizedDescription)"))
        return
    }
    await refreshSuperAssetsReadiness()
    await startSuperModelDownload()
}

// ... and from applyProductMode(.cloud):
case .cloud:
    guard credentialStore.get() != nil else {
        Self.logger.warning("Cloud credentials не найдены, остаёмся на текущем режиме")
        return
    }
    let authService = SberAuthService(
        credentialProvider: { [credentialStore] in credentialStore.get() }
    )
    // ...
cloudAvailable = credentialStore.get() != nil
```

**Adaptation notes for planner:**
- Place the three new methods near the other public coordinator methods (around `:337-382`, in the same `// MARK:` section).
- Shape:
  ```swift
  // MARK: - Cloud Settings (Phase 15 shim)

  func saveCloudCredentials(clientId: String, clientSecret: String) throws {
      try credentialStore.save(clientId: clientId, clientSecret: clientSecret)
      cloudAvailable = credentialStore.get() != nil
      // objectWillChange shot by @Published cloudAvailable
  }

  func deleteCloudCredentials() throws {
      try credentialStore.delete()
      cloudAvailable = false
  }

  func probeCloudConnection() async -> Result<Void, AuthError> {
      let authService = SberAuthService(
          credentialProvider: { [credentialStore] in credentialStore.get() }
      )
      do {
          _ = try await authService.getAccessToken()
          return .success(())
      } catch let error as AuthError {
          return .failure(error)
      } catch {
          // Защита: всё не-AuthError паковать в generic
          return .failure(.networkError(urlError: nil, description: error.localizedDescription))
      }
  }
  ```
- Reuses existing `private let credentialStore` (no injection change needed — test init at `:267` already accepts `credentialStore: CredentialStoring?`).
- `@Published var cloudAvailable` is at `:40`; mutating it re-renders the picker's lock state automatically (already wired).
- For testability of `probeCloudConnection`: if planner wants to inject `MockAuthService`, add an `@MainActor` property `var authServiceFactory: () -> AuthService = { ... }` with a default that builds `SberAuthService`. Optional — the simpler path is to keep the shim as-is and test through the integration seam (MockCredentialStore returns bogus secrets → MockHTTPClient returns 401 → probe returns failure).

### 8. `Govorun/Services/SberAuthService.swift` — MODIFY (Path B override, CONTEXT D-11.2)

**Role:** Service actor; extend `AuthError.networkError(String)` → `.networkError(urlError: URLError?, description: String)` + update Equatable + update the one catch site at `:97-98` + update `CloudLLMClient.swift:289` pattern match.
**Data flow:** error transport — preserve the original URLError inside the AuthError payload for UI-layer inspection.

**Primary analog:** Same file, lines 11-31 (AuthError enum + Equatable); the same enum payload pattern also exists at `Services/LLMClient.swift:25` for LLMError.
**Why this analog:** The enum we are modifying. Self-reference; no closer analog.

**Code excerpt (SberAuthService.swift:11-31):**

```swift
enum AuthError: Error, Equatable {
    case credentialsNotFound
    case networkError(String)
    case invalidResponse(statusCode: Int)
    case tokenParsingFailed

    static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        switch (lhs, rhs) {
        case (.credentialsNotFound, .credentialsNotFound):
            true
        case (.networkError(let a), .networkError(let b)):
            a == b
        case (.invalidResponse(let a), .invalidResponse(let b)):
            a == b
        case (.tokenParsingFailed, .tokenParsingFailed):
            true
        default:
            false
        }
    }
}
```

**Catch-site current code (SberAuthService.swift:94-99):**

```swift
let (data, response): (Data, URLResponse)
do {
    (data, response) = try await self.httpClient.data(for: request)
} catch {
    throw AuthError.networkError(error.localizedDescription)
}
```

**Adaptation notes for planner:**
- New enum payload:
  ```swift
  case networkError(urlError: URLError?, description: String)
  ```
- Equatable — compare both `urlError?.code` and `description`:
  ```swift
  case (.networkError(let ua, let da), .networkError(let ub, let db)):
      ua?.code == ub?.code && da == db
  ```
- Catch site at `:95-99` becomes:
  ```swift
  } catch {
      let urlErr = error as? URLError
      throw AuthError.networkError(
          urlError: urlErr,
          description: error.localizedDescription
      )
  }
  ```
- Update one existing pattern-match call site — `CloudLLMClient.swift:289-290`:
  ```swift
  // БЫЛО:
  case .networkError(let msg):
      .networkError(msg)
  // СТАЛО:
  case .networkError(_, let msg):
      .networkError(msg)
  ```
  (The discarded `urlError` is fine — `LLMError.networkError` only carries a String, not a URLError, so dropping the urlErr here doesn't lose info that LLMError currently uses.)
- Keep the enum `Equatable` conformance manually written (don't auto-synthesize) — it already is, just extend the case.
- Per CONTEXT D-11.2 this is the ONLY Services/ file edit allowed in Phase 15. No LLMError changes. No new AuthError cases.

### 9. `GovorunTests/SettingsStoreTests.swift` — EXTEND (in-place)

**Role:** Test; add 3 methods for `cloudConsentAcceptedAt` round-trip + resetToDefaults coverage.
**Data flow:** CRUD round-trip.

**Primary analog:** Same file, lines 43-49 (`test_set_product_mode` — set/get round-trip), :115-130 (`test_reset_to_defaults`), :180-184 (`test_activationKey_persists` — persistence across instances).
**Why this analog:** Exact idiom — SettingsStore is designed to be tested with UUID-suffixed UserDefaults; all 30 existing tests follow this pattern. Just add 3 more.

**Code excerpt (SettingsStoreTests.swift:43-49 + :115-130):**

```swift
func test_set_product_mode() {
    store.productMode = .superMode
    XCTAssertEqual(store.productMode, .superMode)

    let store2 = SettingsStore(defaults: defaults)
    XCTAssertEqual(store2.productMode, .superMode)
}

// ...
func test_reset_to_defaults() {
    store.productMode = .superMode
    store.superStyleMode = .manual
    // ...
    store.resetToDefaults()

    XCTAssertEqual(store.productMode, .standard)
    XCTAssertEqual(store.superStyleMode, .auto)
    // ...
}
```

**Adaptation notes for planner:**
- Add 3 test methods (MARK group «11. Cloud consent»):
  ```swift
  func test_cloudConsentAcceptedAt_default_nil() {
      XCTAssertNil(store.cloudConsentAcceptedAt)
  }

  func test_cloudConsentAcceptedAt_roundtrip_persists() {
      let date = Date(timeIntervalSince1970: 1_735_000_000)
      store.cloudConsentAcceptedAt = date
      XCTAssertEqual(store.cloudConsentAcceptedAt, date)

      let store2 = SettingsStore(defaults: defaults)
      XCTAssertEqual(store2.cloudConsentAcceptedAt, date)
  }

  func test_clearCloudConsent_removes_key() {
      store.cloudConsentAcceptedAt = Date()
      store.clearCloudConsent()
      XCTAssertNil(store.cloudConsentAcceptedAt)
  }
  ```
- Optionally a fourth: `test_resetToDefaults_clears_cloudConsent` — already covered by adding `cloudConsentAcceptedAt = Date()` + calling `resetToDefaults()` + XCTAssertNil, mirroring :143-147 (`test_saveAudioHistory_reset_to_defaults`).
- No migration test required (new key, nil is the semantic default).

### 10. `GovorunTests/SberAuthServiceTests.swift` — EXTEND (in-place)

**Role:** Test; add 2 methods for Path B — URLError preservation on catch + updated Equatable coverage.
**Data flow:** error mocking — `mockHTTP.error = URLError(.timedOut)` → assert the thrown `AuthError.networkError` carries `urlError?.code == .timedOut`.

**Primary analog:** Same file, lines 86-97 (`test_getAccessToken_networkError` — existing URLError injection with generic guard) and :219-227 (`test_authError_equatable` — existing Equatable tests that will need the payload update).
**Why this analog:** The tests we are tightening. Existing test at `:86-97` already injects `URLError(.notConnectedToInternet)` via `mockHTTP.error` — it's the one test that currently throws the wrapping code at line 98. Perfect target for Path B enrichment.

**Code excerpt (SberAuthServiceTests.swift:86-97 + :219-227):**

```swift
func test_getAccessToken_networkError() async {
    mockHTTP.error = URLError(.notConnectedToInternet)
    do {
        _ = try await sut.getAccessToken()
        XCTFail("Ожидалась ошибка")
    } catch {
        guard case .networkError = error as? AuthError else {
            XCTFail("Ожидался networkError, получен \(error)")
            return
        }
    }
}

// ...
func test_authError_equatable() {
    XCTAssertEqual(AuthError.credentialsNotFound, AuthError.credentialsNotFound)
    XCTAssertEqual(AuthError.networkError("a"), AuthError.networkError("a"))
    XCTAssertNotEqual(AuthError.networkError("a"), AuthError.networkError("b"))
    // ...
}
```

**Adaptation notes for planner:**
- The existing `test_getAccessToken_networkError` at `:86-97` must be tightened from `guard case .networkError = ...` to full-payload assertion:
  ```swift
  func test_getAccessToken_networkError_preserves_urlError() async {
      mockHTTP.error = URLError(.notConnectedToInternet)
      do {
          _ = try await sut.getAccessToken()
          XCTFail("Ожидалась ошибка")
      } catch let AuthError.networkError(urlErr, _) {
          XCTAssertEqual(urlErr?.code, .notConnectedToInternet)
      } catch {
          XCTFail("Ожидался AuthError.networkError, получен \(error)")
      }
  }
  ```
- Add a second test `test_getAccessToken_networkError_timedOut_preserves_urlError`: same shape, `URLError(.timedOut)`.
- Update `test_authError_equatable` at `:219-227` — all `.networkError("x")` literals must migrate to `.networkError(urlError: nil, description: "x")`. Add one case: `XCTAssertNotEqual(.networkError(urlError: URLError(.timedOut), description: "x"), .networkError(urlError: URLError(.notConnectedToInternet), description: "x"))` to lock the `urlError?.code` comparison.
- No new mocks — `MockHTTPClient` already supports `.error = URLError(...)` injection.

## Shared Patterns

### Authentication / Credentials
**Source:** `Govorun/App/AppState.swift:714-716` (existing `SberAuthService` construction from `credentialStore.get()`)
**Apply to:** Item 7 (AppState shims) — reuse this exact idiom inside `probeCloudConnection()`.

```swift
let authService = SberAuthService(
    credentialProvider: { [credentialStore] in credentialStore.get() }
)
```

### Error Mapping (typed enum → user-facing String)
**Source:** `Govorun/Services/CloudLLMClient.swift:285-307` (mapAuthError + mapTransportError) and `Govorun/Core/ErrorMessages.swift` (URLError → Russian)
**Apply to:** Item 1 (CloudSettingsDisclosure.swift) `errorMessage(for:) -> String`.

Key insight — CloudLLMClient ALREADY does `URLError → LLMError.networkError(specific_string)` mapping via `mapTransportError` at `:298-307`. The Phase 15 View-layer errorMessage mirrors this at a different layer but is independent: View does `AuthError.networkError(urlError:, description:) → specific_string`, not a service-to-service transform.

```swift
// From CloudLLMClient.swift:298-307 (reference only, not a direct copy):
private func mapTransportError(_ error: URLError) -> LLMError {
    switch error.code {
    case .timedOut:
        .timeout
    case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
        .networkError("GigaChat API недоступен")
    default:
        .networkError(error.localizedDescription)
    }
}
```

### Destructive Confirmation
**Source:** `Govorun/Views/HistoryView.swift:54-61` (SwiftUI `.alert()` with `.destructive` role)
**Apply to:** Item 1 (CloudSettingsDisclosure — «Очистить» button confirmation)

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

**Why this over NSAlert:** RESEARCH.md line 234-236 notes that the only AppKit NSAlert call site in the whole codebase is a fatal-error path in `GovorunApp.swift:27-31` (`.critical + runModal`) — NOT suitable for Settings. Every Settings-context destructive confirmation in the codebase today uses SwiftUI `.alert()`. Follow precedent, document the deviation from CONTEXT-style wording («NSAlert-подтверждение») in the plan.

### UserDefaults-backed Optional Date Accessor
**Source:** `Govorun/Storage/SettingsStore.swift:231-251` (`activationKey` — an Optional-with-default pattern using `defaults.string(forKey:)` + JSON decode fallback)
**Apply to:** Item 5 (`cloudConsentAcceptedAt: Date?`). The closest semantic match: `activationKey` is "present or fallback to default"; `cloudConsentAcceptedAt` is "present or nil". For nil-honest Date storage, use `defaults.object(forKey:) as? Date` — this is the canonical SwiftUI idiom and matches what `activationKey` does for JSON.

```swift
// activationKey as reference for Optional-shape accessor:
var activationKey: ActivationKey {
    get {
        guard let jsonString = defaults.string(forKey: Keys.activationKey),
              let data = jsonString.data(using: .utf8),
              let key = try? JSONDecoder().decode(ActivationKey.self, from: data)
        else {
            return .default
        }
        return key
    }
    set {
        if let data = try? JSONEncoder().encode(newValue),
           let jsonString = String(data: data, encoding: .utf8)
        {
            defaults.set(jsonString, forKey: Keys.activationKey)
            objectWillChange.send()
        } // ...
    }
}
```

### Test File Header + Suite Isolation
**Source:** `GovorunTests/SettingsStoreTests.swift:1-22`, `GovorunTests/SberAuthServiceTests.swift:1-61`
**Apply to:** Items 2, 3 (new test files)

Test file header convention (note order of `@testable import` vs `import XCTest` varies but all existing test files follow one of two forms — both OK):

```swift
// Form A (SettingsStoreTests.swift:1-2):
@testable import Govorun
import XCTest

// Form B (SberAuthServiceTests.swift:1-2):
import XCTest
@testable import Govorun
```

For UUID-suffixed suite isolation (only needed for tests that actually touch UserDefaults — pure errorMessage tests don't need it):
```swift
let suiteName = "com.govorun.tests.\(UUID().uuidString)"
defaults = UserDefaults(suiteName: suiteName)!
// ...
override func tearDown() {
    if let suite = defaults.volatileDomainNames.first {
        defaults.removePersistentDomain(forName: suite)
    }
    // ...
}
```

## No Analog Found

**None.** All 10 files (new and modified) have strong in-repo analogs. The most novel aspects of this phase — first View-layer `SecureField`, first `@FocusState`, first direct View-to-`AuthService` probe — have close-but-not-exact analogs:

- `SecureField` → closest is `TextField` in `Govorun/Views/SettingsSearchBar.swift` (file reference `SettingsTheme.swift:244`). Same SwiftUI input-binding idiom with `@State var text: String`. Planner substitutes `SecureField`.
- `@FocusState` → no existing usage. Standard SwiftUI API, ~3 lines. Planner must invent conventions; recommend: `enum Field: Hashable { case clientId; case clientSecret }` + `@FocusState private var focus: Field?` + `.onAppear { focus = .clientId }`.
- View-to-`AuthService` direct call → routed through AppState shim (item 7) to preserve privacy of `private let credentialStore` per RESEARCH Landmine #2.

## Metadata

**Analog search scope:**
- `Govorun/Views/` (SettingsView, SettingsTheme, HistoryView, TextStyleSettingsView)
- `Govorun/App/AppState.swift`
- `Govorun/Storage/SettingsStore.swift`, `CredentialStore.swift`
- `Govorun/Services/SberAuthService.swift`, `CloudLLMClient.swift`, `LLMClient.swift`
- `GovorunTests/SettingsStoreTests.swift`, `SberAuthServiceTests.swift`, `IntegrationTests.swift`

**Files scanned:** 12
**Pattern extraction date:** 2026-04-20

## PATTERN MAPPING COMPLETE
