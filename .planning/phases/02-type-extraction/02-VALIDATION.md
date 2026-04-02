---
phase: 2
slug: type-extraction
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-30
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in, Swift 5.10) |
| **Config file** | `Govorun.xctestplan` |
| **Quick run command** | `xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Full suite command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`
- **After every plan wave:** Run `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | EXTRACT-01 | compilation | `xcodebuild build ...` | N/A (compilation) | ⬜ pending |
| 02-01-02 | 01 | 1 | EXTRACT-02 | compilation | `xcodebuild build ...` | N/A (compilation) | ⬜ pending |
| 02-01-03 | 01 | 1 | EXTRACT-03 | unit (existing) | `xcodebuild test ...` | ✅ existing 986+ tests | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new tests needed — the success criterion is that ALL existing 986+ tests pass without modification (beyond removing `textMode:` from test constructors).

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
