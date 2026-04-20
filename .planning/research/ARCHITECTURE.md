# Architecture Research: GigaChat Max API Integration

**Domain:** Cloud LLM mode for macOS speech-to-text app
**Researched:** 2026-04-06
**Confidence:** HIGH

## Existing Architecture Snapshot

```
Activation key -> AudioCapture -> STT (GigaAM) ->
-> DictionaryStore -> SnippetEngine ->
-> DeterministicNormalizer ->
-> [Super?] -> LocalLLMClient (llama-server :8080) -> NormalizationGate ->
-> ListFormatter -> TextInserter
```

Key abstractions already in place:

| Abstraction | Location | Role |
|-------------|----------|------|
| `LLMClient` protocol | Services/LLMClient.swift | `normalize(_:superStyle:hints:) async throws -> String` |
| `ProductMode` enum | Models/ProductMode.swift | `.standard`, `.superMode` with `usesLLM: Bool` |
| `LocalLLMClient` | Services/LocalLLMClient.swift | HTTP to llama-server, healthcheck, retry |
| `NormalizationGate` | Core/NormalizationGate.swift | Edit distance, protected tokens, contract-aware |
| `SuperTextStyle` | Models/SuperTextStyle.swift | `.relaxed`/`.normal`/`.formal` with `systemPrompt()` |
| `NormalizationHints` | Models/NormalizationHints.swift | personalDictionary, appName, currentDate, snippetContext |
| `PipelineEngine` | Core/PipelineEngine.swift | Orchestrates full pipeline, `updateLLMClient()` hot-swap |
| `NetworkMonitor` | Core/NetworkMonitor.swift | NWPathMonitor, `isConnected` @Published |

## System Overview -- Cloud Integration

```
+---------------------------------------------------------------------+
|                          UI Layer                                    |
|  +---------------------+  +-------------------+  +---------------+  |
|  | CloudSettingsView   |  | ProductModePicker |  | StatusBar     |  |
|  | (clientId, secret,  |  | .standard         |  | mode indicator|  |
|  |  connection status) |  | .superMode        |  |               |  |
|  |                     |  | .cloud            |  |               |  |
|  +--------+------------+  +--------+----------+  +-------+-------+  |
|           |                        |                      |          |
+-----------|------------------------|----------------------|----------+
|           v                        v                      v          |
|                        App Layer (AppState)                          |
|  +----------------------------------------------------------------+ |
|  | currentProductMode -> applyProductMode()                        | |
|  |   .cloud -> wire CloudLLMClient + start SberAuthService         | |
|  |   .superMode -> wire LocalLLMClient + start LLMRuntimeManager  | |
|  |   .standard -> no LLM                                          | |
|  +----------------------------------------------------------------+ |
|                                                                      |
+----------------------------------------------------------------------+
|                       Services Layer                                  |
|                                                                       |
|  +-------------------+    +-------------------+    +--------------+   |
|  | CloudLLMClient    |    | SberAuthService   |    |CredentialStore|  |
|  | (LLMClient)       |<---| (AuthService)     |<---| (Keychain)   |  |
|  | GigaChat Max API  |    | OAuth token cache |    | clientId     |  |
|  | retry + timeout   |    | 5min refresh      |    | clientSecret |  |
|  +--------+----------+    +-------------------+    +--------------+   |
|           |                                                           |
|           | (conforms to LLMClient)                                   |
|           v                                                           |
|  +----------------------------------------------------------------+  |
|  |              PipelineEngine (unchanged core)                    |  |
|  |  _llmClient: LLMClient  <-- hot-swapped per ProductMode        |  |
|  |  _productMode: ProductMode                                      |  |
|  |  _superStyle: SuperTextStyle?                                   |  |
|  |                                                                 |  |
|  |  STT -> DeterministicNormalizer -> [LLM?] -> Gate -> Output     |  |
|  +----------------------------------------------------------------+  |
|                                                                       |
+-----------------------------------------------------------------------+
|                        Models Layer                                    |
|  +---------------+  +------------------+  +------------------------+  |
|  | ProductMode   |  | SuperTextStyle   |  | CloudLLMConfiguration  |  |
|  | .standard     |  | .relaxed         |  | baseURL, model,        |  |
|  | .superMode    |  | .normal          |  | temperature, timeout   |  |
|  | .cloud (NEW)  |  | .formal          |  |                        |  |
|  +---------------+  +------------------+  +------------------------+  |
|  +------------------+  +-----------------+                             |
|  | LLMError (reuse) |  | AuthError       |                            |
|  +------------------+  +-----------------+                             |
+------------------------------------------------------------------------+
```

