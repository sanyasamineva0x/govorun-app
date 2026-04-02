---
phase: 4
slug: gate-modernization
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-31
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest |
| **Config file** | `Govorun.xctestplan` |
| **Quick run command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/NormalizationGateTests` |
| **Full suite command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Estimated runtime** | ~45 seconds (quick), ~120 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run quick run command (NormalizationGateTests only)
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | GATE-01 | unit | `xcodebuild test -only-testing:GovorunTests/NormalizationGateTests` | ✅ | ⬜ pending |
| 04-01-02 | 01 | 1 | GATE-02 | unit | `xcodebuild test -only-testing:GovorunTests/NormalizationGateTests` | ✅ | ⬜ pending |
| 04-01-03 | 01 | 1 | GATE-03 | unit | `xcodebuild test -only-testing:GovorunTests/NormalizationGateTests` | ✅ | ⬜ pending |
| 04-01-04 | 01 | 1 | GATE-04 | unit | `xcodebuild test -only-testing:GovorunTests/NormalizationGateTests` | ✅ | ⬜ pending |
| 04-02-01 | 02 | 1 | TEST-04 | unit | `xcodebuild test -only-testing:GovorunTests/NormalizationGateTests` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. NormalizationGateTests.swift already exists with 21 tests.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
