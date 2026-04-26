# Phase 11: OAuth - Research

**Researched:** 2026-04-12
**Domain:** Swift actor-based OAuth token management, Sber GigaChat API authentication
**Confidence:** HIGH

## Summary

Phase 11 ports the existing `SberAuthService` from the prototype (`/Desktop/govorun/`) to the new codebase, replacing `NSLock`-based concurrency with a Swift `actor`. The prototype already contains working OAuth logic (request building, token parsing, expiry check) that maps directly. The key architectural change is concurrency: actor isolation replaces manual locking, and in-flight task coalescing prevents thundering herd on concurrent `getAccessToken()` calls.

All external dependencies already exist in the codebase from Phase 10: `HTTPClient` protocol + `MockHTTPClient`, `CredentialStoring` protocol + `MockCredentialStore`, `SberTrustPolicy` + `MockTrustPolicy`. No new dependencies or frameworks needed -- this is pure Swift, URLSession, Foundation.

**Primary recommendation:** Port prototype business logic (buildTokenRequest, parseTokenResponse, isExpiringSoon) into a new `actor SberAuthService` with a stored `Task<String, Error>?` for in-flight coalescing. AuthError stays clean -- no LLMError knowledge.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** AuthError remains a clean auth type (credentialsNotFound, networkError, invalidResponse, tokenParsingFailed). Mapping AuthError to LLMError is CloudLLMClient's responsibility (Phase 12), not SberAuthService. SberAuthService has no knowledge of LLMError.
- **D-02:** This allows reusing SberAuthService for other clients without LLM coupling.
- **D-03:** SberAuthService is fail-fast. Single HTTP attempt per request, error returned up without retry. Retry logic lives entirely in CloudLLMClient (Phase 12) -- single retry location, no nested retry loops.
- **D-04:** Init parameters with defaults (like prototype): tokenURL, scope, httpClient, credentialProvider via init. Tests inject localhost URL and MockHTTPClient. No separate config struct -- overkill for auth with a fixed endpoint.
- **D-05:** Scope hardcoded as default: `GIGACHAT_API_PERS`. Refresh margin: 5 minutes (static let).
- **D-06:** Swift `actor` -- first actor added to codebase via planning. Natural serialization: concurrent getAccessToken() calls automatically serialize through actor isolation. No NSLock + continuation array needed -- actor provides this for free.

### Claude's Discretion
- Protocol naming (`AuthService` vs `SberAuthenticating` vs other)
- OAuthToken struct shape (internal vs public)
- Concrete coalescing implementation (actor Task + in-flight tracking)
- Error Equatable conformance pattern
- File placement (Services/SberAuthService.swift)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INFRA-04 | SberAuthService gets OAuth token (scope GIGACHAT_API_PERS), caches with refresh margin, actor-based | Actor coalescing pattern, prototype port logic, Sber API specification -- all researched below |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation | system | URLRequest, Data, Date, UUID, JSONSerialization | Already used throughout codebase [VERIFIED: codebase] |
| URLSession | system | HTTP transport (via HTTPClient protocol) | Already abstracted in Phase 10, injectable for tests [VERIFIED: codebase] |
| Security (Keychain) | system | Credentials storage (via CredentialStoring protocol) | Already abstracted in Phase 10 [VERIFIED: codebase] |

### Supporting
No new dependencies. Phase 10 output provides everything:
- `HTTPClient` protocol + `MockHTTPClient` [VERIFIED: Govorun/Services/HTTPClient.swift]
- `CredentialStoring` protocol + `MockCredentialStore` [VERIFIED: Govorun/Storage/CredentialStore.swift]
- `TrustPolicyProviding` + `MockTrustPolicy` [VERIFIED: Govorun/Services/SberTrustPolicy.swift]

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `actor` | `@unchecked Sendable + NSLock` | NSLock is existing pattern in codebase but D-06 locks `actor`; actor is cleaner for async coalescing |
| `JSONSerialization` | `Codable/JSONDecoder` | Prototype uses JSONSerialization -- simpler for flat 2-field response, no need for full Codable model |