## New Types Required

### 1. ProductMode Extension

```swift
// Models/ProductMode.swift -- MODIFY
enum ProductMode: String, CaseIterable, Codable {
    case standard
    case superMode = "super"
    case cloud

    var usesLLM: Bool {
        self == .superMode || self == .cloud
    }

    var isCloud: Bool {
        self == .cloud
    }

    var title: String {
        switch self {
        case .standard: "Govorun"
        case .superMode: "Govorun Super"
        case .cloud: "Govorun Cloud"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: "Offline voice input, no AI processing"
        case .superMode: "Voice input with local AI"
        case .cloud: "Voice input with GigaChat Max"
        }
    }
}
```

**Rationale:** Adding `.cloud` case. `usesLLM` becomes true for both super and cloud. New `isCloud` property distinguishes cloud-specific logic (auth, network checks). Every switch on ProductMode that handles `.superMode` must now also handle `.cloud`.

**Impact analysis:**
- `PipelineEngine.stopRecording()` line 562: `currentProductMode.usesLLM` -- works as-is, cloud goes to LLM path
- `PipelineEngine` embedded snippet path line 431: `currentProductMode.usesLLM` -- works as-is
- `AppState.applyProductMode()` -- MUST add `.cloud` handling (wire CloudLLMClient)
- `AppState.handleSuperAssetsChanged()` line 356: `effectiveProductMode.usesLLM` -- needs guard: cloud does not use llmRuntimeManager
- `AppState.updateLLMRuntimeState()` line 297: `currentProductMode.usesLLM` -- cloud should not drive llmRuntimeState
- `SettingsStore.productMode` -- works as-is (Codable rawValue)

### 2. AuthService Protocol and SberAuthService

```swift
// Services/SberAuthService.swift -- NEW FILE (port from govorun repo)

protocol AuthService: Sendable {
    func getAccessToken() async throws -> String
}

enum AuthError: Error, Equatable {
    case credentialsNotFound
    case networkError(String)
    case invalidResponse(statusCode: Int)
    case tokenParsingFailed
}

struct OAuthToken: Sendable {
    let accessToken: String
    let expiresAt: Date
}

final class SberAuthService: AuthService, @unchecked Sendable {
    // credentialProvider: @Sendable () -> (clientId: String, secret: String)?
    // scope: String (GIGACHAT_API_PERS)
    // httpClient: HTTPClient (URLSession with SberTrustDelegate)
    // tokenURL: https://ngw.devices.sberbank.ru:9443/api/v2/oauth
    //
    // Caches OAuthToken with 5min refresh margin.
    // NSLock for thread-safe cached token access.
    // Basic auth header = base64(clientId:clientSecret).
    // RqUID header = UUID per request.
    // Sber returns expires_at as Unix ms timestamp.
}
```

**Key design decisions:**
- Port directly from reference repo `/Users/sanyasamineva/Desktop/govorun/Govorun/Services/SberAuthService.swift`
- credentialProvider closure (not direct CredentialStoring dependency) for testability
- Scope hardcoded to `GIGACHAT_API_PERS` for personal API access to GigaChat Max
- HTTPClient protocol already exists in reference; reuse pattern for govorun-app

### 3. HTTPClient Protocol

```swift
// Services/HTTPClient.swift -- NEW FILE

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}
```

**Rationale:** Required by both SberAuthService and CloudLLMClient. Enables mock injection in tests without real network calls. Identical to reference repo pattern. Small file, clear boundary.

