---
phase: 16
status: resolved
recorded: 2026-04-25
---

# Phase 16 — Product Decisions (resolved by Sanya)

## Q2 (Plan 16-02 Task 1) — Bench-vs-prod credentials

**Answer: B (reuse prod credentials)**

- Использовать те же `SBER_CLIENT_ID` / `SBER_CLIENT_SECRET` что в Keychain прод-приложения для benchmark runs
- `.env.bench` всё равно создаётся как gitignored файл (defence-in-depth, secrets out of git)
- Plan 16-02 Task 2 → `.env.bench.example` помечен как «ВАРИАНТ B (reuse prod)»
- Risk accepted: бенчмарковые прогоны жгут токены из общего prod-budget (2M GigaChat Max free)
  - Researcher оценил ≈20-30K tokens на full run = ≈1% quota — margin ОК

## Q1 (Plan 16-03 Task 1) — Benchmark scope

**Answer: BOTH (a + b)** — оба варианта, side-by-side

### Variant A — Text-in symmetric
- Input: text-only (existing seed transcripts)
- Local path: `text → llama-server (GigaChat 3.1 10B Q4) → normalized text`
- Cloud path: `text → /chat/completions (GigaChat-2-Max) → normalized text`
- Что меряем: качество **LLM-нормализации** при равном входе → честное сравнение моделей

### Variant B — Audio-in asymmetric (full-pipeline)
- Input: audio (WAV from existing seed audio history, если есть; иначе — TTS-генерируем)
- Local path: `audio → Python STT worker (GigaAM-v3) → text → llama-server → normalized text`
- Cloud path: `audio → /files upload (WAV) → /chat/completions (one-shot) → normalized text`
- Что меряем: **end-to-end pipeline quality** — Sber STT vs локальный + comparable LLM normalization

### Reporting
- Plan 16-04 (16-BENCHMARK-RESULTS.md) должен содержать **обе таблицы**: Variant A side-by-side и Variant B side-by-side
- Per-bucket breakdown для каждого варианта
- Cross-variant analysis: какая разница в zero-edit-rate между A и B (tells us how much of cloud's win/loss is LLM vs STT)

## Implications for plan execution

- Plan 16-03 теперь делает **4 прогона** вместо 2:
  1. local --mode local --pipeline-mode llm-only (Variant A local)
  2. cloud --mode cloud --pipeline-mode llm-only (Variant A cloud)
  3. local --mode local --pipeline-mode full-pipeline (Variant B local)
  4. cloud --mode cloud --pipeline-mode full-pipeline (Variant B cloud)
- Token cost x2 (≈40-60K tokens total cloud) — всё ещё в margin прод-бюджета
- Plan 16-04 documentation scope x2 — две side-by-side таблицы плюс analysis
- Plan 16-03 Task 2 timing: ~10-15 min (4 runs × ~2-4 min каждый, sequential)