**Installation:** No packages to install. Zero new dependencies (per project Out of Scope: "New SPM dependencies -- URLSession + Security.framework only").

## Architecture Patterns

### Recommended Project Structure
```
Govorun/
  Services/
    SberAuthService.swift    # actor + AuthService protocol + AuthError + OAuthToken
```

Single file placement, consistent with existing Services/ organization. [VERIFIED: codebase pattern -- AnalyticsService.swift, LocalLLMClient.swift are single-file services]

### Pattern 1: Actor with In-Flight Task Coalescing

**What:** Store a `Task<String, Error>?` property on the actor. When `getAccessToken()` is called, check if an in-flight fetch exists. If yes, await it. If no, create one. Actor reentrancy ensures concurrent callers see the same in-flight task at await suspension points.

**When to use:** Any time multiple concurrent callers might trigger the same expensive operation.

**How it works with actor reentrancy:**
1. Caller A enters `getAccessToken()`, sees no cached token, sees no in-flight task, creates `Task` and stores it, then hits `await task.value` (suspension point).
2. Caller B enters while A is suspended (actor reentrancy). Sees the in-flight task exists. Hits `await task.value` on the same Task.
3. Task completes. Both A and B resume with the same result.
4. `defer` clears the in-flight task so future calls can trigger a new fetch.

**Example:**
```swift
// [CITED: buczel.com/blog/swift-task-coalescing/]
// [CITED: blog.jacobstechtavern.com/p/advanced-swift-actors-re-entrancy]
// Adapted for SberAuthService

actor SberAuthService: AuthService {
    private var cachedToken: OAuthToken?
    private var inFlightTask: Task<String, Error>?

    func getAccessToken() async throws -> String {
        // Быстрый путь: кеш валиден
        if let token = cachedToken, !isExpiringSoon(token) {
            return token.accessToken
        }

        // Coalescing: подключиться к текущему запросу
        if let task = inFlightTask {
            return try await task.value
        }

        // Новый запрос
        let task = Task<String, Error> {
            defer { inFlightTask = nil }
            let token = try await fetchToken()
            cachedToken = token
            return token.accessToken
        }
        inFlightTask = task

        return try await task.value
    }
}
```

**Critical reentrancy detail:** `Task` is a reference type (class). When caller A suspends at `await task.value`, caller B enters the actor, sees `inFlightTask != nil`, and awaits the *same* Task handle. The `defer { inFlightTask = nil }` executes when the Task body completes, clearing it for future fetches. Because `defer` runs inside the Task body (not the `getAccessToken` method), it only clears once -- not per caller. [CITED: blog.jacobstechtavern.com/p/advanced-swift-actors-re-entrancy]

### Pattern 2: Prototype Port -- Business Logic Methods

**What:** Port these three methods from the prototype without changes to their core logic:

1. `buildTokenRequest(clientId:clientSecret:scope:) -> URLRequest` -- POST to token URL, Basic auth header, RqUID UUID header, form-urlencoded body
2. `parseTokenResponse(_ data: Data) throws -> OAuthToken` -- JSONSerialization, extract access_token + expires_at (milliseconds / 1000.0)
3. `isExpiringSoon(_ token: OAuthToken) -> Bool` -- `expiresAt.timeIntervalSinceNow < refreshMargin`

**Source:** [VERIFIED: /Desktop/govorun/govorun/Services/SberAuthService.swift lines 136-165]

### Pattern 3: Protocol-Based DI (Existing Codebase Pattern)

**What:** `AuthService` protocol with single method `getAccessToken() async throws -> String`. Production type is `actor SberAuthService`. Tests use a `MockAuthService`.