### 4. SberTrustPolicy (TLS Certificate Pinning)

```swift
// Services/SberTrustPolicy.swift -- NEW FILE

final class SberTrustPolicy: @unchecked Sendable {
    // Loads SberRootCA.pem from bundle
    // Creates URLSession with custom URLSessionDelegate
    // SberTrustDelegate pins Sber domain certificates (*.sberbank.ru, *.sber.ru)
    // Uses SecTrustSetAnchorCertificates + system CAs (not only-pinned)
    // Required because Sber uses Russian CA (Mintsifry) not in macOS trust store
}
```

**Rationale:** Sber API uses TLS certificates signed by Russian Mintsifry CA, not trusted by default on macOS. Without this, URLSession rejects the connection. Port from reference repo minus gRPC parts (no GRPC/NIOSSL needed -- govorun-app uses REST only). Bundle `SberRootCA.pem` in Resources/.

### 5. CloudLLMClient

```swift
// Services/CloudLLMClient.swift -- NEW FILE

final class CloudLLMClient: LLMClient, @unchecked Sendable {
    // Conforms to existing LLMClient protocol:
    //   func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String
    //
    // Dependencies:
    //   authService: AuthService
    //   httpClient: HTTPClient (SberTrustPolicy.urlSession)
    //   configuration: CloudLLMConfiguration
    //
    // API: POST https://gigachat.devices.sberbank.ru/api/v1/chat/completions
    // Model: GigaChat-Max (or GigaChat-2 per reference)
    // Temperature: 0.1
    // Request timeout: 5s
    // Retry: 1 retry on retryable errors (rateLimited, serverError, timeout) after 500ms
    //
    // Uses SuperTextStyle.systemPrompt() for system message -- IDENTICAL to LocalLLMClient.
    // Returns parsed content from choices[0].message.content.
}
```

**Critical insight:** CloudLLMClient uses the exact same prompt generation as LocalLLMClient (`SuperTextStyle.systemPrompt()`). The only difference is transport: HTTP to Sber API vs HTTP to localhost llama-server. This means:
- NormalizationGate works identically for both
- SuperTextStyle logic is fully reusable
- All style-aware tests validate both paths

### 6. CloudLLMConfiguration

```swift
// Models/CloudLLMConfiguration.swift -- NEW FILE

struct CloudLLMConfiguration: Equatable {
    static let defaultBaseURLString = "https://gigachat.devices.sberbank.ru/api/v1"
    static let defaultModel = "GigaChat-Max"
    static let defaultTemperature: Double = 0.1
    static let defaultRequestTimeout: TimeInterval = 5.0
    static let defaultRetryDelay: TimeInterval = 0.5

    let baseURLString: String
    let model: String
    let temperature: Double
    let requestTimeout: TimeInterval
    let retryDelay: TimeInterval
}
```

**Rationale:** Separate from LocalLLMConfiguration because cloud has different defaults (different model, shorter timeout, no healthcheck TTL, no failure cooldown). Follows same pattern as LocalLLMConfiguration.

### 7. CredentialStore

```swift
// Storage/CredentialStore.swift -- NEW FILE

protocol CredentialStoring: Sendable {
    func saveCloudCredentials(clientId: String, clientSecret: String) throws
    func getCloudCredentials() -> (clientId: String, secret: String)?
    func deleteCloudCredentials() throws
}

final class CredentialStore: CredentialStoring, @unchecked Sendable {
    // Keychain(service: "com.govorun.credentials")
    // Keys:
    //   com.govorun.cloud.clientId
    //   com.govorun.cloud.clientSecret
    // NSLock for thread safety
    // No migration needed (new keychain entries)
}
```

**Rationale:** govorun-app currently has ZERO API credentials ("Zero API credentials -- all local" per CLAUDE.md). Cloud mode introduces the first external credentials. Keychain is mandatory per project constraints. Simplified protocol vs reference repo (no STT credentials, no legacy migration needed).

**Security constraint from PROJECT.md:** "API credentials only in Keychain, not UserDefaults."

