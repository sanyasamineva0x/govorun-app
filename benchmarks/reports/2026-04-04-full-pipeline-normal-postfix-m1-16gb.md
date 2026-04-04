# Full Pipeline Benchmark After Date-Year Gate Fix

**Дата:** 2026-04-04  
**Железо:** Apple M1, 16 GB RAM, macOS  
**Модель:** `GigaChat3.1-10B-A1.8B-q4_K_M.gguf`  
**Endpoint alias:** `gigachat-gguf`  
**Runtime:** `llama-server` (Metal backend)  
**Dataset:** `benchmarks/llm-normalization-seed.jsonl` (36 samples)  
**Prompt source:** production `SuperTextStyle.normal`  
**Prompt hash:** `0bfca3fee10a667c0bb7676cdb39bd4878927a04064c569cbd60ca0aab5696ec`

## Что проверяли

Регрессию после фикса, который перестал разбивать год внутри уже нормализованной даты:
- раньше `23 марта 2026` в postflight мог превращаться в `23 марта 2 026`
- из-за этого `NormalizationGate` ложно отклонял LLM output по `missing_protected_tokens(2026)`
- целевой кейс: `medium-006`

## Команда

```bash
python3 scripts/benchmark-llm-normalization.py \
  --pipeline-mode full-pipeline \
  --super-style normal \
  --base-url http://127.0.0.1:8080/v1 \
  --model gigachat-gguf \
  --dataset benchmarks/llm-normalization-seed.jsonl \
  --output build/llm-full-pipeline-normal-2026-04-04-postfix.jsonl \
  --summary build/llm-full-pipeline-normal-2026-04-04-postfix-summary.json \
  --warmup 0
```

## Результат

| Метрика | До фикса | После фикса |
|---|---:|---:|
| Exact match | 77.8% | **80.6%** |
| Period-tolerant match | 77.8% | **80.6%** |
| Short | 100.0% | 100.0% |
| Medium | 83.3% | **91.7%** |
| Long | 50.0% | 50.0% |
| `llmRejected` | 1 | **0** |
| `llm` | 35 | **36** |
| p50 total ms | 1137.14 | **1119.86** |
| p95 total ms | 2330.93 | **2315.65** |

## Итог

Фикс подтвердился benchmark-ом:
- убран ложный reject в `medium-006`
- весь датасет теперь проходит без `llmRejected`
- улучшение качества пришло целиком из medium bucket

Оставшиеся проблемы уже не про gate на дате, а про качество rewrite:
- перестановка слов
- потеря союзов
- слабая self-correction
- long-form punctuation / structure preservation

## Remaining failures (7)

- `medium-012`
- `long-001`
- `long-004`
- `long-005`
- `long-007`
- `long-009`
- `long-010`
