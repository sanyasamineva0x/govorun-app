---
status: issues_found
phase: 11
depth: standard
files_reviewed: 2
findings:
  critical: 2
  warning: 4
  info: 3
  total: 9
---

# Code Review: Phase 11 — OAuth

## Critical

### CR-01 — `fatalError` in production code violates no-crash convention
**File:** `Govorun/Services/SberAuthService.swift`
**Lines:** 51–56
**Confidence:** 95

`defaultTokenURL` uses `fatalError` as a fallback if URL parsing fails. CLAUDE.md forbids force unwraps in production code; `fatalError` is strictly worse. The URL string is hardcoded and currently valid, but the pattern violates guidelines.

**Fix:** Use private enum constant or guard differently without crashing path.

### CR-02 — `MockAuthService` lives in production `Services/` layer
**File:** `Govorun/Services/SberAuthService.swift`
**Lines:** 159–176
**Confidence:** 90

`MockAuthService` is in the production target. CLAUDE.md: "Моки в тестах". Having a mock in production target ships test code in the app binary.

**Note:** The plan explicitly requires MockAuthService in this file for Phase 12 downstream injection. This is an intentional architectural decision — Phase 12's CloudLLMClient needs the mock available in the main target for dependency injection patterns. Reclassify as advisory.

## Warning

### WR-01 — `MockAuthService` uses `NSLock` — new code should prefer actor
**File:** `Govorun/Services/SberAuthService.swift`
**Lines:** 161, 167–170
**Confidence:** 88

CLAUDE.md concurrency model says actor for new code. MockAuthService uses NSLock + @unchecked Sendable.

**Note:** MockAuthService needs synchronous property access for test assertions (e.g., `mock.callCount`), which actors cannot provide without await. NSLock is the established pattern for mocks in this codebase per CredentialStore and HTTPClient mocks. Reclassify as advisory.

### WR-02 — `AuthError` does not conform to `LocalizedError`
**File:** `Govorun/Services/SberAuthService.swift`
**Lines:** 11–31
**Confidence:** 85

CLAUDE.md: "Conform to `LocalizedError` when error is shown to users". Auth errors will surface as user-facing indicators.

### WR-03 — `scope` not percent-encoded in HTTP form body
**File:** `Govorun/Services/SberAuthService.swift`
**Lines:** 137
**Confidence:** 82

Scope value interpolated directly into form body without percent-encoding. Default `GIGACHAT_API_PERS` is safe but custom scopes with special characters would break.

### WR-04 — No test for `refreshMargin` boundary condition
**File:** `GovorunTests/SberAuthServiceTests.swift`
**Confidence:** 83

No test exercises the 5-minute boundary specifically. Existing test uses already-expired token, not the proactive refresh within margin.

## Info

### IR-01 — No test for retry after failed request
**File:** `GovorunTests/SberAuthServiceTests.swift`
**Confidence:** 80

No test verifies that after a failed `getAccessToken()` clears `inFlightTask`, subsequent call creates fresh request.

### IR-02 — `expires_at` millisecond division has no defensive floor
**File:** `Govorun/Services/SberAuthService.swift`
**Lines:** 144, 149
**Confidence:** 80

No validation that resulting expiry date is in the future. Server returning `expires_at: 0` would cause infinite refresh loop.

### IR-03 — Coalescing test relies on timing (acceptable)
**File:** `GovorunTests/SberAuthServiceTests.swift`
**Lines:** 198–215
**Confidence:** 80

The `async let` pattern is structurally sound — actor serial executor guarantees correct ordering. No action required.
