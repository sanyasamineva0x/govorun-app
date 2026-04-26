# Domain Pitfalls

**Domain:** Adding cloud LLM mode (GigaChat Max API) to offline-first macOS speech-to-text app
**Researched:** 2026-04-06
**Confidence:** HIGH (based on codebase analysis + official Sber docs + real prototype in govorun repo)

## Critical Pitfalls

Mistakes that cause rewrites, data loss, or broken offline functionality.

### Pitfall 1: OAuth Token Refresh Race Condition

**What goes wrong:**
Two concurrent pipeline executions both detect an expired token and issue separate OAuth requests to `ngw.devices.sberbank.ru:9443/api/v2/oauth`. Both get new tokens, one overwrites the other. Wasted token request (Sber limits to 10 token requests/second) and unnecessary latency.

**Why it happens:**
The existing `SberAuthService` in the govorun prototype uses `NSLock` for `cachedToken`, but `getAccessToken()` is `async` -- there is a window between checking `getCachedToken()` and `setCachedToken()` where another caller can enter the same path. The lock protects the stored value, not the entire refresh flow.

```
Thread A: getCachedToken() -> expired -> starts HTTP request...
Thread B: getCachedToken() -> still expired (A hasn't finished) -> starts HTTP request...
Thread A: sets new token
Thread B: sets another new token (redundant)
```

**Consequences:**
- Double token requests eat into the 10 req/sec limit
- Under high concurrency, thundering herd on the OAuth endpoint
- Possible 429 from the OAuth endpoint itself (undocumented but real)

**Prevention:**
Use Swift `actor` instead of `NSLock` for the auth service, with a stored continuation pattern:

```swift
actor CloudAuthService {
    private var cachedToken: OAuthToken?
    private var refreshTask: Task<String, Error>?

    func getAccessToken() async throws -> String {
        if let token = cachedToken, !isExpiringSoon(token) {
            return token.accessToken
        }
        // Coalesce concurrent refresh requests into one task
        if let existing = refreshTask {
            return try await existing.value
        }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}
```

**Detection:**
Multiple "token refreshed" log entries within the same second. Or 429 from the OAuth endpoint.

**Phase to address:** Phase 1 (CloudAuthService) -- get this right from the start

---

### Pitfall 2: Breaking Offline Modes When Adding Cloud

**What goes wrong:**
Adding `ProductMode.cloud` to the enum changes rawValue serialization in UserDefaults. Existing users on `.standard` or `.superMode` open the app after update and get an unknown rawValue, falling back to `.standard` -- or worse, a crash if code assumes all cases are handled.

**Why it happens:**
`ProductMode` is `CaseIterable, Codable` with raw String values. Adding `.cloud` is safe for the enum itself, but:
1. `SettingsStore.productMode` reads from UserDefaults -- old values still work
2. BUT: if cloud mode requires credentials and the user switches, then removes credentials, what happens on next launch?
3. Pipeline code currently uses `currentProductMode.usesLLM` as a boolean gate. Cloud mode also uses LLM but through a different client. Adding cloud to `usesLLM` would route it to the LOCAL LLM client.

**Consequences:**
- Cloud dictation routed to local llama-server (wrong client entirely)
- Standard/Super modes accidentally touching network code
- Saved `.cloud` in UserDefaults persists across app restarts, but credentials gone = dead mode

**Prevention:**
1. Do NOT make `usesLLM` return true for cloud. Add separate properties:
   - `usesLocalLLM` (super only)
   - `usesCloudLLM` (cloud only)
   - `usesAnyLLM` (both)
2. Pipeline must snapshot which LLMClient to use based on mode, not rely on a single `_llmClient` field
3. If cloud credentials are missing, auto-downgrade to standard on launch (never crash, never silently use wrong mode)
4. Validate mode + credentials at `applyProductMode()` time

**Detection:**
Test: set productMode to .cloud, remove credentials, restart. Should gracefully degrade to .standard.

**Phase to address:** Phase 2 (ProductMode.cloud) + Phase 3 (Pipeline integration)

---

### Pitfall 3: SberRootCA Certificate Not Bundled or Expired

**What goes wrong:**
GigaChat API requires the Russian Ministry of Digital Development (Mintsifry) root certificate for TLS. Without it, URLSession fails with `NSURLErrorServerCertificateUntrusted`. The existing govorun prototype bundles `SberRootCA.pem` and uses a custom `URLSessionDelegate` -- but the govorun-app currently has NO certificate file and NO trust policy code.

