---
phase: 10
status: issues_found
depth: standard
files_reviewed: 6
findings:
  critical: 0
  warning: 4
  info: 1
  total: 5
---

# Phase 10: TLS & Credentials — Code Review

## Warning Findings

### WR-01 — MockHTTPClient: mutable state read outside NSLock

**File:** `Govorun/Services/HTTPClient.swift`, lines 26–31
**Confidence:** 95

`MockHTTPClient` reads `error` and `result` outside the lock scope. Both properties are public `var`, writable from any thread. Under `SWIFT_STRICT_CONCURRENCY: complete`, the `@unchecked Sendable` promise of thread safety is broken.

**Fix:** Extend lock scope to capture both reads using `lock.withLock`.

### WR-02 — Force unwraps in production code in MockHTTPClient

**File:** `Govorun/Services/HTTPClient.swift`, lines 35 and 39
**Confidence:** 90

Two `!` operators in `MockHTTPClient.data(for:)` violate the project rule "No force unwrap (!) in production code". MockHTTPClient lives in a production-compiled file.

**Fix:** Use `guard let` or safe fallback instead of `!`.

### WR-03 — CredentialStore: credentials eligible for iCloud Keychain sync

**File:** `Govorun/Storage/CredentialStore.swift`, lines 59–82
**Confidence:** 88

Neither `saveItem` nor `readItem` sets `kSecAttrSynchronizable: false`. GigaChat API credentials could sync to iCloud Keychain on other Apple devices.

**Fix:** Add `kSecAttrSynchronizable: kCFBooleanFalse` to all three queries (save, read, delete).

### WR-04 — SberTrustDelegate: system CAs remain trusted for Sber domains

**File:** `Govorun/Services/SberTrustPolicy.swift`, line 114
**Confidence:** 85

`SecTrustSetAnchorCertificatesOnly(serverTrust, false)` allows any system-trusted CA to also sign certs for `*.sberbank.ru`. Intentional design decision from prototype — flagged for documentation.

**Fix:** Add code comment documenting the tradeoff. Review when Phase 11 ships.

## Info Findings

### IR-01 — CredentialStoreTests: real Keychain implementation untested

**File:** `GovorunTests/CredentialStoreTests.swift`
**Confidence:** 82

All 9 tests use MockCredentialStore. The real Security.framework implementation has zero test coverage. Bugs in Keychain queries would only surface during Phase 13 integration.

**Fix:** Add one roundtrip integration test using UUID-suffixed service name.

## Summary

No crashes or data-loss bugs found. WR-01 and WR-03 are highest priority before Phase 11. WR-02 is a convention fix. WR-04 needs a code comment. IR-01 should be addressed before Phase 13.
