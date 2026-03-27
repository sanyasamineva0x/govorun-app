# Full Pipeline Production Benchmark

**Дата:** 2026-03-27  
**Железо:** Apple M1, 16 GB RAM, macOS Sequoia  
**Модель:** `GigaChat3.1-10B-A1.8B-q4_K_M.gguf`  
**Endpoint alias:** `gigachat-gguf`  
**Runtime:** `llama-server` (Metal backend)  
**Dataset:** `benchmarks/llm-normalization-seed.jsonl` (36 samples)  
**Prompt source:** production `TextMode.universal`  
**Prompt hash:** `dec2aeb74f4bd4ea7e00368b4cb879510c1d1fc495c71451a7a0cfe4b0e64516`  
**Prompt snapshot:** [2026-03-27-system-prompt-production-head.txt](/Users/sanyasamineva/Desktop/govorun-app/benchmarks/prompts/2026-03-27-system-prompt-production-head.txt)

## Команда

```bash
python3 scripts/benchmark-llm-normalization.py \
  --pipeline-mode full-pipeline \
  --base-url http://127.0.0.1:8080/v1 \
  --model gigachat-gguf \
  --dataset benchmarks/llm-normalization-seed.jsonl \
  --text-mode universal \
  --output build/llm-full-pipeline-2026-03-27.jsonl \
  --summary build/llm-full-pipeline-2026-03-27-summary.json \
  --warmup 0
```

## Latency

Источник: `build/llm-full-pipeline-2026-03-27-summary.json`

| Метрика | Все | Short | Medium | Long |
|---------|-----|-------|--------|------|
| p50 total ms | 1125 | 520 | 1125 | 1998 |
| p95 total ms | 2135 | 863 | 1298 | 2344 |
| max total ms | 2472 | 896 | 1336 | 2472 |
| p50 first token ms | 465 | 320 | 488 | 543 |
| p95 first token ms | 564 | 437 | 555 | 585 |

## Quality

| Bucket | Period-tolerant match |
|--------|-----------------------|
| Short | 58.3% (7/12) |
| Medium | 50.0% (6/12) |
| Long | 8.3% (1/12) |
| **Итого** | **38.9% (14/36)** |

- Exact match: `27.8% (10/36)`
- Completed: `100% (36/36)`
- Normalization path: `llm=30`, `llmRejected=6`, `llmFailed=0`

## Что это значит

Инфраструктурно `full-pipeline` теперь воспроизводим и быстрый enough для локального UX на short/medium фразах.  
Но качество текущего production path для `Говорун Super` пока недостаточное: особенно сыпятся бренды, валюты, единицы измерения, некоторые даты/время и длинные фразы.

Ключевые группы промахов:
- бренды и product names: `Jira`, `Slack`, `Notion`, `Sparkle`, `project.yml`
- числовые и валютные формы: `900 ₽`, `20 000 ₽`, `12,5%`, `15:30`
- длинные фразы: потеря пунктуации, слабая нормализация сложных списков и correction-heavy конструкций

## Коррекция датасета

Для `short-003` добавлено `expected_full_pipeline = "Завтра в пять."`, потому что правило `в пять -> 17:00` сознательно убрано из production contract как небезопасная догадка.

## Verdict

Ветка полезна как инженерный инкремент:
- prompt v3;
- честный benchmark harness;
- full-pipeline helper и report artifacts.

Но мержить это как "LLM normalization quality solved" нельзя.  
Следующий шаг должен идти от этого отчёта: либо усиливать deterministic owner для чисел/валют/времени/брендов, либо менять runtime/prompt под эти конкретные классы ошибок.