**Why it happens:**
govorun-app is fully offline today. It has zero HTTP dependencies (local llama-server is localhost). The SberRootCA certificate and SberTrustPolicy exist only in the separate govorun prototype repo.

**Consequences:**
- Every cloud API call fails silently with certificate errors
- Error message is generic ("network error"), not "certificate not trusted"
- User has no idea why cloud mode does not work
- If the certificate expires or Mintsifry rotates it, cloud mode breaks without code change

**Prevention:**
1. Bundle `SberRootCA.pem` in the app target (Copy Files build phase in project.yml)
2. Port `SberTrustPolicy` with the domain check pattern (`isSberDomain()`) -- do NOT trust the custom CA for non-Sber domains
3. The existing prototype uses `SecTrustSetAnchorCertificatesOnly(serverTrust, false)` -- this is correct: it trusts BOTH system CAs AND the Mintsifry CA. Do not set this to `true` or regular HTTPS breaks.
4. Create the URLSession with the custom delegate, NOT use URLSession.shared for cloud requests
5. Add specific error type `CloudLLMError.certificateNotTrusted` for clear user feedback
6. Version-pin or hash the certificate file to detect when it needs rotation

**Detection:**
`urlSession(_:didReceive:completionHandler:)` called with `NSURLAuthenticationMethodServerTrust` and `SecTrustEvaluateWithError` returns false for `*.sberbank.ru`.

**Phase to address:** Phase 1 (Foundation) -- certificate must exist before any HTTP code

---

### Pitfall 4: Network Timeout vs LLM Generation Timeout

**What goes wrong:**
The existing LocalLLMClient uses `requestTimeout = 12s` for llama-server on localhost. GigaChat Max over the network needs vastly different timeouts. Setting it too low = frequent timeouts on long phrases. Setting it too high = user waits forever on a dead connection.

**Why it happens:**
Network requests have TWO independent timeouts:
1. **Connection timeout** -- how long to establish TCP/TLS connection (should be short: 10-15s)
2. **Response timeout** -- how long to wait for the complete response (should be longer: 30-60s for LLM generation)

GigaChat Max is a large model. For short text normalization (~10-30 tokens) it is fast. But the API has unpredictable latency spikes (cold starts, queue depth, network variability). The Sber SDK default timeout is 60s; the Python SDK uses 120s.

`URLSessionConfiguration.timeoutIntervalForRequest` controls the TOTAL time, not just connection time. If set to the existing 5s (from the prototype `GigaChatClient.requestTimeout`), every request that takes > 5s fails.

**Consequences:**
- Cloud mode appears flaky: "works sometimes, times out randomly"
- Users blame the app, not the network
- Graceful degradation returns deterministic text, so users may not even notice the cloud is failing -- but they are paying for API access and getting the free mode quality

**Prevention:**
1. Separate timeouts: `URLSessionConfiguration.timeoutIntervalForResource` (long: 60s) vs `timeoutIntervalForRequest` (per-chunk: 30s)
2. Add a `CloudLLMConfiguration` separate from `LocalLLMConfiguration` with cloud-appropriate defaults:
   - connectionTimeout: 15s
   - responseTimeout: 30s (for normalization, not arbitrary generation)
3. Implement a "fast-fail on no network" check: use `NetworkMonitor.isCurrentlyConnected` before even attempting the cloud request
4. Show clear timeout errors to the user: "GigaChat did not respond in time, using offline normalization"

**Detection:**
Monitor `llmLatencyMs` in PipelineResult. If cloud path p95 > 10s, timeouts are a real risk.

**Phase to address:** Phase 1 (CloudLLMClient) -- configure timeouts correctly from day one

---

### Pitfall 5: Leaking Transcribed Speech to Cloud Without Consent

**What goes wrong:**
User dictates sensitive content (passwords, medical info, personal messages) in what they think is an offline app. With cloud mode, this text goes to Sber's servers. No consent flow, no warning, no way to know what was sent.

**Why it happens:**
The app was 100% offline until now. Users trust it to keep data local. Adding cloud mode changes the privacy contract fundamentally. Even if the user explicitly enables cloud mode, they may not realize EVERY dictation in that mode sends text over the network.

