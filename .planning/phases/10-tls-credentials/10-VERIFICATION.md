---
phase: 10-tls-credentials
verified: 2026-04-12T13:27:47Z
status: human_needed
score: 4/4 must-haves verified
re_verification: false
human_verification:
  - test: "Run xcodegen generate then xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation"
    expected: "All 1153 tests pass including SberTrustPolicyTests (15 tests), CredentialStoreTests (9 tests), HTTPClientTests (5 tests)"
    why_human: "The xcodeproj on disk (modified 2026-04-11) is stale relative to Phase 10 source files (added 2026-04-12). xcodegen must be run to regenerate project references before xcodebuild can compile new files. This requires a local macOS environment with Xcode."
---

# Phase 10: TLS & Credentials Verification Report

**Phase Goal:** App can establish trusted HTTPS connections to Sber domains and securely store API credentials
**Verified:** 2026-04-12T13:27:47Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SberRootCA.pem is bundled in the app and loadable at runtime via Security.framework | VERIFIED | File exists at `Govorun/Resources/Certificates/SberRootCA.pem`, exactly 4634 bytes, contains 2 valid DER-encoded certificates (2 `BEGIN CERTIFICATE` markers confirmed). Included via XcodeGen `sources: path: Govorun` auto-discovery. `.gitignore` exception `!Govorun/Resources/Certificates/SberRootCA.pem` added. |
| 2 | SberTrustPolicy throws TrustPolicyError on init when PEM is missing or unparseable | VERIFIED | `init(bundle: Bundle = .main) throws` in `SberTrustPolicy.swift` throws `.pemNotFound` on nil path and `.certificateParsingFailed` on empty cert array. Both error cases have tests (`test_init_emptyBundle_throwsPemNotFound`, `test_init_invalidPEM_throwsCertificateParsingFailed`). |
| 3 | A dedicated URLSession with SberTrustDelegate trusts `*.sberbank.ru` using bundled CA while preserving system CA for other domains | VERIFIED | `SberTrustDelegate.urlSession(_:didReceive:completionHandler:)` calls `SecTrustSetAnchorCertificates`, `SecTrustSetAnchorCertificatesOnly(serverTrust, false)` (false preserves system CAs), `SecTrustEvaluateWithError`. Non-Sber domains receive `.performDefaultHandling`. `isSberDomain` is case-insensitive and matches both `*.sberbank.ru` and `*.sber.ru`. |
| 4 | CredentialStore saves and retrieves clientId + clientSecret from Keychain (Security.framework, not KeychainAccess) | VERIFIED | `CredentialStore.swift` uses `SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete` directly. Service name `com.govorun.app.credentials` with accounts `gigachat.clientId` / `gigachat.clientSecret`. No `import KeychainAccess`. Delete-then-add upsert pattern. `errSecItemNotFound` treated as success on delete. NSLock for thread safety. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Govorun/Resources/Certificates/SberRootCA.pem` | Russian Trusted Root CA + Sub CA certificate chain | VERIFIED | 4634 bytes, 2 certificates, committed in git `994a92e` |
| `Govorun/Services/SberTrustPolicy.swift` | TrustPolicyProviding protocol, SberTrustPolicy class, SberTrustDelegate, TrustPolicyError enum, MockTrustPolicy | VERIFIED | All 5 exports present, 134 lines, committed in `255396f` |
| `GovorunTests/SberTrustPolicyTests.swift` | Unit tests for PEM parsing, domain matching, failable init, error cases | VERIFIED | 15 test methods (above minimum of 10) covering all specified behaviors |
| `Govorun/Storage/CredentialStore.swift` | CredentialStoring protocol (3 methods), CredentialStore (Security.framework), CredentialStoreError, MockCredentialStore | VERIFIED | All 4 exports present, 140 lines, committed in `b027294` |
| `Govorun/Services/HTTPClient.swift` | HTTPClient protocol, URLSession extension conformance, MockHTTPClient | VERIFIED | All 3 exports present, 43 lines, committed in `1705b40` |
| `GovorunTests/CredentialStoreTests.swift` | Unit tests for CredentialStoring protocol via MockCredentialStore | VERIFIED | 9 test methods (above minimum of 8) |
| `GovorunTests/HTTPClientTests.swift` | Unit tests for HTTPClient protocol and URLSession conformance | VERIFIED | 5 test methods (meets minimum of 4) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `SberTrustPolicy.swift` | `Govorun/Resources/Certificates/SberRootCA.pem` | `bundle.path(forResource: "SberRootCA", ofType: "pem")` | WIRED | Line 27: `bundle.path(forResource: "SberRootCA", ofType: "pem")` confirmed |
| `SberTrustPolicy.swift` | `Security.framework` | `SecCertificateCreateWithData, SecTrustSetAnchorCertificates, SecTrustEvaluateWithError` | WIRED | All 3 Security APIs confirmed in file: `SecCertificateCreateWithData` (line 77), `SecTrustSetAnchorCertificates` (line 112), `SecTrustEvaluateWithError` (line 117) |
| `CredentialStore.swift` | `Security.framework` | `SecItemAdd, SecItemCopyMatching, SecItemDelete` | WIRED | All 3 SecItem APIs confirmed: `SecItemAdd` (line 69), `SecItemCopyMatching` (line 85), `SecItemDelete` (lines 67, 103) |
| `HTTPClient.swift` | `Foundation.URLSession` | `extension URLSession: HTTPClient` | WIRED | Line 11: `extension URLSession: HTTPClient {}` confirmed |

### Data-Flow Trace (Level 4)

Not applicable for this phase. All artifacts are infrastructure/protocol definitions (no dynamic data rendering). The phase provides trust primitives and storage, not UI components or data pipelines.

### Behavioral Spot-Checks

Skipped — no runnable entry points in this phase (no CLI, no API server, no build scripts). All artifacts are Swift source files requiring Xcode compilation. Compilation and test execution require human verification (see Human Verification Required section).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| INFRA-01 | 10-01-PLAN.md | Сертификат Минцифры (SberRootCA.pem) вшит в приложение для TLS с Sber API | SATISFIED | `Govorun/Resources/Certificates/SberRootCA.pem` exists (4634 bytes, 2 certs), committed, gitignore exception added |
| INFRA-02 | 10-01-PLAN.md | SberTrustPolicy реализует URLSessionDelegate для certificate pinning на `*.sberbank.ru` | SATISFIED | `SberTrustDelegate` (private inner class) implements `URLSessionDelegate`, uses `SecTrustSetAnchorCertificatesOnly(serverTrust, false)` to add bundled CA while preserving system trust; `isSberDomain` gates custom trust to `*.sberbank.ru` and `*.sber.ru` only |
| INFRA-03 | 10-02-PLAN.md | CredentialStore хранит clientId и clientSecret в Keychain (Security.framework) | SATISFIED | `CredentialStore` uses raw `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` with `kSecClassGenericPassword`, no KeychainAccess SPM dependency |
| INFRA-04 | (Not Phase 10) | SberAuthService получает OAuth токен, кеширует с refresh margin, actor-based | DEFERRED | REQUIREMENTS.md assigns INFRA-04 to Phase 11 — correctly excluded from this phase |

No orphaned requirements: REQUIREMENTS.md traceability table maps INFRA-01, INFRA-02, INFRA-03 to Phase 10 and all three are covered by the phase plans.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `Govorun/Services/HTTPClient.swift` | 35 | `URL(string: "https://localhost")!` force unwrap in `MockHTTPClient` | Info | Zero risk (hardcoded valid URL string literal guaranteed to succeed), but technically violates the "no force unwrap in production code" convention. The mock class is in a production file (co-located pattern per project convention — same as `MockTrustPolicy` and `MockCredentialStore`). Not a blocker. |

No TODO/FIXME/placeholder comments found. No empty implementations. No hardcoded empty data returned to callers. No singleton (`static let shared`) in `SberTrustPolicy`. No GRPC/NIO imports. No `KeychainAccess` import.

### Human Verification Required

#### 1. Test Suite Compilation and Execution

**Test:** From the project root, run:
```bash
xcodegen generate && xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation
```
**Expected:**
- `xcodegen generate` completes successfully and includes `SberTrustPolicy.swift`, `CredentialStore.swift`, `HTTPClient.swift`, and `SberRootCA.pem` in the generated project
- All 29 new tests pass: `SberTrustPolicyTests` (15 tests), `CredentialStoreTests` (9 tests), `HTTPClientTests` (5 tests)
- Full test suite passes with zero regressions (SUMMARY claims 1152-1153 tests)

**Why human:** The `Govorun.xcodeproj/project.pbxproj` on disk has modification timestamp `2026-04-11` (before Phase 10 files were added on `2026-04-12`). The xcodeproj is NOT committed as part of Phase 10 commits (`994a92e`, `255396f`, `b027294`, `1705b40`). XcodeGen must be run to regenerate project references. This requires a local macOS environment with Xcode 15.4+ and the `xcodegen` CLI. Cannot be verified statically.

**Note:** Once `xcodegen generate` is run, all Phase 10 source files will be auto-included via the `sources: - path: Govorun` directive in `project.yml` which recursively includes all Swift files and resources under `Govorun/`.

### Gaps Summary

No gaps found. All 4 observable truths verified. All 7 required artifacts exist and are substantive. All 4 key links confirmed wired. Requirements INFRA-01, INFRA-02, INFRA-03 all satisfied. The only pending item is human test execution due to the stale xcodeproj (expected in the XcodeGen-based workflow).

---

_Verified: 2026-04-12T13:27:47Z_
_Verifier: Claude (gsd-verifier)_
