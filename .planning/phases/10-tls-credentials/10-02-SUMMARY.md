---
phase: 10-tls-credentials
plan: 02
subsystem: storage
tags: [security-framework, keychain, credential-store, http-client, dependency-injection]

requires: []
provides:
  - "CredentialStoring protocol (save/get/delete) for Keychain credential persistence"
  - "CredentialStore implementation using Security.framework SecItem* APIs"
  - "HTTPClient protocol with URLSession conformance for testable networking"
  - "MockCredentialStore and MockHTTPClient for testing"
affects: [11-oauth, 12-cloud-llm, 15-settings-ui]

tech-stack:
  added: [Security.framework]
  patterns: [SecItem delete-then-add upsert, protocol-based HTTP injection]

key-files:
  created:
    - Govorun/Storage/CredentialStore.swift
    - Govorun/Services/HTTPClient.swift
    - GovorunTests/CredentialStoreTests.swift
    - GovorunTests/HTTPClientTests.swift
  modified: []

key-decisions:
  - "Single credential pair (clientId+clientSecret) instead of STT/LLM/Legacy split (D-01)"
  - "Security.framework raw SecItem* instead of KeychainAccess SPM dependency (D-03)"

patterns-established:
  - "CredentialStoring: 3-method protocol (save/get/delete) for credential storage"
  - "HTTPClient: single data(for:) async throws protocol with URLSession extension conformance"
  - "Mock pattern: @unchecked Sendable + NSLock + call tracking + error injection"

requirements-completed: [INFRA-03]

duration: 5min
completed: 2026-04-12
---

# Phase 10 Plan 02: Credential Store + HTTP Client Summary

**CredentialStore using raw Security.framework for Keychain persistence and HTTPClient protocol with URLSession conformance for dependency-injectable networking**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-12T11:45:33Z
- **Completed:** 2026-04-12T11:50:51Z
- **Tasks:** 2
- **Files created:** 4

## Accomplishments
- CredentialStoring protocol with 3 methods (save/get/delete) per D-02, single credential pair per D-01
- CredentialStore implementation using SecItemAdd/SecItemCopyMatching/SecItemDelete (D-03) with delete-then-add upsert pattern
- HTTPClient protocol with data(for:) async throws and URLSession extension conformance (D-06)
- MockCredentialStore and MockHTTPClient with call tracking and error injection following project mock patterns
- 14 new tests (9 CredentialStore + 5 HTTPClient), full suite 1152 tests passing with zero regressions

## Task Commits

1. **Task 1: CredentialStore with Security.framework via TDD** - `b027294` (test)
2. **Task 2: HTTPClient protocol with URLSession conformance via TDD** - `1705b40` (test)

## Files Created/Modified
- `Govorun/Storage/CredentialStore.swift` - CredentialStoreError enum, CredentialStoring protocol, CredentialStore (Security.framework), MockCredentialStore
- `Govorun/Services/HTTPClient.swift` - HTTPClient protocol, URLSession extension conformance, MockHTTPClient
- `GovorunTests/CredentialStoreTests.swift` - 9 tests for credential store via mock (save/get/delete/error/tracking/equatable)
- `GovorunTests/HTTPClientTests.swift` - 5 tests for HTTP client (URLSession conformance, mock result/error/tracking/default)

## Decisions Made
- Single credential pair (clientId + clientSecret) simplified from prototype's 7-method STT/LLM/Legacy split (D-01)
- Raw Security.framework SecItem* APIs instead of KeychainAccess SPM dependency -- zero new dependencies (D-03)
- Service name `com.govorun.app.credentials` with `gigachat.clientId` / `gigachat.clientSecret` account keys
- Delete-then-add upsert pattern for SecItemAdd to avoid errSecDuplicateItem (research pitfall #2)
- errSecItemNotFound treated as success on delete (not an error)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- CredentialStoring protocol ready for Phase 11 (SberAuthService) and Phase 15 (Settings UI credential input)
- HTTPClient protocol ready for Phase 11 (SberAuthService) and Phase 12 (CloudLLMClient)
- Both mocks ready for test injection throughout the cloud networking stack

## Self-Check: PASSED

- All 4 source/test files exist on disk
- Commit b027294 (Task 1) verified in git log
- Commit 1705b40 (Task 2) verified in git log
- Full test suite: 1152 tests, 0 failures

---
*Phase: 10-tls-credentials*
*Completed: 2026-04-12*
