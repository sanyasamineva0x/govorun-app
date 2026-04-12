---
phase: 10-tls-credentials
plan: 01
subsystem: infra
tags: [tls, security, certificate-pinning, urlsession, sber-api]

requires: []
provides:
  - "TrustPolicyProviding protocol for DI of URLSession with custom CA trust"
  - "SberTrustPolicy with failable init, PEM parsing, Sber domain matching"
  - "SberRootCA.pem bundled (Russian Trusted Root CA + Sub CA)"
  - "MockTrustPolicy for testing"
  - "TrustPolicyError typed error enum"
affects: [11-sber-auth, 12-gigachat-cloud, 13-app-integration]

tech-stack:
  added: [Security.framework (SecCertificate, SecTrust), OSLog]
  patterns: [failable-init-with-bundle-DI, custom-urlsession-delegate, domain-scoped-trust]

key-files:
  created:
    - Govorun/Resources/Certificates/SberRootCA.pem
    - Govorun/Services/SberTrustPolicy.swift
    - GovorunTests/SberTrustPolicyTests.swift
  modified:
    - .gitignore

key-decisions:
  - "gitignore exception for SberRootCA.pem -- public CA, not a secret"
  - "SberTrustDelegate holds only [SecCertificate] -- no back-reference to SberTrustPolicy (URLSession retains delegate)"

patterns-established:
  - "Failable init with Bundle DI: init(bundle: Bundle = .main) throws for resource-dependent services"
  - "Domain-scoped trust: custom CA only for matching domains, performDefaultHandling for everything else"
  - "TrustPolicyProviding protocol: single urlSession requirement for DI"

requirements-completed: [INFRA-01, INFRA-02]

duration: 5min
completed: 2026-04-12
---

# Phase 10 Plan 01: SberTrustPolicy Summary

**TLS trust foundation: SberRootCA.pem bundled with failable SberTrustPolicy parsing PEM into SecCertificate, custom URLSession delegate trusting Sber domains via Russian CA while preserving system trust**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-12T11:44:52Z
- **Completed:** 2026-04-12T11:49:59Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 4

## Accomplishments

- SberRootCA.pem (4634 bytes, 2 certificates) bundled from prototype, verified by xcodegen
- SberTrustPolicy with failable init(bundle:) throws, PEM parsing, domain matching
- SberTrustDelegate with SecTrustSetAnchorCertificatesOnly(false) preserving system CAs
- 15 unit tests covering PEM parsing, domain matching, init success/failure, mock conformance
- Full test suite passes: 1153 tests, 0 failures

## Task Commits

Each task was committed atomically (TDD):

1. **Task 1 RED: SberRootCA.pem + failing tests** - `994a92e` (test)
2. **Task 1 GREEN: SberTrustPolicy implementation** - `255396f` (feat)

## Files Created/Modified

- `Govorun/Resources/Certificates/SberRootCA.pem` - Russian Trusted Root CA + Sub CA (2 certs, 4634 bytes)
- `Govorun/Services/SberTrustPolicy.swift` - TrustPolicyProviding protocol, SberTrustPolicy, SberTrustDelegate, TrustPolicyError, MockTrustPolicy
- `GovorunTests/SberTrustPolicyTests.swift` - 15 tests: PEM parsing, domain matching, init, mock
- `.gitignore` - Exception for SberRootCA.pem (public CA, not a secret)

## Decisions Made

- Added .gitignore exception for SberRootCA.pem -- it's a public CA certificate, not a private key or secret
- SberTrustDelegate holds only [SecCertificate] array, no back-reference to SberTrustPolicy (avoids retain cycle since URLSession strongly retains its delegate)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] .gitignore *.pem rule blocked SberRootCA.pem from git**
- **Found during:** Task 1 (RED commit)
- **Issue:** `*.pem` in .gitignore secrets section blocked the public CA certificate from being committed
- **Fix:** Added `!Govorun/Resources/Certificates/SberRootCA.pem` exception
- **Files modified:** .gitignore
- **Verification:** git add succeeded, file tracked
- **Committed in:** 994a92e (Task 1 RED commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary to track public CA certificate in git. No scope creep.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None - all functionality is fully wired.

## Next Phase Readiness

- TrustPolicyProviding protocol ready for injection into SberAuthService (Phase 11)
- SberTrustPolicy.urlSession ready for GigaChat cloud API (Phase 12)
- MockTrustPolicy ready for testing auth/cloud without real certificates
- Failable init pattern: callers catch TrustPolicyError to gracefully degrade (cloud mode disabled)

## Self-Check: PASSED

- All 4 files verified present on disk
- Commit 994a92e (RED) verified in git log
- Commit 255396f (GREEN) verified in git log

---
*Phase: 10-tls-credentials*
*Completed: 2026-04-12*
