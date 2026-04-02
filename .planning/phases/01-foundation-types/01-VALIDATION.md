---
phase: 01
slug: foundation-types
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-29
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (system, Xcode 26.4) |
| **Config file** | `Govorun.xctestplan` |
| **Quick run command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests -only-testing:GovorunTests/SuperStyleEngineTests` |
| **Full suite command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command (SuperTextStyleTests + SuperStyleEngineTests)
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | STYLE-01 | unit | `-only-testing:GovorunTests/SuperTextStyleTests` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | STYLE-02 | unit | `-only-testing:GovorunTests/SuperTextStyleTests` | ❌ W0 | ⬜ pending |
| 01-01-03 | 01 | 1 | STYLE-03 | unit | already covered by NormalizationGateTests | ✅ existing | ⬜ pending |
| 01-01-04 | 01 | 1 | STYLE-04 | unit | `-only-testing:GovorunTests/SuperTextStyleTests` | ❌ W0 | ⬜ pending |
| 01-01-05 | 01 | 1 | STYLE-05 | unit | `-only-testing:GovorunTests/SuperTextStyleTests` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | ENGINE-01 | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | ENGINE-02 | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | ❌ W0 | ⬜ pending |
| 01-02-03 | 02 | 1 | ENGINE-03 | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | ❌ W0 | ⬜ pending |
| 01-02-04 | 02 | 1 | ENGINE-04 | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | ❌ W0 | ⬜ pending |
| 01-02-05 | 02 | 1 | ENGINE-05 | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | ❌ W0 | ⬜ pending |
| 01-01-T1 | 01 | 1 | TEST-01 | unit | `-only-testing:GovorunTests/SuperTextStyleTests` | ❌ W0 | ⬜ pending |
| 01-02-T2 | 02 | 1 | TEST-02 | unit | `-only-testing:GovorunTests/SuperStyleEngineTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `GovorunTests/SuperTextStyleTests.swift` — stubs for STYLE-01, STYLE-02, STYLE-04, STYLE-05, TEST-01
- [ ] `GovorunTests/SuperStyleEngineTests.swift` — stubs for ENGINE-01..05, TEST-02

*No framework install needed. XCTest is system-provided. No conftest/shared fixtures needed — tests are self-contained.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
