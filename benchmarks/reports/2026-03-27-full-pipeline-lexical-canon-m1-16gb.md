# Full Pipeline Lexical Canon Follow-up

**Дата:** 2026-03-27  
**Железо:** Apple M1, 16 GB RAM, macOS Sequoia  
**Модель:** `GigaChat3.1-10B-A1.8B-q4_K_M.gguf`  
**Endpoint alias:** `gigachat-gguf`  
**Runtime:** `llama-server` (Metal backend)  
**Prompt source:** production `TextMode.universal`  
**Prompt hash:** `dec2aeb74f4bd4ea7e00368b4cb879510c1d1fc495c71451a7a0cfe4b0e64516`

## Что изменилось

В deterministic-слой добавлен встроенный lexical canon:
- бренды: `Jira`, `Slack`, `Notion`, `Telegram`, `GitHub`, `Zoom`, `Sparkle`
- тех-термины: `PDF`, `CSV`, `iOS`, `ML`, `QA`
- phrase-level формы: `Jira Server`, `project.yml`, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `Sparkle-обновление`

## Команда

```bash
python3 scripts/benchmark-llm-normalization.py \
  --pipeline-mode full-pipeline \
  --base-url http://127.0.0.1:8080/v1 \
  --model gigachat-gguf \
  --dataset benchmarks/llm-normalization-seed.jsonl \
  --text-mode universal \
  --output build/llm-full-pipeline-2026-03-27-lexical-canon.jsonl \
  --summary build/llm-full-pipeline-2026-03-27-lexical-canon-summary.json \
  --warmup 0
```

## Результат

| Metric | До lexical canon | После lexical canon |
|--------|-------------------|---------------------|
| Period-tolerant overall | 38.9% (14/36) | 47.2% (17/36) |
| Exact overall | 27.8% (10/36) | 30.6% (11/36) |
| Short bucket | 58.3% | 83.3% |
| Medium bucket | 50.0% | 50.0% |
| Long bucket | 8.3% | 8.3% |
| `llmRejected` | 6 | 4 |

Latency этого прогона хуже baseline из-за cold-start outlier на первом запросе:
- `p50 total = 1285 ms`
- `p95 total = 2616 ms`
- `first-token p50 = 526 ms`
- `max total = 13349 ms`

## Что реально починилось

Сразу ушли типовые lexical misses:
- `жиру -> Jira`
- `слак -> Slack`
- `ноушн -> Notion`
- `github -> GitHub`
- `телеграм -> Telegram`

Это подняло short bucket почти до приемлемого состояния без изменений prompt.

## Что всё ещё болит

Следующие классы ошибок не закрываются одним lexical canon:
- время и даты: `15:30`, `18:00`, `21:00`, `23 марта 2026`
- units normalization: `5 кг`, `2 л`
- числовой стиль: часть ожиданий в dataset ещё про `₽`, тогда как product canon уже смещается к `рублей`
- длинные фразы: punctuation, restructuring, correction-heavy кейсы

## Вывод

Deterministic lexical canon — правильный следующий owner-слой: он даёт быстрый measurable gain и не зависит от prompt.  
Но для `Говорун Super` этого недостаточно. Следующий рациональный шаг — добить deterministic canonical spec для:
- времени и дат
- единиц измерения
- денежного/процентного формата под продуктовый канон