**Example:**
```swift
// Протокол (как в прототипе)
protocol AuthService: Sendable {
    func getAccessToken() async throws -> String
}

// Actor реализация
actor SberAuthService: AuthService { ... }

// Мок для тестов Phase 12+
final class MockAuthService: AuthService, @unchecked Sendable {
    private let lock = NSLock()
    var tokenResult: String?
    var tokenError: Error?
    private(set) var callCount = 0

    func getAccessToken() async throws -> String {
        lock.lock()
        callCount += 1
        lock.unlock()
        if let error = tokenError { throw error }
        return tokenResult ?? "mock-token"
    }
}
```

[VERIFIED: codebase pattern -- MockHTTPClient, MockCredentialStore, MockSTTClient all follow this exact structure]

### Anti-Patterns to Avoid
- **NSLock + continuation array for coalescing:** Overly complex when actor provides natural serialization (D-06 explicitly forbids this).
- **Nested retry inside SberAuthService:** D-03 requires fail-fast. Single attempt, error propagates. CloudLLMClient (Phase 12) owns retry.
- **Importing or referencing LLMError:** D-01 forbids SberAuthService from knowing about LLMError.
- **`defer` inside `getAccessToken` instead of inside the Task body:** If `defer { inFlightTask = nil }` is placed in `getAccessToken()`, each caller's return would clear the task, breaking coalescing for concurrent waiters. The defer must be inside the Task body.
- **Multiple await points before coalescing check:** All state checks (cached token? in-flight task?) must happen synchronously before any await. Actor reentrancy can change state between await points.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thread-safe mutable state | NSLock + manual locking | Swift `actor` | Actor isolation is built-in, compiler-enforced, no deadlock risk |
| Base64 encoding | Manual byte manipulation | `Data.base64EncodedString()` | Standard Foundation, used in prototype |
| UUID generation | Custom ID format | `UUID().uuidString` | Standard, matches Sber RqUID format (uuid4) |
| JSON parsing (flat response) | Full Codable model | `JSONSerialization` | 2-field response, Codable overkill, prototype already works |

**Key insight:** This phase is a port, not a greenfield design. The prototype's business logic is battle-tested. The only change is the concurrency model (NSLock -> actor + coalescing).

## Common Pitfalls

### Pitfall 1: Actor Reentrancy Breaking Cache Invariants
**What goes wrong:** State checked before `await` is no longer valid after `await` resumes.
**Why it happens:** Actor reentrancy allows other calls to execute between suspension points.
**How to avoid:** Do all state reads and the in-flight task check/creation synchronously (no await). Only one await point: `task.value`.
**Warning signs:** Multiple `await` calls before returning the token; `if-let` on cached token followed by an await then using the cached token.

### Pitfall 2: expires_at Parsed as Seconds Instead of Milliseconds
**What goes wrong:** Token appears to expire 1000x further in the future, never refreshes.
**Why it happens:** Sber API returns `expires_at` as Unix timestamp in **milliseconds** (int64). Forgetting to divide by 1000.0 creates dates in year ~33,000.
**How to avoid:** `Date(timeIntervalSince1970: expiresAt / 1000.0)` -- exactly as in prototype.
**Warning signs:** Token never auto-refreshes in testing; expiresAt date is absurdly far in the future.
[VERIFIED: ai-forever/gigachat Python SDK models/auth.py documents expires_at as "Unix timestamp (in milliseconds)"]

### Pitfall 3: defer Placement in Coalescing
**What goes wrong:** `defer { inFlightTask = nil }` placed in `getAccessToken()` instead of inside the Task body means each caller's return clears the in-flight reference, potentially before other callers finish awaiting.
**Why it happens:** Natural instinct to put cleanup in the calling function.
**How to avoid:** Put `defer` inside the Task closure body. It fires once when the Task body completes, not per awaiter.
**Warning signs:** Second concurrent caller gets a nil in-flight task and spawns a duplicate fetch.

