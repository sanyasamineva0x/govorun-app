---
phase: 16
slug: tests
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-23
updated: 2026-04-23
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Extracted from `16-RESEARCH.md §Validation Architecture`.

> **Update 2026-04-23 (revision):** Plan 16-03 split into 16-03 (Q1 + smoke + runs) and 16-04 (parse → docs + regression + close) per checker B2.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Apple, bundled with Xcode 15.4) |
| **Config file** | `Govorun.xctestplan` (skips `LLMQualityEvalTests` per existing config) |
| **Quick run command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -only-testing:GovorunTests/{SuiteName}` |
| **Full suite command** | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` |
| **Estimated runtime** | ~70 seconds full suite (baseline 1299 tests) |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -only-testing:GovorunTests/{TouchedTests}` (per-suite filter)
- **After every plan wave:** Run full suite. Must show **1299 + N PASS** where N = new test count for that plan.
- **Before `/gsd-verify-work`:** Full suite green + benchmark dry-run smoke (cloud + local each return at least one result without 500/auth errors)
- **Max feedback latency:** 70s full suite, <5s per targeted suite

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | TEST-01 | unit (TDD) | `xcodebuild test -only-testing:GovorunTests/CredentialStoreKeychainTests` | ❌ Wave 0 | ⬜ pending |
| 16-01-02 | 01 | 1 | TEST-01 | unit | `xcodebuild test -only-testing:GovorunTests/AppStateCloudShimTests` | ✅ | ⬜ pending |
| 16-01-03 | 01 | 1 | TEST-01 | unit (regression) | `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` | ✅ | ⬜ pending |
| 16-02-01 | 02 | 1 | TEST-02 | checkpoint:decision | Sanya product decision (Q2 bench-credentials) | N/A | ⬜ pending |
| 16-02-02 | 02 | 1 | TEST-02 | file-exists + W7 cross-check | `git check-ignore .env.bench && test -f .env.bench.example && grep -qE "ВАРИАНТ [AB]" .env.bench.example` (option letter matches Task 1) | ❌ Wave 0 | ⬜ pending |
| 16-02-03 | 02 | 1 | TEST-02 | CLI smoke + W4/W6/I8 | `python3 scripts/benchmark-llm-normalization.py --mode cloud --pipeline-mode full-pipeline --help` exits 0 (W4) + `! grep -q "_CLOUD_SSL_CTX" scripts/benchmark-llm-normalization.py` (W6) + `grep -q "cloud_ssl_ctx" scripts/benchmark-llm-normalization.py` (W6 DI param) + `grep -q "response_body.get(.usage.)" scripts/benchmark-llm-normalization.py` (I8) | ❌ Wave 0 | ⬜ pending |
| 16-03-01 | 03 | 2 | TEST-02 | checkpoint:decision | Sanya product decision (Q1 benchmark scope: option-a/b/c) | N/A | ⬜ pending |
| 16-03-02 | 03 | 2 | TEST-02 | benchmark run (orchestrator-routed per Q1) | option-a: `python3 scripts/benchmark-llm-normalization.py --mode {local,cloud}` exits 0 + smoke + local + cloud summary JSONs present + `cloud_usage_total_tokens > 0`. option-b: `build/bench-blocker.txt` created. option-c: `build/bench-deferred.txt` created. (W3: verify uses `exit 1` not `exit 0`; W5: option-c skip handled at orchestrator precondition layer, not in action body) | N/A | ⬜ pending |
| 16-04-01 | 04 | 3 | TEST-02 | doc generation (branch-aware) | `test -f .planning/phases/16-tests/16-BENCHMARK-RESULTS.md`. Branch "full": ≥60 lines + sections (Модели/Результаты/Per-bucket/Cloud token usage/Failures/Анализ/Рекомендация/Reproduction/Metadata) + `cloud_usage_total_tokens` cited (I8). Branch "deferred"/"blocked"/"a1_failed": ≥20 lines + marker section + handoff. | N/A | ⬜ pending |
| 16-04-02 | 04 | 3 | TEST-01, TEST-02 | regression gate | Full XCTest suite PASS — `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation` shows «Test Suite 'All tests' passed» + ≥1311 tests | N/A | ⬜ pending |
| 16-04-03 | 04 | 3 | TEST-02 | roadmap close (branch-aware) | `grep -E "TEST-01.*Complete\|TEST-02.*(Complete\|Partial)" .planning/REQUIREMENTS.md && grep -E "Phase 16.*(Complete\|Partial)\|16 (CLOSED\|PARTIAL)" .planning/STATE.md && grep -E "^\s*- \[[x~]\] \*\*Phase 16\|16\. Tests" .planning/ROADMAP.md` | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `GovorunTests/CredentialStoreKeychainTests.swift` — new file, covers TEST-01 (real Keychain impl)
- [ ] Extend `GovorunTests/AppStateCloudShimTests.swift` — covers TEST-01 error propagation paths
- [ ] `scripts/benchmark-llm-normalization.py` — extend with `--mode cloud` flag + OAuth/TLS helpers + explicit SSL DI (W6) + usage forwarding (I8) + cloud+full-pipeline arg parse (W4) (Plan 2)
- [ ] `.env.bench.example` — template (no real secrets), option letter matches Q2 (W7)
- [ ] `.gitignore` — add `.env.bench` explicit line (defence-in-depth; existing `.env` pattern already matches)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real Sber API round-trip in benchmark | TEST-02 | Requires live credentials + internet + token budget | After Plan 2 ships, Sanya creates `.env.bench` from developers.sber.ru keys; Plan 3 Task 2 runs `python3 scripts/benchmark-llm-normalization.py --mode cloud` and collects results |
| Q2 bench-vs-prod credentials decision | TEST-02 | Product decision (scope + trust boundary) | Plan 2 Task 1 blocking checkpoint — Sanya answers A (separate client) or B (reuse prod) |
| Q1 benchmark scope (text-symmetric vs audio-asymmetric vs defer) | TEST-02 | Product decision (what the benchmark measures) | Plan 3 Task 1 blocking checkpoint — Sanya picks option-a/b/c. Orchestrator routes Plan 3 Task 2 based on this answer (W5). |
| A1 validation (GigaChat-2-Max supports text-in via /chat/completions без attachment) | TEST-02 | Requires real API call to validate | Plan 3 Task 2 dry-run — 3 sample text-in requests; smoke summary persisted as `build/smoke-cloud-summary.json` |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (checkpoints are explicit manual gates)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (every implementation task has per-suite xcodebuild filter or jq validation)
- [x] Wave 0 covers all MISSING references (CredentialStoreKeychainTests, benchmark script extensions, `.env.bench.example`)
- [x] No watch-mode flags (xcodebuild is single-shot)
- [x] Feedback latency < 70s (full suite; <5s per-suite filter)
- [x] `nyquist_compliant: true` set in frontmatter
- [x] **B2 split applied:** Plan 16-03 split into 16-03 (Q1 + smoke + runs) and 16-04 (docs + regression + roadmap close); map updated above
- [x] **W3 fix:** Plan 16-03 verify uses `exit 1` (not `exit 0`) on missing summaries
- [x] **W4 fix:** Plan 16-02 Task 3 acceptance includes `--mode cloud --pipeline-mode full-pipeline --help` exits 0
- [x] **W5 fix:** Plan 16-03 Task 2 option-c skip routed via orchestrator precondition (not internal action branching)
- [x] **W6 fix:** Plan 16-02 Task 3 uses explicit DI (`build_cloud_ssl_ctx` + `cloud_ssl_ctx` param) instead of module-level `_CLOUD_SSL_CTX`
- [x] **W7 fix:** Plan 16-02 Task 2 acceptance includes option letter cross-check (Q2 answer ↔ template letter)
- [x] **I8 applied:** `request_completion` returns 4-tuple with `usage`; per-sample row + summary forward `cloud_usage_total_tokens`; Plan 16-04 reads it directly (no log greps)

**Approval:** approved 2026-04-23 — plan-checker iteration 2 PASS (all 7 issues resolved, 0 new)
</content>
</invoke>
