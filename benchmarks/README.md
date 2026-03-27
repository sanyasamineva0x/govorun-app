# LLM Normalization Benchmarks

Seed-корпус для уровня 0 из `docs/llm-normalization-roadmap.md`.

## Что внутри

- `llm-normalization-seed.jsonl` — стартовый набор short / medium / long фраз.

Формат строки:

```json
{"id":"short-001","bucket":"short","input":"ну привет","expected":"Привет."}
```

`expected` нужен для ручной оценки качества и будущего offline scorer, но текущий benchmark harness его не валидирует автоматически.

Для `full-pipeline` режима можно добавить отдельное ожидаемое поле:

```json
{"id":"short-003","bucket":"short","input":"завтра в пять","expected":"Завтра в 17:00.","expected_full_pipeline":"Завтра в 5:00."}
```

Это нужно, потому что в новой архитектуре числа, валюты, время и даты нормализует deterministic слой ДО LLM.

## Как запускать

Подними локальный OpenAI-compatible endpoint, например `llama-server`, затем:

Дефолты в приложении и benchmark одинаковые:
- base URL: `http://127.0.0.1:8080/v1`
- model: `gigachat-gguf`

Если `llama-server` уже установлен, можно поднять endpoint так:

```bash
MODEL_PATH=/path/to/gigachat.gguf \
bash scripts/run-gigachat-llm.sh
```

```bash
python3 scripts/benchmark-llm-normalization.py \
  --base-url http://127.0.0.1:8080/v1 \
  --model gigachat-gguf \
  --dataset benchmarks/llm-normalization-seed.jsonl \
  --output build/llm-normalization-benchmark-results.jsonl \
  --summary build/llm-normalization-benchmark-summary.json
```

Если хочешь замерять RSS сервера:

```bash
python3 scripts/benchmark-llm-normalization.py \
  --server-pid <PID>
```

Результат:
- per-sample JSONL с output и latency;
- агрегированный JSON summary с `p50`, `p95`, `first token latency`.

## Full Pipeline

Если хочешь мерить продуктовый путь, а не только сырой LLM contract:

```bash
python3 scripts/benchmark-llm-normalization.py \
  --pipeline-mode full-pipeline \
  --base-url http://127.0.0.1:8080/v1 \
  --model local-model \
  --dataset benchmarks/llm-normalization-seed.jsonl \
  --text-mode universal \
  --output build/llm-normalization-full-pipeline.jsonl \
  --summary build/llm-normalization-full-pipeline-summary.json
```

В этом режиме harness:
- генерирует production system prompt из текущего `TextMode`;
- прогоняет `raw input -> DeterministicNormalizer -> LLM -> NormalizationGate -> final output`;
- сравнивает `output` с `expected_full_pipeline`, если оно есть, иначе с `expected`.

Если нужен старый чистый `llm-only` замер, оставь `--pipeline-mode llm-only` или не указывай флаг вовсе.

Для временного override из приложения:
- `GOVORUN_LLM_BASE_URL`
- `GOVORUN_LLM_MODEL`
- `GOVORUN_LLM_TIMEOUT`
- `GOVORUN_LLM_HEALTHCHECK_TIMEOUT`