### Pitfall 4: Missing `@Sendable` on credentialProvider Closure
**What goes wrong:** Compiler error under `SWIFT_STRICT_CONCURRENCY: complete`.
**Why it happens:** Closure stored in an actor must be `@Sendable`. Project enforces strict concurrency.
**How to avoid:** Declare as `@Sendable () -> (clientId: String, secret: String)?` -- exactly as in prototype.
**Warning signs:** Build error about non-sendable closure capture.
[VERIFIED: project.yml sets SWIFT_STRICT_CONCURRENCY: complete]

### Pitfall 5: Testing Actors Requires `async` Test Methods
**What goes wrong:** Calling actor methods from synchronous XCTest methods.
**Why it happens:** Actor-isolated methods are async from the outside.
**How to avoid:** All test methods that interact with SberAuthService must be `func test_...() async throws`.
**Warning signs:** Compiler error about calling async function from non-async context.

## Code Examples

### Complete SberAuthService Skeleton (Recommended Implementation)

```swift
// Source: Prototype port + actor coalescing pattern
// [VERIFIED: prototype at /Desktop/govorun/govorun/Services/SberAuthService.swift]
// [CITED: buczel.com/blog/swift-task-coalescing/]

import Foundation

// MARK: - Протокол

protocol AuthService: Sendable {
    func getAccessToken() async throws -> String
}

// MARK: - Ошибки

enum AuthError: Error, Equatable {
    case credentialsNotFound
    case networkError(String)
    case invalidResponse(statusCode: Int)
    case tokenParsingFailed

    // Equatable: ассоциированные значения требуют ручной реализации
    static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        switch (lhs, rhs) {
        case (.credentialsNotFound, .credentialsNotFound),
             (.tokenParsingFailed, .tokenParsingFailed):
            true
        case (.networkError(let a), .networkError(let b)):
            a == b
        case (.invalidResponse(let a), .invalidResponse(let b)):
            a == b
        default:
            false
        }
    }
}

// MARK: - Модель токена

struct OAuthToken: Sendable {
    let accessToken: String
    let expiresAt: Date
}

// MARK: - Реализация

actor SberAuthService: AuthService {
    private let credentialProvider: @Sendable () -> (clientId: String, secret: String)?
    private let scope: String
    private let httpClient: HTTPClient
    private let tokenURL: URL

    private var cachedToken: OAuthToken?
    private var inFlightTask: Task<String, Error>?

    static let defaultTokenURL: URL = {
        guard let url = URL(string: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth") else {
            fatalError("Invalid defaultTokenURL")
        }
        return url
    }()
    static let refreshMargin: TimeInterval = 5 * 60

    init(
        credentialProvider: @escaping @Sendable () -> (clientId: String, secret: String)?,
        scope: String = "GIGACHAT_API_PERS",
        httpClient: HTTPClient = URLSession.shared,
        tokenURL: URL? = nil
    ) {
        self.credentialProvider = credentialProvider
        self.scope = scope
        self.httpClient = httpClient
        self.tokenURL = tokenURL ?? Self.defaultTokenURL
    }

    func getAccessToken() async throws -> String {
        // Кеш
        if let token = cachedToken, !isExpiringSoon(token) {
            return token.accessToken
        }

        // Coalescing
        if let task = inFlightTask {
            return try await task.value
        }

        // Новый запрос
        let task = Task<String, Error> {
            defer { self.inFlightTask = nil }

            guard let credentials = self.credentialProvider() else {
                throw AuthError.credentialsNotFound
            }

            let request = self.buildTokenRequest(
                clientId: credentials.clientId,
                clientSecret: credentials.secret,
                scope: self.scope
            )

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await self.httpClient.data(for: request)
            } catch {
                throw AuthError.networkError(error.localizedDescription)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse(statusCode: -1)
            }
            guard httpResponse.statusCode == 200 else {
                throw AuthError.invalidResponse(statusCode: httpResponse.statusCode)
            }

            let token = try self.parseTokenResponse(data)
            self.cachedToken = token
            return token.accessToken
        }
        inFlightTask = task
        return try await task.value
    }

    // MARK: - Private (портировано из прототипа)

    private func buildTokenRequest(clientId: String, clientSecret: String, scope: String) -> URLRequest {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "RqUID")

        let authString = "\(clientId):\(clientSecret)"
        if let authData = authString.data(using: .utf8) {
            request.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = "scope=\(scope)".data(using: .utf8)
        return request
    }

    private func parseTokenResponse(_ data: Data) throws -> OAuthToken {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresAt = json["expires_at"] as? TimeInterval
        else {
            throw AuthError.tokenParsingFailed
        }

        // Sber API: expires_at в миллисекундах Unix timestamp
        let expiryDate = Date(timeIntervalSince1970: expiresAt / 1000.0)
        return OAuthToken(accessToken: accessToken, expiresAt: expiryDate)
    }

    private func isExpiringSoon(_ token: OAuthToken) -> Bool {
        token.expiresAt.timeIntervalSinceNow < Self.refreshMargin
    }
}
```

