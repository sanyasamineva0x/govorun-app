---
phase: 16-tests
plan: 04
subsystem: testing
tags: [phase-close, benchmark-docs, regression-gate, cloud-vs-local, gigachat, variant-b-deferred]

requires:
  - phase: 16-tests/16-01
    provides: +12 тестов (CredentialStoreKeychain 9 + AppStateCloudShim 3 error-paths), 1311 total
  - phase: 16-tests/16-02
    provides: benchmark-llm-normalization.py --mode cloud + .env.bench infra (Q2=B, SSL DI, usage forwarding)
  - phase: 16-tests/16-03
    provides: Three summary JSONs (smoke + local + cloud, 36 samples каждый) committed в .planning/phases/16-tests/benchmark-summaries/
provides:
  - .planning/phases/16-tests/16-BENCHMARK-RESULTS.md (204 lines, full cloud-vs-local comparison + Variant B deferred handoff)
  - Phase 16 closed Complete в ROADMAP.md / REQUIREMENTS.md / STATE.md
  - TEST-01 + TEST-02 traceability rows закрыты Complete
  - 1311 XCTest regression gate PASS post-Phase-16
affects:
  - Phase 17 (Polish & Rollout) — recommendation default-off opt-in (D-07 preserved)
  - Phase 17 / CLOUD-06 — Variant B handoff (audio-in end-to-end + latency)

tech-stack:
  added: []  # docs-only phase close
  patterns:
    - "Pattern: phase-close через RESULTS.md аггрегатов из committed summary JSONs (не raw transcripts) — survive worktree teardown"
    - "Pattern: branch-aware close logic (full / deferred / blocked / a1_failed) — но в этой фазе сработала full ветка"
    - "Pattern: Variant B (audio-in) deferred к будущей фазе через explicit handoff section в RESULTS.md"

key-files:
  created:
    - .planning/phases/16-tests/16-BENCHMARK-RESULTS.md
  modified:
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md
    - .planning/STATE.md

key-decisions:
  - "Branch = full (option-a path): no marker files в build/, Plan 16-03 завершила smoke + local + cloud successfully"
  - "Schema corrected: actual JSONs use .quality.* (не .metrics.*) и .quality.failures[].output (не .got) — RESULTS.md написан под реальную shape"
  - "Per-bucket exact-match читается из field period_tolerant_pct (только этот pct present в bucket structure; on top-level совпадает с exact_match_pct)"
  - "Variant B handoff текст добавлен после Анализа — explicit deferred section с полным rationale (TTS + multipart upload + STT path missing)"
  - "Recommendation для Phase 17: default-off explicit opt-in — neither backend dominates (delta = 0.0 pp aggregate, distributional tradeoff +medium / -long), D-07 privacy consent остаётся обязательным"

patterns-established:
  - "Pattern: identical aggregate ≠ identical quality — cloud +medium / local +long requires per-bucket reporting, not just headline"
  - "Pattern: 4 long-bucket overlap failures (`long-004/005/009/010` оба fail'ят) — сигнал seed/prompt issue, не модельной разницы — кандидаты на Phase 17 follow-up"
  - "Pattern: cloud token budget burn = 19594 / 2_000_000 = ~1% — full benchmark + smoke в одном Phase comfortable для repeated future runs"

requirements-completed:
  - TEST-01
  - TEST-02

duration: ~25min
completed: 2026-04-25
---

# Phase 16 Plan 04 — Phase Close: Benchmark Results + Regression Gate + Roadmap Sync

**Cloud (GigaChat-2-Max) и local (GigaChat 3.1 10B Q4_K_M) показали identical 83.3% exact-match aggregate с distributional tradeoff (cloud +medium 100% / local +long 58.3%). 16-BENCHMARK-RESULTS.md опубликован, full XCTest regression PASS (1311 tests), TEST-01 + TEST-02 закрыты Complete, Variant B (audio-in) deferred к Phase 17 CLOUD-06. Phase 16 → Closed.**

## Performance

- **Duration:** ~25 min wall-clock
- **Started:** 2026-04-25 ~13:18 MSK
- **Completed:** 2026-04-25 ~13:35 MSK
- **Tasks:** 3 executed (Task 1 RESULTS.md, Task 2 regression gate verify-only, Task 3 roadmap close)
- **Files modified:** 4 (1 created — RESULTS.md; 3 modified — ROADMAP/REQUIREMENTS/STATE)

## Accomplishments

