# Full Pipeline Product Canon Benchmark

**Дата:** 2026-03-27  
**Железо:** Apple M1, 16 GB RAM, macOS Sequoia  
**Модель:** `GigaChat3.1-10B-A1.8B-q4_K_M.gguf`  
**Endpoint alias:** `gigachat-gguf`  
**Runtime:** `llama-server` (Metal backend)  
**Dataset:** `benchmarks/llm-normalization-seed.jsonl` (36 samples, `expected_full_pipeline`)  
**Prompt source:** production `TextMode.universal`  
**Prompt hash:** `458c7c0a29bbcfce10ceaae711676327e5ed266efe0121b11d476fde8ce3c013`  
**Prompt snapshot:** [2026-03-27-system-prompt-production-product-canon.txt](/Users/sanyasamineva/Desktop/govorun-app/benchmarks/prompts/2026-03-27-system-prompt-production-product-canon.txt)

## Команда

```bash
python3 scripts/benchmark-llm-normalization.py \
  --pipeline-mode full-pipeline \
  --no-terminal-period \
  --base-url http://127.0.0.1:8080/v1 \
  --model gigachat-gguf \
  --dataset benchmarks/llm-normalization-seed.jsonl \
  --text-mode universal \
  --output build/llm-full-pipeline-2026-03-27-product-canon.jsonl \
  --summary build/llm-full-pipeline-2026-03-27-product-canon-summary.json \
  --warmup 0
```

## Latency

Источник: `build/llm-full-pipeline-2026-03-27-product-canon-summary.json`

| Метрика | Все | Short | Medium | Long |
|---------|-----|-------|--------|------|
| p50 total ms | 1067 | 510 | 1059 | 1924 |
| p95 total ms | 2295 | 5661 | 1301 | 2336 |
| max total ms | 11595 | 11595 | 1309 | 2452 |
| p50 first token ms | 461 | 320 | 477 | 529 |
| p95 first token ms | 576 | 5405 | 546 | 585 |

Cold start первого short-запроса дал хвост до `11.6s`. Без него профиль остаётся в районе `~0.5s TTFT` и `~1.0-1.9s total` для прогретого runtime.

## Quality

| Bucket | Exact match | Period-tolerant match |
|--------|-------------|-----------------------|
| Short | 100.0% (12/12) | 100.0% (12/12) |
| Medium | 58.3% (7/12) | 58.3% (7/12) |
| Long | 8.3% (1/12) | 8.3% (1/12) |
| **Итого** | **55.6% (20/36)** | **55.6% (20/36)** |

- Completed: `100% (36/36)`
- Errors: `0`
- Normalization path: `llm=34`, `llmRejected=2`, `llmFailed=0`

## Что поменялось

Этот прогон уже меряет новый продуктовый контракт, а не старый `llm-only` benchmark:
- канон денег: `900 рублей`, а не `900 ₽`
- канон времени: `15:30`, но неоднозначное `в пять` сохраняется как `в пять`
- канон единиц: полные формы вроде `5 килограммов`
- по умолчанию без конечной точки

Поэтому старые headline вроде `53% -> 97%` к текущей архитектуре больше не относятся.

## Что уже хорошо

- Short bucket фактически закрыт: `12/12`.
- Продуктовый канон теперь зафиксирован и воспроизводим через dataset + prompt snapshot.
- Runtime стабилен: `36/36` completed, endpoint errors нет.

## Что ещё ломается

Основные классы оставшихся фейлов:
- command preservation: `Запиши, что ...` и `Скажи, что ...` LLM иногда превращает в обычное сообщение
- correction/context carry-over: `в девять вечера` схлопывается в `в девять`
- structured entities: `А4`, `№1234`, `Jira Server`, `ML-инженер`, кавычки `«Алтай»`
- stylistic rewrites в long-form: перестановки слов, потеря служебных частей, излишняя компрессия

## Вывод

Ветка уже даёт честный benchmark под product canon и показывает реальную картину:
- short-запросы готовы,
- medium-запросы частично готовы,
- long-form пока нет.

Следующий шаг должен идти не в инфраструктуру, а в качество:
1. усилить deterministic owner для structured entities и time-of-day контекста;
2. ужесточить prompt против paraphrase/command drop;
3. перепрогнать `full-pipeline` на том же корпусе.
