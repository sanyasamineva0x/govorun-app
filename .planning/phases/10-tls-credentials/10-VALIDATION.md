---
phase: 10
slug: tls-credentials
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-12
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest |
| **Config file** | `Govorun.xctestplan` |
| **Quick run command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests` |
| **Full suite command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick test command
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | TBD | INFRA-01 | — | PEM loads via Security.framework | unit | `xcodebuild test` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | INFRA-02 | — | URLSession trusts *.sberbank.ru, rejects other custom CAs | unit | `xcodebuild test` | ❌ W0 | ⬜ pending |
| TBD | TBD | TBD | INFRA-03 | — | Keychain save/get/delete roundtrip | unit | `xcodebuild test` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `GovorunTests/SberTrustPolicyTests.swift` — stubs for INFRA-01, INFRA-02
- [ ] `GovorunTests/CredentialStoreTests.swift` — stubs for INFRA-03
- [ ] `GovorunTests/HTTPClientTests.swift` — protocol conformance tests

*Existing XCTest infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SberRootCA.pem in app bundle | INFRA-01 | Build artifact check | Build DMG, verify `Govorun.app/Contents/Resources/SberRootCA.pem` exists |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
