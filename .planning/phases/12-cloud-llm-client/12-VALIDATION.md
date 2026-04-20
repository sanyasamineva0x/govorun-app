---
phase: 12
slug: cloud-llm-client
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-12
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift) |
| **Config file** | `Govorun.xctestplan` |
| **Quick run command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/CloudLLMClientTests` |
| **Full suite command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command (CloudLLMClient tests)
- **After every plan wave:** Run full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | CLOUD-06 | — | N/A | unit | `xcodebuild test -only-testing:GovorunTests/CloudLLMConfigurationTests` | ❌ W0 | ⬜ pending |
| 12-01-02 | 01 | 1 | CLOUD-01 | — | N/A | unit | `xcodebuild test -only-testing:GovorunTests/CloudLLMClientTests/testUploadAudio` | ❌ W0 | ⬜ pending |
| 12-01-03 | 01 | 1 | CLOUD-02 | — | N/A | unit | `xcodebuild test -only-testing:GovorunTests/CloudLLMClientTests/testChatCompletions` | ❌ W0 | ⬜ pending |
| 12-01-04 | 01 | 1 | CLOUD-03 | — | N/A | unit | `xcodebuild test -only-testing:GovorunTests/CloudLLMClientTests/testProcessAudio` | ❌ W0 | ⬜ pending |
| 12-01-05 | 01 | 1 | CLOUD-06 | — | Retry with backoff | unit | `xcodebuild test -only-testing:GovorunTests/CloudLLMClientTests/testRetry` | ❌ W0 | ⬜ pending |
| 12-01-06 | 01 | 1 | CLOUD-01 | — | AuthError→LLMError | unit | `xcodebuild test -only-testing:GovorunTests/CloudLLMClientTests/testErrorMapping` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `GovorunTests/CloudLLMClientTests.swift` — test stubs for CLOUD-01, CLOUD-02, CLOUD-03, CLOUD-06
- [ ] `GovorunTests/CloudLLMConfigurationTests.swift` — configuration defaults and validation tests

*Existing test infrastructure (XCTest, mocks via protocols) covers all framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| GigaChat API audio round-trip | CLOUD-03 | Requires live API credentials and network | Upload WAV via processAudio, verify normalized text returned |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
