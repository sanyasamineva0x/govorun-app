---
phase: 11-oauth
verified: 2026-04-12T00:00:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
---

# Phase 11: SberAuthService OAuth Verification Report

**Phase Goal:** SberAuthService с actor-based token coalescing, AuthError mapping
**Verified:** 2026-04-12
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SberAuthService fetches OAuth token from ngw.devices.sberbank.ru:9443/api/v2/oauth | VERIFIED | `defaultTokenURL` hardcoded to `https://ngw.devices.sberbank.ru:9443/api/v2/oauth` (line 52), `buildTokenRequest` uses `tokenURL` (line 124) |
| 2 | Token is cached in memory and reused without additional HTTP calls | VERIFIED | `private var cachedToken: OAuthToken?` (line 48); `getAccessToken()` returns `token.accessToken` on cache hit without HTTP call (lines 73–75); `test_cachedToken_returnedWithoutHTTPCall` asserts `mock.requests.count == 1` |
| 3 | Cached token auto-refreshes when within 5 minutes of expiry | VERIFIED | `static let refreshMargin: TimeInterval = 5 * 60` (line 58); `isExpiringSoon` compares `timeIntervalSinceNow < Self.refreshMargin` (line 154); `test_expiredToken_triggersNewFetch` exercises the path |
| 4 | Concurrent getAccessToken() calls coalesce into a single HTTP request | VERIFIED | `private var inFlightTask: Task<String, Error>?` (line 49); in-flight check at lines 77–79; `defer { self.inFlightTask = nil }` inside Task body (line 82); `test_concurrent_calls_coalesce` asserts `delayMock.requests.count == 1` with 3 async let callers |
| 5 | RqUID UUID header is present in every OAuth request | VERIFIED | `request.setValue(UUID().uuidString, forHTTPHeaderField: "RqUID")` (line 127); `test_request_containsRqUIDHeader` validates UUID format via NSRegularExpression |
| 6 | AuthError cases are clean auth types with no LLMError knowledge | VERIFIED | File imports only `Foundation` (line 1); `grep LLMError` returns 0 matches; 4 clean cases: `credentialsNotFound`, `networkError(String)`, `invalidResponse(statusCode: Int)`, `tokenParsingFailed` |
| 7 | SberAuthService is a Swift actor (not NSLock-based) | VERIFIED | `actor SberAuthService: AuthService` (line 42); NSLock appears only in `MockAuthService` (line 161), which is `@unchecked Sendable final class` — correct per project conventions for mocks |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Govorun/Services/SberAuthService.swift` | AuthService protocol, AuthError enum, OAuthToken struct, actor SberAuthService, MockAuthService | VERIFIED | All 5 types present: `protocol AuthService: Sendable` (line 5), `enum AuthError: Error, Equatable` (line 11), `struct OAuthToken: Sendable` (line 35), `actor SberAuthService: AuthService` (line 42), `final class MockAuthService: AuthService, @unchecked Sendable` (line 160) |
| `GovorunTests/SberAuthServiceTests.swift` | Unit tests for SberAuthService, 80+ lines, class SberAuthServiceTests | VERIFIED | 254 lines, `final class SberAuthServiceTests: XCTestCase` (line 48), 16 test methods |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `Govorun/Services/SberAuthService.swift` | `Govorun/Services/HTTPClient.swift` | HTTPClient protocol injection in init | VERIFIED | `httpClient: HTTPClient = URLSession.shared` in init signature (line 63); `private let httpClient: HTTPClient` stored property (line 45); `httpClient.data(for: request)` called at line 96 |
| `Govorun/Services/SberAuthService.swift` | `Govorun/Storage/CredentialStore.swift` | credentialProvider closure wrapping CredentialStoring.get() | VERIFIED | `credentialProvider: @escaping @Sendable () -> (clientId: String, secret: String)?` in init (line 61); closure called at line 84 in Task body; indirect dependency — Phase 12 caller wraps CredentialStore.get() into closure |
| `GovorunTests/SberAuthServiceTests.swift` | `Govorun/Services/SberAuthService.swift` | import and direct instantiation with mocks | VERIFIED | `@testable import Govorun`; `SberAuthService(credentialProvider:...)` instantiated at lines 57, 74, 203, 233, 244 |

### Data-Flow Trace (Level 4)

Not applicable — SberAuthService is a service actor, not a UI component rendering dynamic data. Token data flows through the actor's internal state (`cachedToken`) and is returned as a `String` to callers. The flow is covered by behavioral tests.

### Behavioral Spot-Checks

Step 7b: SKIPPED — tests require `xcodebuild` runtime; this is a Swift macOS target with no independently runnable CLI entry point. Test results are documented in SUMMARY.md: 16/16 SberAuthServiceTests PASS, 1183 total suite 0 failures.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| INFRA-04 | 11-01-PLAN.md | SberAuthService получает OAuth токен (scope GIGACHAT_API_PERS), кеширует с refresh margin, actor-based | SATISFIED | OAuth endpoint wired (Truth 1), caching verified (Truth 2), 5-min refresh margin (Truth 3), actor isolation (Truth 7), scope defaulting to `GIGACHAT_API_PERS` confirmed in init signature and `test_request_containsCorrectBody` |

No orphaned requirements — REQUIREMENTS.md maps only INFRA-04 to Phase 11.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Govorun/Services/SberAuthService.swift` | 51–56 | `fatalError` in `defaultTokenURL` static property | Warning | URL string is hardcoded and valid; fatalError unreachable in practice but violates CLAUDE.md no-crash convention. Documented in REVIEW.md as CR-01. Does not block goal. |
| `Govorun/Services/SberAuthService.swift` | 160–176 | `MockAuthService` in production `Services/` layer | Warning | Intentional architectural decision — Phase 12 CloudLLMClient needs MockAuthService in main target for DI. Documented in REVIEW.md as CR-02 (reclassified advisory). Does not block goal. |
| `Govorun/Services/SberAuthService.swift` | 11–31 | `AuthError` missing `LocalizedError` conformance | Warning | Auth errors will surface to UI (WR-02 in REVIEW.md). Does not block Phase 11 goal; Phase 15 (UI) is appropriate fix location. |

**Clarification on NSLock in SberAuthService.swift:**

The PLAN acceptance criteria states `Govorun/Services/SberAuthService.swift does NOT contain NSLock`. NSLock IS present at line 161, but exclusively inside `MockAuthService` — a `@unchecked Sendable final class`, where NSLock is the established project convention for test doubles (as used in `MockHTTPClient` and `MockCredentialStore`). The plan's own Task 1 action (line 186) explicitly specifies `private let lock = NSLock()` inside MockAuthService. This is a contradiction within the plan text; the implementation follows the explicit task instruction. The observable truth "SberAuthService is a Swift actor (not NSLock-based)" is fully met — the `actor SberAuthService` contains zero NSLock usage.

### Human Verification Required

None. All must-have truths are verifiable statically. The SUMMARY.md documents 16/16 tests passing and 1183 total suite green, which aligns with static code analysis confirming all implementations are present, substantive, and wired.

### Gaps Summary

No gaps. All 7 observable truths verified. INFRA-04 is satisfied. The three anti-patterns noted (fatalError in static URL, mock in production layer, missing LocalizedError) are pre-existing advisory findings from REVIEW.md, none blocking the phase goal. The NSLock presence is constrained to MockAuthService per explicit plan instructions and project conventions for mocks.

---

_Verified: 2026-04-12_
_Verifier: Claude (gsd-verifier)_