## Data Flow: Cloud Dictation Session

```
1. User selects ProductMode.cloud in Settings
2. AppState.applyProductMode(.cloud):
   a. Check CredentialStore for cloud credentials
   b. If present: create SberAuthService + CloudLLMClient
   c. pipelineEngine.updateLLMClient(cloudLLMClient)
   d. pipelineEngine.productMode = .cloud
   e. llmRuntimeManager.stop()  // not needed for cloud
   f. updateLLMRuntimeState(.disabled)  // cloud does not use local runtime

3. User holds activation key -> speaks -> releases

4. PipelineEngine.stopRecording():
   a. STT (GigaAM, local) -> rawTranscript
   b. DictionaryStore corrections
   c. DeterministicNormalizer.preflight()
   d. productMode.usesLLM == true -> invoke LLM
   e. cloudLLMClient.normalize(deterministicText, superStyle, hints)
      i.  SberAuthService.getAccessToken()
          - Check cached token (NSLock)
          - If expired/expiring: POST /oauth with Basic auth
          - Cache new token
      ii. POST /chat/completions with Bearer token
          - systemPrompt from SuperTextStyle (identical to local)
          - Parse choices[0].message.content
          - On retryable error: wait 500ms, retry once
   f. NormalizationGate.evaluate() -- works unchanged
   g. NormalizationPipeline.postflight() -- works unchanged
   h. ListFormatter.format() -> final text

5. TextInserter inserts text into active field
```

## OAuth Token Lifecycle

```
                    SberAuthService
                    +---------------------------------+
                    |                                 |
                    |  cachedToken: OAuthToken?       |
                    |  lock: NSLock                   |
                    |                                 |
getAccessToken() ->|  1. lock.lock()                 |
                    |  2. if cached && !expiringSoon  |
                    |     -> return cached.accessToken|
                    |  3. lock.unlock()               |
                    |                                 |
                    |  4. credentialProvider()        |
                    |     -> CredentialStore.get()    |
                    |     -> (clientId, secret)?      |
                    |     -> nil = AuthError          |
                    |        .credentialsNotFound     |
                    |                                 |
                    |  5. POST /api/v2/oauth          |
                    |     Authorization: Basic(b64)   |
                    |     RqUID: UUID                 |
                    |     Body: scope=GIGACHAT_API_PERS|
                    |                                 |
                    |  6. Parse response:             |
                    |     access_token: String        |
                    |     expires_at: ms timestamp    |
                    |                                 |
                    |  7. Cache OAuthToken            |
                    |     refreshMargin: 5 min        |
                    |                                 |
                    |  8. Return access_token         |
                    +---------------------------------+

Token lifetime: Sber tokens typically expire in 30 minutes.
Refresh margin: 5 minutes before expiry -> re-fetch.
No refresh_token flow -- always re-authenticate with credentials.
Thread safety: NSLock around cached token read/write.
```

**Where it fits:** SberAuthService is called by CloudLLMClient.sendRequest() before every API call. Token caching means most calls reuse the cached token. Re-authentication is transparent to the pipeline.

## Network Error Handling Strategy

### Principle: Cloud errors NEVER break offline modes

```
Error Category       | Handling                          | User Impact
---------------------|-----------------------------------|---------------------------
AuthError            |                                   |
  .credentialsNotFound| Block mode switch, show settings  | Cannot enable cloud mode
  .networkError      | LLM graceful degradation          | Deterministic fallback
  .invalidResponse   | LLM graceful degradation          | Deterministic fallback
  .tokenParsingFailed| LLM graceful degradation          | Deterministic fallback
                     |                                   |
LLMError             |                                   |
  .networkError      | Catch in PipelineEngine -> fallback| Deterministic text output
  .timeout           | 1 retry, then fallback            | ~5.5s delay, then fallback
  .rateLimited       | 1 retry after 500ms, then fallback| Deterministic text output
  .serverError       | 1 retry after 500ms, then fallback| Deterministic text output
  .invalidResponse   | No retry, fallback                | Deterministic text output
  .parsingFailed     | No retry, fallback                | Deterministic text output
                     |                                   |
Network offline      |                                   |
  cloud mode active  | NetworkMonitor.isConnected=false   | Pipeline still works
                     | CloudLLMClient.normalize() throws  |   (deterministic fallback)
                     | PipelineEngine catches -> fallback | No mode auto-switch
```

