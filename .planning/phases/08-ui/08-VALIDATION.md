---
phase: 8
slug: ui
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in, Xcode 15.4) |
| **Config file** | `Govorun.xctestplan` |
| **Quick run command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperTextStyleTests -only-testing:GovorunTests/SettingsSectionTests` |
| **Full suite command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Estimated runtime** | ~45 seconds (full suite, 986+ tests) |

---

## Sampling Rate

- **After every task commit:** Run quick command (SuperTextStyleTests + SettingsSectionTests)
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~15 seconds (targeted tests)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 0 | UI-01 | unit | `xcodebuild test ... -only-testing:GovorunTests/SettingsSectionTests/test_textStyle_in_visibleCases` | ❌ W0 | ⬜ pending |
| 08-01-02 | 01 | 0 | UI-02 | unit | `xcodebuild test ... -only-testing:GovorunTests/SuperTextStyleTests/test_superStyleMode_displayName` | ❌ W0 | ⬜ pending |
| 08-01-03 | 01 | 0 | UI-03 | unit | `xcodebuild test ... -only-testing:GovorunTests/SuperTextStyleTests/test_cardDescription_all_styles` | ❌ W0 | ⬜ pending |
| 08-02-01 | 02 | 1 | UI-01 | unit | `xcodebuild test ... -only-testing:GovorunTests/SettingsSectionTests` | ❌ W0 | ⬜ pending |
| 08-02-02 | 02 | 1 | UI-02..04 | manual | N/A (SwiftUI view rendering) | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `GovorunTests/SettingsSectionTests.swift` — stubs for UI-01 (textStyle in visibleCases, correct title/subtitle/icon) and UI-04 (model state coverage)
- [ ] Extend `GovorunTests/SuperTextStyleTests.swift` — stubs for UI-02 (SuperStyleMode.displayName) and UI-03 (SuperTextStyle.cardDescription for all 3 styles)

*No framework install needed — XCTest is built-in.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| StyleCard visual appearance, checkmark position | UI-03 | SwiftUI view rendering not unit-testable | Build DMG, open Settings → Стиль текста, verify 3 cards with checkmark |
| Disabled overlay with blur/opacity | UI-04 | Visual overlay effect requires visual inspection | Build DMG, ensure no model, verify overlay covers cards but not picker |
| Auto/Manual segment content transition | UI-02 | Animation and content switch is visual | Build DMG, toggle Авто/Ручной, verify content changes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
