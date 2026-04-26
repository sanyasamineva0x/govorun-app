---
phase: 16-tests
plan: 03
subsystem: benchmark-execution
tags: [benchmark, cloud, gigachat, sber, llm-normalization, quality-comparison]

requires:
  - phase: 16-tests/16-DECISIONS
    provides: Q1 product decision (option-a — text-in symmetric; Variant B deferred to Phase 17 per orchestrator decision)
  - phase: 16-tests/16-02
    provides: scripts/benchmark-llm-normalization.py --mode cloud (OAuth + chat/completions, TLS pinning, usage forwarding)
  - phase: 12-cloud-foundation
    provides: SberRootCA.pem (Минцифры root CA для TLS pinning)
provides:
  - .planning/phases/16-tests/benchmark-summaries/smoke-cloud-summary.json (A1 validation, 3 samples)
  - .planning/phases/16-tests/benchmark-summaries/bench-local-2026-04-25-summary.json (local baseline, 36 samples)
  - .planning/phases/16-tests/benchmark-summaries/bench-cloud-2026-04-25-summary.json (cloud full, 36 samples, 15046 tokens)
affects:
  - Phase 16-04 (RESULTS.md generation, regression gate, roadmap close)
  - Phase 17 (CLOUD-06: latency p50/p90/p95 + Variant B audio-in benchmark — deferred handoff)

tech-stack:
  added: []
  patterns:
    - "Pattern: smoke-first cloud benchmark (3 samples) → full run (36 samples), фиксирует A1 assumption перед тратой full quota"
    - "Pattern: aggregate summary JSONs копируются в .planning/phases/<phase>/benchmark-summaries/ — переживают worktree teardown, no raw transcripts"

key-files:
  created:
    - .planning/phases/16-tests/benchmark-summaries/smoke-cloud-summary.json
    - .planning/phases/16-tests/benchmark-summaries/bench-local-2026-04-25-summary.json
    - .planning/phases/16-tests/benchmark-summaries/bench-cloud-2026-04-25-summary.json
  modified: []

key-decisions:
  - "Q1 = option-a (text-in symmetric) per orchestrator pre-resolution; Variant B (audio-in asymmetric) DEFERRED to Phase 17 (overrides earlier `BOTH` decision in 16-DECISIONS.md per Sanya's check at execution start)"
  - "A1 assumption (GigaChat-2-Max accepts text-only chat/completions) VALIDATED — smoke run 3 samples returned non-empty output, errors=0, cloud_usage_total_tokens=4548"
  - "Per-sample raw .jsonl и .log файлы не коммитятся (build/ gitignored, содержат transcripts); только аггрегаты с failure ID + bucket + expected/output копируются в .planning/ — все failure тексты — public seed"
  - "Schema note: actual summary использует `quality.{errors,exact_match_pct,...}` (не `metrics.*`) — PLAN.md verify-script описывал `.metrics.errors` shape, но реальная структура от Plan 2 — `.quality.errors`. Plan 16-04 при чтении должен использовать `.quality`."

patterns-established:
  - "Pattern: cloud-vs-local symmetric LLM benchmark на 36-sample text seed — same prompt SHA-256 (b23cc0df...), same super-style, same dataset, разный backend"
  - "Pattern: --force-cost для CI/auto-runs — smoke + full < 50K threshold (~20K total), prompt-skip OK"

requirements-completed: []  # TEST-02 closes в Plan 16-04

# Metrics
duration: ~3 min (3 sequential runs: smoke ~30s + local ~1m + cloud ~1.5m)
completed: 2026-04-25
---

# Phase 16 Plan 03 — Cloud-vs-Local Benchmark Execution

**Cloud (GigaChat-2-Max) и local (GigaChat 3.1 10B Q4) показали одинаковый exact-match score 83.3% на 36-sample text-in seed; cloud сильнее на medium (100% vs 91.7%), local сильнее на long (58.3% vs 50%). Полная honest comparison собрана; Plan 16-04 генерирует RESULTS.md и закрывает Phase 16.**

## Performance

- **Duration:** ~3 min (sequential runs)
- **Started:** 2026-04-25 ~13:10 MSK
- **Completed:** 2026-04-25 ~13:14 MSK
- **Tasks:** 1 executed (Task 2; Task 1 — pre-resolved checkpoint)
- **Files committed:** 3 summary JSONs

## Q1 Resolution