**Existing graceful degradation in PipelineEngine (line 600-626):**
The pipeline already handles LLM failures with deterministic fallback. CloudLLMClient errors will be caught by the same `catch` block that handles LocalLLMClient failures. The `NormalizationPipeline.failedPostflight()` path produces `deterministicText` as output. The user gets text -- just without LLM polish.

**No auto-switch on network loss.** If the user selected cloud mode and the network drops, the pipeline degrades gracefully per-request rather than switching to standard/super mode. Rationale: mode is a user choice, not an automatic failover target.

### Cloud readiness check

```swift
// AppState -- new method
func cloudReadiness() -> CloudReadiness {
    guard credentialStore.getCloudCredentials() != nil else {
        return .noCredentials
    }
    guard networkMonitor.isCurrentlyConnected else {
        return .offline  // still allow mode, just degrade gracefully
    }
    return .ready
}

enum CloudReadiness {
    case ready
    case noCredentials  // block mode switch, direct to settings
    case offline        // allow mode, show warning, degrade gracefully
}
```

## Modified Components

### AppState Changes

```
MODIFY: AppState.init()
  - Create CredentialStore
  - Create SberTrustPolicy (bundle SberRootCA.pem)
  - No CloudLLMClient at init -- create on-demand when mode switches to .cloud

MODIFY: AppState.applyProductMode()
  Current: handles .standard and .superMode
  Add: .cloud branch
    - Verify credentials exist
    - Create SberAuthService with credentialProvider closure
    - Create CloudLLMClient with SberTrustPolicy.urlSession
    - pipelineEngine.updateLLMClient(cloudLLMClient)
    - pipelineEngine.productMode = .cloud
    - llmRuntimeManager?.stop()
    - updateLLMRuntimeState(.disabled)

MODIFY: AppState.handleSuperAssetsChanged()
  Current: checks effectiveProductMode.usesLLM (true for both super AND cloud)
  Fix: guard effectiveProductMode == .superMode (not .cloud)
  Cloud does not depend on super assets (llama-server, GGUF model).

MODIFY: AppState.start()
  Current: if currentProductMode.usesLLM -> handleSuperAssetsChanged()
  Fix: if currentProductMode == .superMode -> handleSuperAssetsChanged()
       if currentProductMode == .cloud -> wireCloudClient()

MODIFY: AppState.updateLLMRuntimeState()
  Current: llmRuntimeState = currentProductMode.usesLLM ? state : .disabled
  Fix: llmRuntimeState = currentProductMode == .superMode ? state : .disabled
```

### SettingsStore Changes

```
MODIFY: SettingsStore
  - No new keys needed for productMode (already Codable)
  - Add cloud-specific readiness state for UI
  - ProductMode.cloud value auto-persists via rawValue "cloud"
```

### PipelineEngine: No Changes Required

The beauty of the existing design: PipelineEngine is completely agnostic to whether `_llmClient` is `LocalLLMClient` or `CloudLLMClient`. The `LLMClient` protocol is the seam. The only change is in AppState which swaps the client when mode changes via `pipelineEngine.updateLLMClient()`.

### NormalizationGate: No Changes Required

CloudLLMClient uses identical prompts (SuperTextStyle.systemPrompt). Gate rules apply equally -- same edit distance thresholds, same protected token patterns, same contract logic.

## Architectural Patterns

### Pattern 1: Protocol-Polymorphic LLM Client

**What:** Both LocalLLMClient and CloudLLMClient conform to LLMClient. PipelineEngine only knows the protocol.
**Why:** Zero pipeline changes for cloud. Hot-swap via `updateLLMClient()`. Test isolation through mock clients.
**Trade-off:** Cannot expose cloud-specific features (e.g. streaming) through the protocol without protocol evolution.

