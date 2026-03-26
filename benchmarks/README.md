# LLM Normalization Benchmarks

Seed-корпус для уровня 0 из `docs/llm-normalization-roadmap.md`.

## Что внутри

- `llm-normalization-seed.jsonl` — стартовый набор short / medium / long фраз.

Формат строки:

```json
{"id":"short-001","bucket":"short","input":"ну привет","expected":"Привет."}
```

`expected` нужен для ручной оценки качества и будущего offline scorer, но текущий benchmark harness его не валидирует автоматически.

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

Для временного override из приложения:
- `GOVORUN_LLM_BASE_URL`
- `GOVORUN_LLM_MODEL`
- `GOVORUN_LLM_TIMEOUT`
- `GOVORUN_LLM_HEALTHCHECK_TIMEOUT`
