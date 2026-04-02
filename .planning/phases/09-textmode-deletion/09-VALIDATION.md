---
phase: 9
slug: textmode-deletion
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift) |
| **Config file** | `Govorun.xctestplan` |
| **Quick run command** | `xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Full suite command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`
- **After every plan wave:** Run `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | DELETE-01 | grep + build | `grep -rn "TextMode" --include="*.swift" Govorun/` | ✅ | ⬜ pending |
| 09-01-02 | 01 | 1 | DELETE-02 | grep + build | `grep -rn "AppModeOverriding" --include="*.swift" Govorun/` | ✅ | ⬜ pending |
| 09-01-03 | 01 | 1 | DELETE-03 | grep + build | `grep -rn "resolveTextMode\|defaultAppModes" --include="*.swift" Govorun/` | ✅ | ⬜ pending |
| 09-02-01 | 02 | 2 | DELETE-04 | unit test | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| HistoryView old entries show no style badge | DELETE-04 | Visual verification | Open history, check entries with old TextMode values show no badge |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