### Test Pattern: MockHTTPClient with OAuth Response

```swift
// Source: Project test patterns [VERIFIED: GovorunTests/HTTPClientTests.swift]

func makeValidTokenResponse(token: String = "test-token", expiresInSeconds: TimeInterval = 1800) -> (Data, URLResponse) {
    let expiresAtMs = (Date().timeIntervalSince1970 + expiresInSeconds) * 1000.0
    let json = """
    {"access_token": "\(token)", "expires_at": \(Int64(expiresAtMs))}
    """
    let data = Data(json.utf8)
    let response = HTTPURLResponse(
        url: URL(string: "https://ngw.devices.sberbank.ru:9443/api/v2/oauth")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    return (data, response as URLResponse)
}
```

### Test Pattern: Coalescing Verification

```swift
// Проверка что N конкурентных вызовов = 1 HTTP запрос
func test_concurrent_calls_coalesce_into_single_request() async throws {
    let mock = MockHTTPClient()
    mock.result = makeValidTokenResponse()

    let sut = SberAuthService(
        credentialProvider: { ("id", "secret") },
        httpClient: mock
    )

    // Запускаем N конкурентных запросов
    async let t1 = sut.getAccessToken()
    async let t2 = sut.getAccessToken()
    async let t3 = sut.getAccessToken()

    let tokens = try await [t1, t2, t3]

    // Все получили один и тот же токен
    XCTAssertEqual(Set(tokens).count, 1)
    // Только 1 HTTP запрос
    XCTAssertEqual(mock.requests.count, 1)
}
```

## Sber OAuth API Specification

| Property | Value |
|----------|-------|
| Endpoint | `POST https://ngw.devices.sberbank.ru:9443/api/v2/oauth` |
| Content-Type | `application/x-www-form-urlencoded` |
| Authorization | `Basic base64(clientId:clientSecret)` |
| RqUID header | UUID v4 string (unique per request) |
| Body | `scope=GIGACHAT_API_PERS` |
| Response | `{"access_token": "...", "expires_at": 1234567890123}` |
| expires_at format | Unix timestamp in **milliseconds** (int64) |
| Token validity | 30 minutes |
| Rate limit | Up to 10 requests/second |