**Consequences:**
- Privacy violation for users who enabled cloud mode without understanding the implications
- Potential compliance issues (Russian data protection law, 152-FZ)
- Trust erosion: "my private dictation app sends my text to Sber"
- App Store / notarization review concerns (though not on App Store currently)

**Prevention:**
1. First-time cloud mode enable: show explicit consent dialog explaining that transcribed text will be sent to Sber GigaChat API
2. Settings UI: clear indicator when cloud mode is active ("Cloud" label in menubar/bottombar)
3. HistoryItem: record whether cloud was used for each dictation (for user transparency)
4. Consider: do NOT send personalDictionary entries to the cloud API (they are personal data). Only send the transcribed text + system prompt.
5. Log cloud requests to analytics (without content) so user can see cloud usage stats

**Detection:**
No detection -- this is a design requirement. If there is no consent flow, it is a bug.

**Phase to address:** Phase 5 (UI) -- consent dialog before first cloud activation. But the ARCHITECTURE must support this from Phase 1 (CredentialStore must track consent state).

---

## Moderate Pitfalls

### Pitfall 6: PipelineEngine LLM Client Swap Race

**What goes wrong:**
User switches from Super to Cloud mode while a dictation is in progress. `PipelineEngine.updateLLMClient()` swaps `_llmClient` under lock, but the in-flight `stopRecording()` already captured the old client via `snapshotConfig()`. The snapshot is safe. But: if the user starts a NEW dictation immediately after switching, the LLM client might not be fully initialized yet (OAuth token not fetched, certificate not loaded).

**Why it happens:**
`updateLLMClient()` is synchronous -- it sets the new client immediately. But the CloudLLMClient needs async initialization (token fetch). If the pipeline snapshots the client before the first token is obtained, the first cloud request will block on token acquisition, adding latency.

**Prevention:**
1. Pipeline already snapshots under lock via `snapshotConfig()` -- this is correct and must be preserved
2. CloudLLMClient should eagerly fetch a token at construction time (background task), not lazily on first request
3. Or: `applyProductMode(.cloud)` should be async and only set the client after verifying credentials exist AND the initial token is obtainable
4. Never swap LLMClient mid-session -- the snapshot pattern already prevents this

**Phase to address:** Phase 3 (Pipeline integration)

---

### Pitfall 7: NormalizationGate Rejection of Cloud LLM Output

**What goes wrong:**
GigaChat Max has different behavior than the local GigaChat 3.1 GGUF. It may produce output that:
- Is slightly longer (more verbose)
- Uses different punctuation styles
- Handles brand names differently
- Adds explanations instead of just normalizing

The NormalizationGate rejects this output due to edit distance or length ratio violations, and the user gets deterministic text despite paying for cloud.

**Why it happens:**
NormalizationGate was tuned for the local 10B quantized model. GigaChat Max is a much larger model with different output characteristics. The thresholds (edit distance ratio, length ratio bounds) may be too tight for cloud output.

**Consequences:**
- Cloud mode produces the same output as standard mode (gate rejection = deterministic fallback)
- User pays for API tokens but gets no benefit
- Analytics shows high gate rejection rate for cloud path
- Difficult to debug because the gate silently falls back

**Prevention:**
1. NormalizationGate should accept the same `LLMOutputContract` (.normalization / .rewriting) regardless of source
2. BUT: consider looser thresholds for cloud mode IF the model is genuinely better at normalization
3. First: ship with same thresholds, monitor `gateFailureReason` in analytics by productMode
4. Add `normalizationSource: .local | .cloud` to PipelineResult for analytics segmentation
5. Test the production prompt against GigaChat Max BEFORE integration: use the 2M test tokens to evaluate gate pass rates

**Detection:**
Analytics: `gate_rejection_rate` segmented by `productMode == cloud`. If > 10%, thresholds need tuning.

**Phase to address:** Phase 3 (Pipeline) for wiring, Phase 4 for tuning after real API testing

---

### Pitfall 8: Keychain Access Differences Between Apps

**What goes wrong:**
The govorun prototype uses `KeychainAccess` (third-party library) with `Keychain(service: "com.govorun.credentials")`. The govorun-app currently has NO keychain dependency. If the new app uses the Security framework directly (which is the convention -- no unnecessary third-party deps), the keychain item format may differ, and credentials from one app cannot be read by the other.

**Why it happens:**
Keychain items are scoped by:
- Bundle ID (access group)
- Service name (kSecAttrService)
- Signing identity