### Pattern 2: Lazy Client Construction

**What:** CloudLLMClient is NOT created at AppState.init(). Created only when ProductMode switches to .cloud.
**Why:** Avoids creating auth services and trust policies when user never enables cloud. No unnecessary resource allocation.
**Trade-off:** First cloud request has ~200ms overhead for client construction + first OAuth token fetch.

### Pattern 3: Credential-Gated Mode Switch

**What:** ProductMode.cloud cannot be activated without credentials in Keychain.
**Why:** Prevents confusing UX where user enables cloud but every request fails with AuthError.credentialsNotFound.
**Trade-off:** Settings UI must provide credential entry before or during mode switch. Two-step flow.

### Pattern 4: Transparent Degradation (reuse existing)

**What:** PipelineEngine's existing `catch` block around LLM calls produces deterministic fallback.
**Why:** Cloud errors (network, auth, rate limit) hit the same catch path as local LLM errors. Zero new error handling code in pipeline.
**Trade-off:** User may not know WHY text quality degraded. Consider: analytics event for cloud fallback.

### Pattern 5: Trust Delegate Injection

**What:** SberTrustPolicy creates a URLSession with SberTrustDelegate. This session is passed to both SberAuthService and CloudLLMClient as HTTPClient.
**Why:** Single TLS trust configuration shared across all Sber API calls. Certificate loading happens once.
**Trade-off:** Cannot use URLSession.shared for Sber calls (must use custom session).

## Anti-Patterns to Avoid

### Anti-Pattern 1: Mode Auto-Switch on Network Loss

**What people do:** Auto-switch from .cloud to .standard when network drops.
**Why bad:** User explicitly chose cloud mode. Auto-switching is confusing. Creates race conditions when network flaps.
**Instead:** Degrade gracefully per-request. Show status indicator. Let user switch manually.

### Anti-Pattern 2: Shared Configuration Between Local and Cloud

**What people do:** Reuse LocalLLMConfiguration for CloudLLMClient.
**Why bad:** Different defaults (model name, timeout, no healthcheck). Leaky abstraction.
**Instead:** Separate CloudLLMConfiguration struct with cloud-specific defaults.

### Anti-Pattern 3: Token Management in CloudLLMClient

**What people do:** Put OAuth logic directly in the LLM client.
**Why bad:** Violates single responsibility. Makes testing harder. Token logic is reusable.
**Instead:** Separate SberAuthService. CloudLLMClient calls authService.getAccessToken().

### Anti-Pattern 4: Storing Credentials in UserDefaults

**What people do:** Save clientId/clientSecret in UserDefaults for simplicity.
**Why bad:** Plaintext, accessible to any process. Project constraint explicitly forbids this.
**Instead:** Keychain via CredentialStore. Always.

### Anti-Pattern 5: Modifying PipelineEngine for Cloud

**What people do:** Add cloud-specific branching inside PipelineEngine.
**Why bad:** Violates the clean protocol boundary. PipelineEngine should be LLM-agnostic.
**Instead:** All cloud specifics live in CloudLLMClient, SberAuthService, AppState wiring. Pipeline stays clean.

## Suggested Build Order

Dependencies flow bottom-up. Each phase compiles and tests independently.

```
Phase 1: Foundation Types
  - CloudLLMConfiguration (Models/)
  - ProductMode.cloud case (Models/)
  - AuthError enum (Services/)
  - OAuthToken struct (Services/)
  
Phase 2: Security Infrastructure
  - SberRootCA.pem in Resources/
  - SberTrustPolicy (Services/) -- URLSession with TLS pinning
  - CredentialStore + CredentialStoring protocol (Storage/)
  - HTTPClient protocol (Services/)
  
Phase 3: Auth Service
  - AuthService protocol (Services/)
  - SberAuthService implementation (Services/)
  - Tests: token caching, refresh, credential errors, HTTP errors
  
Phase 4: Cloud LLM Client
  - CloudLLMClient (Services/) -- conforms to LLMClient
  - Tests: normalize, retry, timeout, auth integration
  
Phase 5: AppState Integration
  - CredentialStore wiring in AppState.init()
  - applyProductMode(.cloud) branch
  - handleSuperAssetsChanged() guard fix
  - start() cloud branch
  - updateLLMRuntimeState() fix
  - handleSettingsChanged() cloud awareness
  
Phase 6: Settings UI
  - Cloud credentials entry (clientId + clientSecret)
  - Connection status indicator
  - ProductMode picker with .cloud option
  
Phase 7: Analytics
  - Cloud-specific analytics events (cloud_fallback, cloud_latency)
  - Mode in existing events
```