[CITED: developers.sber.ru/docs/ru/gigachat/api/reference/rest/post-token]
[VERIFIED: ai-forever/gigachat Python SDK: `expires_at: int` documented as "Unix timestamp (in milliseconds)"]
[VERIFIED: saintbyte/gigachat_api Go SDK: `ExpiresAt int64`]
[VERIFIED: prototype parseTokenResponse divides by 1000.0]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@unchecked Sendable + NSLock` | Swift `actor` | Existing in codebase (AnalyticsService, LocalLLMHealthState) but prototype used NSLock | Actor is already used in project; this is a port to modern pattern |
| Manual continuation arrays for coalescing | Stored `Task<V, Error>?` + actor reentrancy | Swift 5.5+ actors (WWDC21) | Simpler, less error-prone than NSLock + continuation tracking |
| Prototype's legacy `CredentialStoring` (STT/LLM/legacy methods) | Phase 10 `CredentialStoring` (save/get/delete only) | Phase 10 | Clean interface, no legacy methods -- credentialProvider closure wraps it |

**Note on existing actors in codebase:** Despite CONTEXT.md calling this "first actor," the codebase already has `actor AnalyticsService` and `private actor LocalLLMHealthState`. SberAuthService will be the first actor introduced through the GSD planning pipeline and the first with in-flight task coalescing. [VERIFIED: grep for `actor` in Govorun/Services/]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Task<String, Error>` inside actor body can reference `self` properties without capture issues under strict concurrency | Architecture Patterns | Compiler error -- fixable at implementation time with explicit self capture |
| A2 | `async let` in tests creates true concurrency sufficient to trigger coalescing | Code Examples | Test may not reliably trigger concurrent access -- may need TaskGroup or explicit delay in mock |

**Both assumptions are LOW risk.** A1 is standard actor-isolated Task usage. A2 can be verified during implementation with a delay-based MockHTTPClient.

## Open Questions

1. **Protocol naming: `AuthService` vs `SberAuthenticating`**
   - What we know: Prototype uses `AuthService`. Project conventions use verb-based protocol names (e.g., `SnippetMatching`, `AudioRecording`, `TextInserting`).
   - What's unclear: Whether to follow the `-ing` convention or keep the prototype's simple name.
   - Recommendation: Use `AuthService` -- it matches the prototype, is more descriptive for a service protocol (not a capability), and is consistent with the existing `AnalyticsService` actor. The `-ing` suffix pattern in this codebase is for capabilities (matching, recording, inserting), not services.

2. **OAuthToken visibility: internal vs private**
   - What we know: Prototype declares it at file scope (internal by default). Phase 12 CloudLLMClient only needs `getAccessToken() -> String`, not the token struct.
   - What's unclear: Whether any future consumer needs the struct.
   - Recommendation: Keep `OAuthToken` as file-private or internal. No consumer outside SberAuthService needs it currently.

3. **Concurrency test reliability**
   - What we know: `async let` may or may not create true interleaving depending on Swift runtime scheduling.
   - What's unclear: Whether mock needs artificial delay to guarantee coalescing behavior in tests.
   - Recommendation: Add a configurable delay to MockHTTPClient for coalescing tests. This ensures the first request is still in-flight when subsequent callers enter.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (system, ~986 existing tests) |