1. **16-BENCHMARK-RESULTS.md опубликован** — 204 lines, все required sections: Модели, Результаты, Per-bucket, Cloud token usage, Failures Comparison (3 subsections), Анализ (200-400 word Russian paragraph), Variant B deferred handoff, Рекомендация Phase 17, Reproduction commands, Open Issues, Metadata. Real metrics из committed summary JSONs (no fabrication).
2. **Full XCTest regression gate PASS** — 1311 tests, 0 failures за 59s. Plan 1 +12 новых тестов остаются green; ни один из Plan 2 (Python script extension) и Plan 3 (data-only) изменений не сломал Swift suite.
3. **Phase 16 closed Complete в planning artifacts** — ROADMAP.md Phase 16 checkbox `[x]` + table row 4/4 Complete 2026-04-25; REQUIREMENTS.md TEST-01 + TEST-02 checkboxes flipped + traceability rows updated с full Plan attribution; STATE.md status=phase_complete, progress 6/8→7/8 (87%), 22/22 plans, 4 Phase 16 entries дописаны в Decisions section.
4. **Variant B (audio-in) explicit handoff к Phase 17** — отдельная section в RESULTS.md с rationale почему отложен (TTS-генерация seed audio + расширение runner на STT path + multipart upload — out of Phase 16 scope). REQUIREMENTS.md TEST-02 traceability явно отмечает «Variant B → Phase 17 CLOUD-06».

## Key Metrics Preview (for next-phase reference)

```
LOCAL (GigaChat 3.1 10B Q4_K_M, llama-server, b8500):
  exact_match_pct:        83.3%  (30/36)
  period_tolerant_pct:    83.3%
  errors:                 0
  buckets: short 100% / medium 91.7% / long 58.3%
  6 failures: medium-012, long-001, long-004, long-005, long-009, long-010

CLOUD (GigaChat-2-Max via /chat/completions):
  exact_match_pct:        83.3%  (30/36)
  period_tolerant_pct:    83.3%
  errors:                 0
  cloud_usage_total_tokens: 15046  (~0.75% от 2M Max budget)
  buckets: short 100% / medium 100% / long 50%
  6 failures: long-004, long-005, long-006, long-008, long-009, long-010

Overlap failures (оба fail):  long-004, long-005, long-009, long-010 (4 sample'а, all long-bucket)
Local-only failures:          medium-012, long-001
Cloud-only failures:           long-006, long-008

Total cloud tokens (Phase 16 budget burn):  19 594 / 2 000 000 = 0.98%
```

## Recommendation for Phase 17

**Default-off, explicit opt-in (без изменений).**

- Aggregate quality identical (83.3% оба) — нет основания менять default.
- Distributional tradeoff: cloud +medium / local +long. Ни один не доминирует на ≥5 pp threshold.
- D-07 privacy consent остаётся обязательным (Phase 15 CloudSettingsDisclosure flow).
- Cloud остаётся opt-in feature для power users.
- Variant B (audio-in end-to-end) в Phase 17 CLOUD-06 может изменить баланс — до тех пор статус-кво.

## Task Commits

1. **Task 1: 16-BENCHMARK-RESULTS.md** — `16dd6da` (`docs(16-04): benchmark results cloud vs local + Variant B deferred handoff`)
2. **Task 2: Full XCTest regression gate** — verify-only, 1311 tests PASS, no commit
3. **Task 3: ROADMAP / REQUIREMENTS / STATE close** — `3c828d5` (`docs(16): Phase 16 закрыт — coverage closure + cloud benchmark + Variant B deferred to Phase 17`)

**SUMMARY commit:** будет создан финальным шагом этого плана.

## Files Created/Modified

- `.planning/phases/16-tests/16-BENCHMARK-RESULTS.md` (NEW, 204 lines) — cloud-vs-local quality comparison + Variant B deferred handoff
- `.planning/ROADMAP.md` (MODIFIED) — Phase 16 [x] Complete + 4/4 plans table row + 4 plans listed
- `.planning/REQUIREMENTS.md` (MODIFIED) — TEST-01 + TEST-02 [x] + traceability rows Complete с Variant B → Phase 17 attribution
- `.planning/STATE.md` (MODIFIED) — status phase_complete, frontmatter + Current Position + Decisions section appended (4 Phase 16 entries)

## Decisions Made

- **Branch = full** (option-a path) — Plan 16-03 завершила все 3 runs successfully (smoke + local + cloud), no marker files в build/, RESULTS.md написан по полному template'у.
- **Schema correction applied** — actual JSONs от Plan 2 используют `.quality.*` shape (не `.metrics.*` как описано в PLAN.md). RESULTS.md использует реальные пути; jq queries в Reproduction section работают на actual schema.
- **Per-bucket field handling** — bucket structure имеет только `period_tolerant_pct` (не `exact_match_pct`). На top-level эти поля совпадают (83.3%), и Plan 16-03 SUMMARY уже дал per-bucket exact match через эти числа — RESULTS.md cite'ит values отсюда.
- **Variant B handoff формат** — отдельная section после Анализа, не разбросан по тексту. Полный rationale: что Variant B измерил бы, что нужно для запуска, почему out of scope Phase 16. Также REQUIREMENTS.md TEST-02 row явно указывает «Variant B → Phase 17 CLOUD-06» в статусе Complete.
- **Phase 17 recommendation choice** — из 3 опций (default-on cloud / default-off opt-in / cloud-block) выбрана средняя. Default-on требовал ≥+5 pp delta; cloud-block требовал ≥−5 pp или completed_pct < 90%. Реальный delta = 0.0 pp aggregate с distributional tradeoff — middle path.