### Build Order Rationale

- Types first (1) -- all subsequent phases depend on them
- Security before auth (2) -- TLS policy and Keychain must exist before auth service
- Auth before client (3) -- CloudLLMClient depends on AuthService
- Client before integration (4) -- AppState needs CloudLLMClient to wire
- Integration before UI (5) -- functional pipeline before user-facing controls
- UI before analytics (6) -- user can test before analytics tracking
- Each phase is independently testable with mocks

## Integration Points Summary

| Boundary | Direction | Mechanism | Notes |
|----------|-----------|-----------|-------|
| AppState -> CloudLLMClient | Create on mode switch | Lazy construction | Not at init |
| AppState -> PipelineEngine | `updateLLMClient()` | Hot-swap | Existing API |
| CloudLLMClient -> SberAuthService | `getAccessToken()` | async/await | Per-request |
| SberAuthService -> CredentialStore | `getCloudCredentials()` | Closure capture | Decoupled |
| SberAuthService -> HTTPClient | `data(for:)` | Protocol | SberTrustPolicy.urlSession |
| CloudLLMClient -> HTTPClient | `data(for:)` | Protocol | Same URLSession |
| PipelineEngine -> LLMClient | `normalize()` | Protocol | Agnostic to impl |
| CloudSettingsView -> CredentialStore | Save/load | Direct call | Keychain |
| CloudSettingsView -> AppState | Mode change | SettingsStore -> Combine | Existing pattern |

## File Inventory

### New Files (7)

| File | Layer | Purpose |
|------|-------|---------|
| `Services/CloudLLMClient.swift` | Services | GigaChat Max HTTP client, LLMClient conformance |
| `Services/SberAuthService.swift` | Services | OAuth token lifecycle, credential-based auth |
| `Services/SberTrustPolicy.swift` | Services | TLS certificate pinning for Sber domains |
| `Services/HTTPClient.swift` | Services | Protocol for testable HTTP, URLSession extension |
| `Models/CloudLLMConfiguration.swift` | Models | Cloud API defaults (model, timeout, temperature) |
| `Storage/CredentialStore.swift` | Storage | Keychain-backed credential persistence |
| `Resources/Certificates/SberRootCA.pem` | Resources | Mintsifry root CA certificate |

### Modified Files (5)

| File | Change |
|------|--------|
| `Models/ProductMode.swift` | Add `.cloud` case, `isCloud` property |
| `App/AppState.swift` | Wire cloud client, mode handling, credentials |
| `Storage/SettingsStore.swift` | Cloud readiness helpers (minor) |
| `Core/ErrorMessages.swift` | Cloud-specific error messages |
| `project.yml` | New source files, SberRootCA.pem bundle resource |

### Unchanged Files (critical to note)

| File | Why Unchanged |
|------|---------------|
| `Core/PipelineEngine.swift` | Protocol-polymorphic, LLM-agnostic |
| `Core/NormalizationGate.swift` | Same prompts, same gate rules |
| `Core/NormalizationPipeline.swift` | Same preflight/postflight |
| `Services/LLMClient.swift` | Protocol unchanged, new conformer |
| `Services/LocalLLMClient.swift` | Not affected by cloud addition |
| `Models/SuperTextStyle.swift` | Cloud uses same prompts |
| `Models/NormalizationHints.swift` | No cloud-specific hints needed |

---
*Architecture research for: GigaChat Max API integration into govorun-app*
*Researched: 2026-04-06*
