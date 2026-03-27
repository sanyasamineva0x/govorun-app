# Full Pipeline Spec Fixes Benchmark

**Дата:** 2026-03-27  
**Железо:** Apple M1, 16 GB RAM, macOS Sequoia  
**Модель:** `GigaChat3.1-10B-A1.8B-q4_K_M.gguf`  
**Endpoint alias:** `gigachat-gguf`  
**Runtime:** `llama-server` (Metal backend)  
**Dataset:** `benchmarks/llm-normalization-seed.jsonl` (36 samples, `expected_full_pipeline`)  
**Prompt source:** production `TextMode.universal`  
**Prompt hash:** `59a9e51e13c98c2ccd0c6122faa6220f9671a9da237ab4496b45183eade9aaad`  
**Источник summary:** `build/llm-full-pipeline-2026-03-27-spec-fixes-summary.json`

## Команда

```bash
python3 scripts/benchmark-llm-normalization.py \
  --pipeline-mode full-pipeline \
  --no-terminal-period \
  --base-url http://127.0.0.1:8080/v1 \
  --model gigachat-gguf \
  --dataset benchmarks/llm-normalization-seed.jsonl \
  --text-mode universal \
  --output build/llm-full-pipeline-2026-03-27-spec-fixes.jsonl \
  --summary build/llm-full-pipeline-2026-03-27-spec-fixes-summary.json \
  --warmup 0
```

## Что чинили

- `А4` вместо `A4`
- `12,5%` вместо `12,5 процента`
- `7 человек` вместо `семь человек`
- кавычки у названия проекта после `по проекту`

## Дельта к предыдущему prompt-tightened прогону

| Метрика | Было | Стало |
|---------|------|-------|
| Overall period-tolerant | 75.0% | 80.6% |
| Short | 100.0% | 100.0% |
| Medium | 75.0% | 83.3% |
| Long | 50.0% | 58.3% |
| p50 total ms | 1295.5 | 1378.68 |
| p95 total ms | 2687.09 | 2802.05 |

## Что реально закрылось

- `medium-010` — `А4`
- `medium-011` — `7 человек`
- `long-002` — `12,5%`

Кейс `long-001` больше не ломается по кавычкам: `«Алтай»` уже сохраняется.  
Оставшееся расхождение там теперь только по запятым.

## Остаток

Остались `7` failing samples:

- `medium-006`
- `medium-012`
- `long-001`
- `long-004`
- `long-005`
- `long-009`
- `long-010`

Из них только `long-005` всё ещё упирается в numeric style (`три ночи` vs `3 ночи`). Остальные — уже не про deterministic spec, а про command/punctuation/paraphrase contract.