**Answer: option-a (text-in symmetric)** — pre-resolved per orchestrator's check with Sanya.

### Rationale recap (from preresolved_checkpoint брифа orchestrator'а)
- Honest LLM-quality comparison, apples-to-apples
- Использует existing seed без extension
- ~1-2 hours of work для full run
- Cheap по токенам (smoke + full = ~20K total)

### Variant B (audio-in asymmetric) — DEFERRED to Phase 17
- Хотя `.planning/phases/16-tests/16-DECISIONS.md` ранее зафиксировал «BOTH (a + b)», orchestrator выяснил у Sanya на старте execution, что Variant B → Phase 17 (CLOUD-06 уже планирует latency + audio-in).
- Plan 16-04 документирует Variant B как deferred handoff в `16-BENCHMARK-RESULTS.md` (per orchestrator brief).

## Accomplishments

1. **A1 assumption VALIDATED:** smoke run 3 samples через `/chat/completions` text-in без attachments → 100% completion, errors=0, cloud_usage_total_tokens=4548. GigaChat-2-Max принимает text-only contract.
2. **Local baseline:** 36 samples за ~37s, 30/36 exact match (83.3%), 0 errors. Bucket break: short 100%, medium 91.7%, long 58.3%.
3. **Cloud full run:** 36 samples за ~85s, 30/36 exact match (83.3%), 0 errors, 15046 tokens (~0.75% от 2M GigaChat Max budget). Bucket break: short 100%, medium 100%, long 50%.
4. **Three summary JSONs survive worktree teardown:** скопированы в `.planning/phases/16-tests/benchmark-summaries/` (committed), Plan 16-04 читает с устойчивых путей.

## Task Commits

1. **Task 1: [CHECKPOINT] Q1 — benchmark scope** — pre-resolved by Sanya (см. orchestrator brief + `16-DECISIONS.md` + execution-start check). Не было промпта.
2. **Task 2: smoke + local + cloud benchmark runs** — three runs выполнены, summary JSONs скопированы и закоммичены одной chore-commit.

## Files Created/Modified

- **`.planning/phases/16-tests/benchmark-summaries/smoke-cloud-summary.json`** (created) — 3-sample A1 validation artifact, mode=cloud, errors=0, cloud_usage_total_tokens=4548
- **`.planning/phases/16-tests/benchmark-summaries/bench-local-2026-04-25-summary.json`** (created) — 36-sample local baseline, mode=local, errors=0, exact_match_pct=83.3
- **`.planning/phases/16-tests/benchmark-summaries/bench-cloud-2026-04-25-summary.json`** (created) — 36-sample cloud full, mode=cloud, errors=0, exact_match_pct=83.3, cloud_usage_total_tokens=15046

Per-sample `build/*.jsonl` + `*.log` остались в `build/` (gitignored — содержат raw transcripts, PII-adjacent). Будут потеряны при worktree teardown — это ожидаемо (Plan 16-04 работает с аггрегатами).

## Key Metrics Preview (для Plan 16-04 reference)

```
LOCAL (GigaChat 3.1 10B Q4, llama-server):
  exact_match_pct:        83.3%  (30/36)
  period_tolerant_pct:    83.3%
  errors:                 0
  buckets:
    short:  100.0% (12)   — все правильно
    medium:  91.7% (12)   — 1 ошибка на medium-012 (порядок слов: «опоздаю минут на 15» vs «опоздаю на 15 минут»)
    long:    58.3% (12)   — 5 ошибок (запятые, формат «три ночи» vs «3 ночи», явные слова «нужно/надо», числовые форматы «11:00» vs «11»)

CLOUD (GigaChat-2-Max via /chat/completions):
  exact_match_pct:        83.3%  (30/36)
  period_tolerant_pct:    83.3%
  errors:                 0
  cloud_usage_total_tokens: 15046  (~0.75% от 2M Max quota)
  buckets:
    short:  100.0% (12)
    medium: 100.0% (12)   — cloud win vs local 91.7%
    long:    50.0% (12)   — cloud loss vs local 58.3% (6 ошибок: capitalisation «Demo», предлоги «с/со», числовые форматы)

Identical aggregate score (83.3% exact match) с разным распределением ошибок:
  - Cloud решает medium-012 правильно, но добавляет 1 ошибку в long-006 («с staging» vs «со staging») и long-008 (capitalisation Demo).
  - Local fails medium-012 + long-001 (запятая после «Алтай»).
  - Overlap failures (оба fail): long-004, long-005, long-009, long-010 — 4 sample'а, все long-bucket.
```