govorun-app has bundle ID `com.govorun.app`, the prototype likely has a different one. Even if the service name matches, code-signed apps cannot share keychain items without explicit access group configuration.

**Consequences:**
- Users cannot migrate credentials from prototype to new app
- If using different keychain APIs (KeychainAccess vs raw Security.framework), data format may differ
- Credential loss on app migration

**Prevention:**
1. Use Security.framework directly (no KeychainAccess dependency) -- matches govorun-app convention of minimal dependencies
2. Use a distinct service name: `"com.govorun.app.cloud"` (not the prototype's `"com.govorun.credentials"`)
3. Do NOT attempt cross-app keychain sharing -- it requires shared access groups and entitlements
4. Build a `CloudCredentialStore` with the protocol pattern used throughout the app
5. Provide clear UI for entering credentials (clientId + clientSecret) -- no import from prototype

**Detection:**
`SecItemCopyMatching` returns `errSecItemNotFound` -- credentials not readable.

**Phase to address:** Phase 1 (CloudCredentialStore)

---

### Pitfall 9: LLMClient Protocol Mismatch Between Local and Cloud

**What goes wrong:**
The existing `LLMClient` protocol:
```swift
protocol LLMClient: Sendable {
    func normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String
}
```
This works for local LLM. But GigaChat cloud API uses a different prompt format, different model name (`GigaChat-2-Max` vs `gigachat-gguf`), and may need different parameters (temperature, max_tokens). If `CloudLLMClient` conforms to the same protocol, it must shoehorn cloud-specific behavior into a local-oriented interface.

**Why it happens:**
The protocol was designed for one implementation (local llama-server). Cloud has different needs:
- Auth header (Bearer token) vs none
- Custom SSL session vs URLSession.shared
- Different model name and temperature
- Different timeout strategy
- Retry with token refresh on 401

**Consequences:**
- If the protocol is adequate, the CloudLLMClient can conform cleanly. If not, the temptation is to add optional parameters or break the protocol.

**Prevention:**
The protocol IS adequate. Both local and cloud clients take text + style + hints and return normalized text. The implementation details (auth, SSL, model name, timeouts) are all internal to the client. This is the whole point of the protocol pattern.

1. `CloudLLMClient` conforms to `LLMClient` with no protocol changes
2. Internal to CloudLLMClient: custom URLSession with SberTrustPolicy, CloudAuthService for token, cloud-specific configuration
3. SuperTextStyle.systemPrompt() works the same for both -- the prompt format is the LLM's instruction, not the transport's concern
4. PipelineEngine does not need to know which client it is using -- just call `normalize()`

The risk is NOT the protocol -- it is that someone tries to add cloud-specific fields to the protocol or NormalizationHints.

**Detection:**
If LLMClient protocol changes in this milestone, something is wrong. It should NOT need changes.

**Phase to address:** Phase 1 (verify protocol adequacy) -- should be a non-issue if done right

---

### Pitfall 10: Error Propagation and User-Facing Messages

**What goes wrong:**
Cloud errors are diverse: certificate error, auth error, network timeout, rate limit, server error, model unavailable. The current `LLMError` enum covers some of these but lacks cloud-specific cases. If all cloud errors map to `LLMError.networkError("...")` with generic strings, the user gets unhelpful messages and the developer cannot distinguish error types in analytics.

**Why it happens:**
`LLMError` was designed for a local-only context where the main error modes are "server not running" and "timeout". Cloud adds:
- `.authFailed` (credentials wrong or revoked)
- `.certificateError` (SberRootCA not bundled)
- `.quotaExhausted` (2M tokens used up)
- `.modelUnavailable` (GigaChat Max API down)

**Consequences:**
- Generic "network error" message when the real problem is expired API credentials
- Unable to auto-retry auth errors (token refresh) vs permanent errors (wrong credentials)
- Analytics cannot distinguish fixable vs unfixable errors

**Prevention:**
1. Add cloud-specific error cases to LLMError (or create a separate `CloudLLMError` that maps to `LLMError` at the pipeline level)
2. Map HTTP status codes precisely: 401 = auth error (retry token), 403 = forbidden (wrong scope), 429 = rate limited (backoff), 503 = model unavailable (retry)
3. User-facing messages should be actionable: "Check your API credentials in Settings" vs "Network error"
4. `LocalizedError` conformance with Russian errorDescription for each case

**Detection:**
If error analytics shows > 50% "network_error" for cloud path, error mapping is too coarse.

**Phase to address:** Phase 1 (CloudLLMClient error types)

---

## Minor Pitfalls

### Pitfall 11: SberRootCA.pem Bundle Path in Tests

**What goes wrong:**
`SberTrustPolicy.create(bundle: .main)` looks for `SberRootCA.pem` in the main bundle. In unit tests, `Bundle.main` is the test runner, not the app. The certificate is not found, and tests crash with `fatalError` in the `shared` lazy static.

**Prevention:**
1. Never use the `shared` singleton in tests -- inject `MockTrustPolicy` (already exists in prototype)
2. For integration tests that need real cert parsing, use `Bundle(for: SberTrustPolicy.self)` or pass a test bundle
3. TDD: test with `MockTrustPolicy`, integration tests with real cert

**Phase to address:** Phase 1

---

### Pitfall 12: Token Expiry Timestamp Interpretation

**What goes wrong:**
Sber OAuth returns `expires_at` as Unix timestamp in MILLISECONDS (not seconds). The prototype correctly divides by 1000:
```swift
let expiryDate = Date(timeIntervalSince1970: expiresAt / 1000.0)
```
If this is missed, the token appears to expire 1000x in the future (year 2993+), caching an invalid token forever.

**Prevention:**
Unit test: mock OAuth response with realistic `expires_at` value (e.g., 1712419200000 for April 2024). Verify `isExpiringSoon()` returns true when 25 minutes have passed.

**Phase to address:** Phase 1 (CloudAuthService)

---

### Pitfall 13: RqUID Header Requirement

**What goes wrong:**
Sber OAuth requires a `RqUID` header with a UUID value on every token request. If missing, the request may fail silently or return a 400. The prototype correctly generates `UUID().uuidString` for each request. Forgetting this when reimplementing the auth service in govorun-app breaks auth.

**Prevention:**
Port this requirement explicitly. Add a unit test that verifies the mock HTTP request includes `RqUID` header.

**Phase to address:** Phase 1 (CloudAuthService)

---

### Pitfall 14: Cloud Mode Without Network Monitor Integration

**What goes wrong:**
The app already has `NetworkMonitor` but it is not wired to cloud mode logic. User enables cloud mode, goes offline, every dictation attempts network request, fails after 15s timeout, falls back to deterministic text. User waits 15s per dictation for no reason.

**Prevention:**
1. CloudLLMClient.normalize() should check NetworkMonitor first and throw immediately if offline
2. Or: PipelineEngine should route to deterministic path when cloud mode + offline, skipping LLM entirely
3. Show UI indicator: "Cloud mode unavailable (no network)" in bottom bar

**Phase to address:** Phase 3 (Pipeline) + Phase 5 (UI)

---

### Pitfall 15: KeychainAccess vs Security.framework

**What goes wrong:**
The prototype uses the `KeychainAccess` third-party library. The govorun-app convention is minimal dependencies (only Sparkle). Adding KeychainAccess for cloud credentials introduces a dependency that the rest of the app does not use.

**Prevention:**
Use Security.framework directly. The raw API is verbose but well-understood, and there are only 3 operations needed: save, read, delete for clientId + clientSecret. Write a thin wrapper `CloudCredentialStore` with ~40 lines of Security.framework code.

**Phase to address:** Phase 1

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| CloudAuthService | Token refresh race condition (#1) | Use actor, coalesce concurrent refresh requests |
| CloudAuthService | Token timestamp in milliseconds (#12) | Unit test with realistic timestamps |
| CloudAuthService | Missing RqUID header (#13) | Unit test verifies header presence |
| SberTrustPolicy | Certificate not bundled (#3) | Add to Copy Files in project.yml, test loading |
| SberTrustPolicy | Test bundle path (#11) | Use MockTrustPolicy in unit tests |
| CloudCredentialStore | KeychainAccess vs Security.framework (#15) | Use Security.framework directly |
| ProductMode.cloud | Breaks usesLLM routing (#2) | Separate usesLocalLLM/usesCloudLLM properties |
| ProductMode.cloud | Saved mode without credentials (#2) | Auto-downgrade on launch if credentials missing |
| CloudLLMClient | Timeout misconfiguration (#4) | Separate connection/response timeouts, 30s default |
| CloudLLMClient | Generic error messages (#10) | Cloud-specific error cases with Russian LocalizedError |
| Pipeline integration | LLM client swap race (#6) | Snapshot pattern already correct, ensure async init |
| Pipeline integration | Network monitor not checked (#14) | Fast-fail if offline before cloud request |
| NormalizationGate | Rejects cloud output (#7) | Monitor gate rejection rate by productMode |
| Privacy / UI | No consent for cloud data (#5) | Explicit consent dialog on first cloud enable |

## "Looks Done But Isn't" Checklist

- [ ] **CloudAuthService:** Actor-based, coalesces concurrent refresh requests -- not NSLock with async gap
- [ ] **SberRootCA.pem:** Bundled in app target AND referenced in project.yml Copy Files phase
- [ ] **SberTrustPolicy:** `SecTrustSetAnchorCertificatesOnly(_, false)` -- trusts system CAs too, not just Mintsifry
- [ ] **SberTrustPolicy:** Domain check (`isSberDomain`) -- only applies custom trust to Sber endpoints
- [ ] **ProductMode.cloud:** Does NOT set `usesLLM = true` -- has its own `usesCloudLLM` property
- [ ] **ProductMode.cloud:** Missing credentials at launch -> auto-downgrade to .standard, not crash
- [ ] **CloudLLMClient:** Response timeout >= 30s, not the local 5s or 12s
- [ ] **CloudLLMClient:** Conforms to existing `LLMClient` protocol WITHOUT protocol changes
- [ ] **CloudLLMClient:** Checks NetworkMonitor before attempting request
- [ ] **CloudLLMClient:** Maps 401 -> retry token, 403 -> wrong scope, 429 -> rate limited (distinct errors)
- [ ] **PipelineEngine:** Snapshot pattern preserved -- no mid-session client swap
- [ ] **NormalizationGate:** Same thresholds for cloud initially, monitored via analytics
- [ ] **Privacy:** Consent dialog shown before first cloud dictation
- [ ] **Analytics:** Cloud requests tracked with `productMode: "cloud"` and `normalizationSource: "cloud"`
- [ ] **Keychain:** Uses Security.framework, NOT KeychainAccess library
- [ ] **expires_at:** Divided by 1000 (milliseconds to seconds)
- [ ] **RqUID:** UUID header included in every OAuth request
- [ ] **Tests:** All cloud services tested with mocks, NO real API calls in unit tests

## Sources

- [Sber Developer Docs: GigaChat Certificates](https://developers.sber.ru/docs/ru/gigachat/certificates) -- Mintsifry certificate requirement
- [Sber Developer Docs: GigaChat Limitations](https://developers.sber.ru/docs/ru/gigachat/limitations) -- Rate limits and quotas
- [Sber Developer Docs: GigaChat API Overview](https://developers.sber.ru/docs/ru/gigachat/api/overview) -- API reference
- [Sber Developer Docs: GigaChat Models](https://developers.sber.ru/docs/ru/gigachat/models) -- GigaChat-2-Max model info
- [Donny Wals: Building a token refresh flow with async/await](https://www.donnywals.com/building-a-token-refresh-flow-with-async-await-and-swift-concurrency/) -- Actor-based token refresh pattern
- [Essential Developer: Refresh auth tokens with actors](https://www.essentialdeveloper.com/articles/how-to-refresh-auth-tokens-correctly-using-swift-async-await-actors-live-dev-mentoring) -- Concurrent token refresh
- [GitHub: ai-forever/gigachat](https://github.com/ai-forever/gigachat) -- Official Python SDK (timeout defaults, retry config)
- [Medium: Offline-First Architecture](https://medium.com/@jusuftopic/offline-first-architecture-designing-for-reality-not-just-the-cloud-e5fd18e50a79) -- Offline-first patterns
- Existing codebase: `/Users/sanyasamineva/Desktop/govorun/Govorun/Services/SberTrustPolicy.swift` -- prototype certificate handling
- Existing codebase: `/Users/sanyasamineva/Desktop/govorun/Govorun/Services/SberAuthService.swift` -- prototype OAuth implementation
- Existing codebase: `/Users/sanyasamineva/Desktop/govorun/Govorun/Services/GigaChatClient.swift` -- prototype cloud LLM client

---
*Pitfalls research for: Adding GigaChat Max cloud LLM to offline-first Govorun app*
*Researched: 2026-04-06*
