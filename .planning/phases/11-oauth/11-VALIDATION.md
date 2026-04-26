---
phase: 11
slug: oauth
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-12
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (system, ~986 existing tests) |
| **Config file** | `Govorun.xctestplan` |
| **Quick run command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SberAuthServiceTests` |
| **Full suite command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Estimated runtime** | ~30 seconds (quick), ~120 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run quick command on SberAuthServiceTests
- **After every plan wave:** Run full test suite
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | INFRA-04.1 | — | OAuth token fetched with correct headers/body | unit | `xcodebuild test ... -only-testing:GovorunTests/SberAuthServiceTests/test_getAccessToken_buildsCorrectRequest` | ❌ W0 | ⬜ pending |
| 11-01-02 | 01 | 1 | INFRA-04.2 | — | Token cached, auto-refreshed 5 min before expiry | unit | `xcodebuild test ... -only-testing:GovorunTests/SberAuthServiceTests/test_cachedToken_returnedWithoutHTTPCall` | ❌ W0 | ⬜ pending |
| 11-01-03 | 01 | 1 | INFRA-04.3 | T-11-01 | Concurrent requests coalesce into single HTTP call | unit | `xcodebuild test ... -only-testing:GovorunTests/SberAuthServiceTests/test_concurrent_calls_coalesce` | ❌ W0 | ⬜ pending |
| 11-01-04 | 01 | 1 | INFRA-04.4 | — | RqUID UUID header in every request | unit | `xcodebuild test ... -only-testing:GovorunTests/SberAuthServiceTests/test_request_containsRqUIDHeader` | ❌ W0 | ⬜ pending |
| 11-01-05 | 01 | 1 | INFRA-04.5 | — | AuthError cases defined (credentialsNotFound, networkError, invalidResponse, tokenParsingFailed) | unit | `xcodebuild test ... -only-testing:GovorunTests/SberAuthServiceTests/test_errors` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `GovorunTests/SberAuthServiceTests.swift` — test stubs for INFRA-04 (all sub-requirements)
- [ ] MockHTTPClient delay support — for reliable coalescing test

*Existing infrastructure (MockHTTPClient, MockCredentialStore) covers most needs.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