## A1 Validation Status: PASS

Smoke summary contents:
```json
{
  "mode": "cloud",
  "cloud_model": "GigaChat-2-Max",
  "cloud_usage_total_tokens": 4548,
  "total_samples": 3,
  "quality": { "errors": 0, "completed": 3, "exact_match_pct": 100.0 }
}
```

Per-sample row schema confirmed: `output` field (не `got`, как описано в PLAN.md loose wording) содержит cloud-нормализованный текст. Все 3 samples returned non-empty `output`. SSL/OAuth/contract — OK.

## Token Usage Summary

| Run | Tokens (cloud only) | % of 2M Max budget |
|-----|---------------------|--------------------|
| Smoke (3 samples) | 4548 | 0.23% |
| Cloud full (36 samples) | 15046 | 0.75% |
| **Total** | **19594** | **0.98%** |

Margin OK — Plan 16-04 не требует cloud calls.

## Decisions Made

- **Q1 → option-a** (orchestrator pre-resolved override of earlier BOTH decision in `16-DECISIONS.md`)
- **Variant B → deferred** (Phase 17 CLOUD-06 уже планирует audio-in + latency)
- **Summary JSONs commit'нуты в `.planning/phases/16-tests/benchmark-summaries/`** — survive worktree teardown, читаются Plan 16-04 с stable paths
- **Per-sample .jsonl + .log не коммитятся** — gitignored в `build/`, raw transcripts могут содержать PII-adjacent material (всё-таки failures showcase prompt examples которые public seed, но raw rows содержат timestamps/latency что не value-add для results doc)

## Deviations from Plan

- **Schema mismatch в plan's verify-script:** PLAN.md verify-script ожидает `jq -e '.metrics.errors <= 2'`, но actual schema (от Plan 2) использует `.quality.errors`. Реальные значения OK (errors=0 в обоих full runs), но automated verify-script в PLAN.md не пройдёт. Plan 16-04 при чтении JSONs должен использовать `.quality`. **Не блокер для closure** — данные корректны, smoke + 2 full runs всё успешные.
- **Per-sample field name:** PLAN.md mentions «non-empty `got`», actual jsonl row uses `output` + `llm_output`. Cosmetic — данные есть.

Этих расхождений недостаточно чтобы блокировать Plan 3 — они известные wording differences между планом и Plan 2 implementation. Plan 16-04 будет читать `.quality` напрямую.

## Verification Results

| Check | Status |
|-------|--------|
| Smoke cloud summary exists, mode=cloud, errors=0, cloud_usage_total_tokens>0 | OK |
| Local baseline summary exists, mode=local, 36 samples, errors=0 | OK |
| Cloud full summary exists, mode=cloud, 36 samples, errors=0, cloud_model=GigaChat-2-Max | OK |
| `cloud_usage_total_tokens > 0` (Plan 2 I8 forwarding) | OK (4548 + 15046) |
| No SSL/auth failures | OK (smoke + 2 fulls — 0 errors) |
| `metrics.errors ≤ 2` (per acceptance) | OK (0 в обоих) — schema is `.quality.errors`, value is 0 |
| `completed_pct ≥ 90.0` для cloud | OK (100%) |
| 36 samples в каждом full run | OK |
| `.env.bench` не модифицирован | OK |
| Никаких credentials в summary JSONs | OK (grep `secret\|client_id\|bearer\|token=` empty) |
| `build/*.jsonl` + `*.log` НЕ коммитнуты | OK (gitignored) |
| Summary JSONs скопированы в .planning/ | OK (committed) |
| STATE.md / ROADMAP.md не модифицированы | OK |

## Next Step

**Plan 16-04** — финальный plan фазы:
- Парсит 3 JSONs из `.planning/phases/16-tests/benchmark-summaries/` → `16-BENCHMARK-RESULTS.md`
- Side-by-side таблица local vs cloud, per-bucket breakdown, failure overlap analysis
- Документирует Variant B (audio-in) как deferred handoff в Phase 17 (CLOUD-06)
- Запускает full XCTest regression gate (986+ тестов)
- Закрывает TEST-02, обновляет STATE.md / ROADMAP.md

Plan 16-04 не требует cloud network calls — работает с уже сохранёнными аггрегатами.