## Deviations from Plan

**Минорные — нет блокирующих.**

- **Schema mismatch noted upstream:** PLAN.md писал про `metrics.*` shape, Plan 16-03 SUMMARY уже зафиксировал что actual = `quality.*`. Plan 16-04 prompt тоже корректировал это в `<schema_correction_critical>`. RESULTS.md использует actual schema без проблем.
- **`security dump-keychain` skip** — Plan 1 SUMMARY уже подтвердил `0` записей; Task 2 этой плана повторил sanity-check (`grep -c com.govorun.tests` = 0).
- **Failures Comparison source** — использован `quality.failures` array из committed summary JSONs (содержит expected + output для всех 6 failures с каждой стороны), а не raw `build/*.jsonl`. Этого достаточно для diff'а — формат идентичен.

## Surprise Findings

- **Identical aggregate score (83.3% exact match оба) — структурный сюрприз.** Изначально гипотеза была что cloud (большая модель GigaChat-2-Max) обыграет quantized 10B local на ≥5-10 pp. Реальность — точно такая же aggregate цифра, но с разной distribution. Это говорит, что **выбор LLM-backend меньше влияет на quality, чем предполагалось**, а основной ограничитель — общий промпт + seed. STT-step (Variant B, audio-in) теперь стал higher-priority дифференциатор для Phase 17.
- **4 long-bucket overlap failures** — оба backend'а fail'ят на одних и тех же 4 sample'ах (`long-004/005/009/010`). Это не модельная проблема, а seed/prompt issue: числовые форматы (3 vs три), самокоррекция говорящего, союзы на стыке клауз. Кандидаты на seed audit либо более чёткий промпт в Phase 17.
- **Cloud capitalisation drift** (`long-008` `Demo` vs `demo`) и **предложная форма** (`long-006` `с staging` vs `со staging`) — характерные «причёски» большой LLM. Не показатель ошибки модели сам по себе, скорее кандидаты на «оба варианта acceptable» в matcher'е.

## Retro: что это означает для Phase 17

Identical aggregates говорят, что на text-in symmetric пути cloud не даёт обещанного quality lift. **Это меняет приоритеты Phase 17:**

1. **Variant B (audio-in)** становится higher priority — там Sber STT vs локальный GigaAM differential может быть значительнее, чем LLM-only difference.
2. **Latency p50/p90/p95 measurement** в CLOUD-06 — local p50 ≈ 1.16s vs cloud p50 ≈ 2.07s в этом тексте; для audio path numbers будут иные (Sber comprehensive single round-trip vs local двухступенчатое).
3. **D-07 privacy consent остаётся обязательным** — нет «free quality» оправдания, чтобы релакс'ить consent flow.
4. **Cloud opt-in retains «alternative backend»** позиционирование — не «better quality», а «другой trade-off» (особенно если Sber STT в Variant B окажется заметно better на specific accents/contexts).

## Phase 16 Close Confirmation

| Check | Status |
|-------|--------|
| 16-BENCHMARK-RESULTS.md exists, 204 lines, all sections present | OK |
| Real metrics from committed summary JSONs (no fabrication) | OK (cited values match jq output) |
| Variant B explicit deferred section с handoff к Phase 17 | OK |
| Full XCTest suite PASS — 1311 tests, 0 failures | OK |
| CredentialStoreKeychainTests = 9 functions / AppStateCloudShimTests = 7 functions | OK |
| ROADMAP.md Phase 16 [x] Complete + 4/4 plans + table row 2026-04-25 | OK |
| REQUIREMENTS.md TEST-01 + TEST-02 [x] + traceability rows updated | OK |
| STATE.md frontmatter status=phase_complete + progress 7/8 87% | OK |
| STATE.md Current Position + Decisions section appended | OK |
| Commits на русском, без Co-Authored-By | OK |
| security dump-keychain | grep com.govorun.tests = 0 (Plan 1 hygiene preserved) | OK |

## Next Step

**Phase 17: Polish & Rollout** — следующая фаза в milestone v2.0.

- Resume file: `.planning/ROADMAP.md §Phase 17`
- Recommended next command: `/gsd-discuss-phase 17` (или `/gsd-plan-phase 17` если scope уже ясен)
- Phase 17 incoming requirements: CLOUD-06 (latency + audio-in benchmark Variant B), MODE-04 finalization, error UX polish, analytics events, credential-gated launch behaviour.

После Phase 17 — milestone v2.0 закрыта (8/8 phases) → готов к v2.0 ship.