| Config file | `Govorun.xctestplan` |
| Quick run command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SberAuthServiceTests` |
| Full suite command | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INFRA-04.1 | Fetches OAuth token from Sber endpoint with correct headers/body | unit | `xcodebuild test ... -only-testing:GovorunTests/SberAuthServiceTests/test_getAccessToken_buildsCorrectRequest` | No -- Wave 0 |
| INFRA-04.2 | Token cached, auto-refreshed 5 min before expiry | unit | `xcodebuild test ... -only-testing:GovorunTests/SberAuthServiceTests/test_cachedToken_returnedWithoutHTTPCall` | No -- Wave 0 |
| INFRA-04.3 | Concurrent requests coalesce into single HTTP call | unit | `xcodebuild test ... -only-testing:GovorunTests/SberAuthServiceTests/test_concurrent_calls_coalesce` | No -- Wave 0 |
| INFRA-04.4 | RqUID UUID header in every request | unit | `xcodebuild test ... -only-testing:GovorunTests/SberAuthServiceTests/test_request_containsRqUIDHeader` | No -- Wave 0 |
| INFRA-04.5 | AuthError cases map correctly | unit | `xcodebuild test ... -only-testing:GovorunTests/SberAuthServiceTests/test_errors` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** Quick run command on SberAuthServiceTests
- **Per wave merge:** Full test suite
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `GovorunTests/SberAuthServiceTests.swift` -- covers INFRA-04 (all sub-requirements)
- [ ] MockHTTPClient delay support -- for reliable coalescing test (may add `responseDelay: TimeInterval?` property or use existing mock with Task.sleep in test)
- [ ] MockAuthService -- for downstream Phase 12 tests (optional, can defer to Phase 12)

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | OAuth 2.0 client credentials flow via Sber API; credentials from Keychain via CredentialStoring |
| V3 Session Management | yes | Token cached in memory only (no persistent storage), auto-refresh before expiry |
| V4 Access Control | no | N/A for this phase |
| V5 Input Validation | yes | HTTP response status validation, JSON response parsing with explicit type checks |
| V6 Cryptography | no | TLS handled by SberTrustPolicy (Phase 10); Basic auth uses standard base64 encoding |

### Known Threat Patterns for OAuth Token Management

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Credentials in memory after use | Information Disclosure | Credentials read from Keychain on-demand via closure, not stored in SberAuthService [VERIFIED: prototype pattern] |
| Token stored in plaintext in memory | Information Disclosure | Acceptable for in-process cache (30 min validity); not persisted to disk |
| Man-in-the-middle on token endpoint | Tampering | SberTrustPolicy certificate pinning (Phase 10) [VERIFIED: SberTrustPolicy.swift] |
| Thundering herd on token refresh | Denial of Service | Actor coalescing prevents multiple simultaneous refresh calls |
| Token replay | Spoofing | Out of scope -- server-side concern; tokens are short-lived (30 min) |

## Environment Availability

Step 2.6: SKIPPED (no external dependencies -- pure Swift code, URLSession, Foundation; all build tools already verified in Phase 10)

## Sources

### Primary (HIGH confidence)
- Prototype SberAuthService.swift -- complete working OAuth implementation [VERIFIED: /Desktop/govorun/govorun/Services/SberAuthService.swift]
- Phase 10 output files -- HTTPClient, CredentialStore, SberTrustPolicy [VERIFIED: codebase]
- ai-forever/gigachat Python SDK models/auth.py -- `expires_at: int` documented as "Unix timestamp (in milliseconds)" [VERIFIED: GitHub raw file]
- Existing codebase actors -- AnalyticsService, LocalLLMHealthState [VERIFIED: grep in codebase]

### Secondary (MEDIUM confidence)
- [Sber Developer Portal](https://developers.sber.ru/docs/ru/gigachat/api/reference/rest/post-token) -- OAuth endpoint specification (site renders client-side, content confirmed via search + SDK cross-reference)
- [Swift Task Coalescing](https://buczel.com/blog/swift-task-coalescing/) -- InFlightTaskCoalescer pattern
- [Actor Reentrancy Deep Dive](https://blog.jacobstechtavern.com/p/advanced-swift-actors-re-entrancy) -- defer placement, reentrancy mechanics
- [Token Refresh with Actors](https://www.donnywals.com/building-a-token-refresh-flow-with-async-await-and-swift-concurrency/) -- AuthManager actor pattern
- [saintbyte/gigachat_api Go SDK](https://pkg.go.dev/github.com/saintbyte/gigachat_api) -- TokenResponse struct with `ExpiresAt int64`

### Tertiary (LOW confidence)
None -- all claims verified against prototype code or official SDK sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- zero new dependencies, all from Phase 10 + Foundation
- Architecture: HIGH -- actor pattern well-documented, prototype provides business logic, existing actors in codebase prove the pattern works
- Pitfalls: HIGH -- reentrancy behavior verified against multiple authoritative sources and prototype code

**Research date:** 2026-04-12
**Valid until:** 2026-05-12 (stable domain -- OAuth spec and Swift actor semantics are not changing)
