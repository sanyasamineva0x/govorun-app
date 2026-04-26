# Phase 16: Benchmark Results — Cloud vs Local Quality

**Дата:** 2026-04-25
**Железо:** Apple M1, 16 GB RAM, macOS 14.x (Sanya's M1)
**Dataset:** `benchmarks/llm-normalization-seed.jsonl` (36 samples)
**Pipeline mode:** full-pipeline (postflight applied)
**Super style:** normal
**Методология:** text-in symmetric (per Q1 = option-a, см. `16-DECISIONS.md` + Plan 16-03)
**Prompt SHA-256:** `b23cc0df7cd0e94dfe51ef8b45e2c6bb7365dda2d50d31421217863361a8019a` (одинаковый для обоих backend'ов)

## Модели

| Параметр | Local | Cloud |
|----------|-------|-------|
| Model | GigaChat 3.1 10B-A1.8B Q4_K_M | GigaChat-2-Max |
| Runtime | llama-server (llama.cpp `b8500`), Metal + BLAS | Sber API (`https://gigachat.devices.sberbank.ru/api/v1`) |
| Endpoint alias | `gigachat-gguf` (HTTP localhost) | `/chat/completions` (TLS pin SberRootCA.pem) |
| Temperature | 0 | 0.1 (Sber default) |
| Max tokens | 128 | 128 |
| Stop | `["\n\n"]` | — (Sber контракт не принимает stop) |
| Streaming | SSE (server-sent events) | non-streaming (Plan 16-02 simplicity choice) |
| Timeout | 30s | 30s |

## Результаты (полные метрики)

| Метрика | Local | Cloud | Δ (cloud − local) |
|---------|------:|------:|------------------:|
| Exact match | 83.3% | 83.3% | 0.0 pp |
| Period-tolerant match | 83.3% | 83.3% | 0.0 pp |
| Completed (no error) | 100.0% | 100.0% | 0.0 pp |
| Errors | 0 | 0 | — |
| Total samples | 36 | 36 | — |

**Aggregate score: identical** (30/36 exact match для обоих backend'ов).

## Per-bucket breakdown

| Bucket | Samples | Local exact | Cloud exact | Δ (cloud − local) |
|--------|--------:|------------:|------------:|------------------:|
| Short  | 12 | 100.0% | 100.0% | 0.0 pp |
| Medium | 12 | 91.7%  | 100.0% | +8.3 pp |
| Long   | 12 | 58.3%  | 50.0%  | −8.3 pp |

Aggregate match вводит в заблуждение — cloud сильнее на medium-bucket (+8.3 pp), но слабее на long-bucket (−8.3 pp); short-bucket насыщен (100% оба).

## Cloud token usage

| Run | Tokens (cloud only) | % from 2M Max budget |
|-----|--------------------:|--------------------:|
| Smoke (3 samples, A1 validation) | 4 548 | 0.23% |
| Cloud full (36 samples) | 15 046 | 0.75% |
| **Phase 16 total** | **19 594** | **0.98%** |

- Avg per cloud sample: ≈418 tokens (15 046 / 36).
- Остаток free quota GigaChat Max: ≈1 980 406 / 2 000 000 (~99.0% свободно).
- Cost equivalent: N/A — Sber дал 2M токенов GigaChat Max free tier для cloud-версии Говоруна (см. `project_gigachat_cloud.md` в auto-memory). Production-pricing открыто Sber'ом не публикуется в текущем контракте.

Источник цифр: поле `cloud_usage_total_tokens` в summary JSON, forwarded из API per-sample `usage.total_tokens` (Plan 16-02 I8 — без greppinga логов).

## Failures Comparison

В обоих backend'ах ровно по 6 failures из 36; с тремя зонами пересечения. Все expected/output ниже взяты из `quality.failures[]` массивов в committed summary JSONs (`.planning/phases/16-tests/benchmark-summaries/`). Per-sample raw `.jsonl` файлы остались в `build/` (gitignored, PII-adjacent), но aggregate failure block уже содержит expected + output для всех ID — этого достаточно для diff'а.

### Cloud-only failures (local PASS, cloud FAIL) — 2 sample'а

| ID | Bucket | Тип ошибки |
|----|--------|------------|
| `long-006` | long | Выбор предлога: «**со** staging» (expected) vs «**с** staging» (cloud output) |
| `long-008` | long | Capitalisation: «**demo**» (expected, lowercase) vs «**Demo**» (cloud output) |

`long-006` expected: `Скажи, что по инциденту №1234 нужно поднять логи со staging, проверить интеграцию со Slack и ответить клиенту до 15:00`
`long-006` cloud:    `Скажи, что по инциденту №1234 нужно поднять логи с staging, проверить интеграцию со Slack и ответить клиенту до 15:00`

`long-008` expected: `Подготовь текст: demo прошло хорошо, но клиент просит добавить экспорт в PDF, офлайн-режим и синхронизацию со своим Jira Server`
`long-008` cloud:    `Подготовь текст: Demo прошло хорошо, но клиент просит добавить экспорт в PDF, офлайн-режим и синхронизацию со своим Jira Server`

### Local-only failures (cloud PASS, local FAIL) — 2 sample'а

| ID | Bucket | Тип ошибки |
|----|--------|------------|
| `medium-012` | medium | Порядок слов: «опоздаю **минут на 15**» (expected) vs «опоздаю **на 15 минут**» (local output) |
| `long-001`   | long   | Запятые: пропущены перед «потому что» и «и» (local output) |

`medium-012` expected: `Напиши в Telegram, что я опоздаю минут на 15`
`medium-012` local:    `Напиши в Telegram, что я опоздаю на 15 минут`

`long-001` expected: `Давай перенесём встречу по проекту «Алтай», потому что Иванов не может сегодня, и предложим четверг после обеда`
`long-001` local:    `Давай перенесём встречу по проекту «Алтай» потому что Иванов не может сегодня и предложим четверг после обеда`

### Both failed (failures в обоих backend'ах) — 4 sample'а, все long-bucket

| ID | Тип ошибки (общий шаблон) |
|----|---------------------------|
| `long-004` | Cloud + local оба добавили лишний фрагмент «не в среду, а» поверх expected — expected предписывает уже стёртое самокоррекцией продолжение |
| `long-005` | Cloud: формат числа «**три ночи**» (expected: «**3 ночи**»); local: «**три ночи**» + «,» вместо «и» |
| `long-009` | Cloud: «в 11» (expected: «в 11:00»); local: формат + сжимание клаузы |
| `long-010` | Cloud + local оба пропустили союз «и» в начале фрагмента «и в целом всё окей» |

Все 4 общих failures сидят в long-bucket, типичные шаблоны — числовая форма (3 vs три), пропуск союзов/запятых на стыке клауз и частичная самокоррекция говорящего, которую LLM не воспроизводит дословно.

## Анализ

Aggregate exact-match scores cloud (GigaChat-2-Max) и local (GigaChat 3.1 10B Q4_K_M) совпали с точностью до 0.0 pp — оба нормализатора прошли 30 из 36 sample'ов. Из этого можно было бы наивно заключить, что выбор backend'а безразличен; реальная картина устроена тоньше.

На **medium-bucket** cloud вырвался вперёд — 100.0% против 91.7% у local'а: единственная медиум-ошибка (`medium-012`) у local'а — это перестановка «опоздаю минут на 15» vs «опоздаю на 15 минут». Quantized 10B-модель на этом перефразировании поскользнулась, а GigaChat-2-Max (большая модель) сохранил исходную аппроксимативную формулировку с «минут на».

На **long-bucket** обратная картина — local 58.3% vs cloud 50.0%. Cloud добавил две новых ошибки которых не было у local'а: capitalisation «Demo» (`long-008`, expected lowercase «demo») и предлог «**с** staging» вместо «**со** staging» (`long-006`). Это типичные английские/корпоративные привычки LLM большего масштаба — он «причёсывает» названия и применяет более стандартную предложную форму.

**Самое важное наблюдение** — 4 sample'а из long-bucket fail'ятся в обоих backend'ах одинаково (`long-004`, `long-005`, `long-009`, `long-010`). Это не разница LLM, это структурная проблема seed'а или промпта: длинные клаузы с самокоррекцией («не в среду, а в четверг» — `long-004`), числовые форматы (`3 ночи` vs `три ночи` — `long-005`), пропуск союзов на стыках («и в целом всё окей» — `long-010`). Ни одна из двух моделей не может уверенно угадать, какую именно из равноправных вариаций прописал human-аннотатор. Эти 4 sample'а кандидаты на (a) пересмотр в seed'е, (b) более чёткие directives в системном промпте по числовым форматам / самокоррекции, либо (c) приём рассматривать оба варианта как acceptable (расширенный period_tolerant fuzz).

Latency ortogonal'на качеству и здесь не определяющая (cloud имеет p50 ≈ 2.07s vs local p50 ≈ 1.16s — cloud медленнее), но Phase 17 (CLOUD-06) измерит latency p50/p90/p95 более внимательно с end-to-end audio path.

## Variant B (audio-in asymmetric) — Deferred to Phase 17

Phase 16 выполнила **Variant A** (text-in symmetric): тот же текстовый input идёт и в local llama-server, и в Sber `/chat/completions`. Это изолирует «качество LLM-нормализации» от STT-различий.

**Variant B** (audio-in asymmetric — audio через Python STT worker → local llama-server; audio через Sber `/files` upload → cloud `/chat/completions`) показал бы end-to-end pipeline quality, но требует:

- TTS-генерации 36 audio-файлов из seed (или sourcing existing recordings).
- Расширения `scripts/benchmark-llm-normalization.py` для multipart upload в `/files` + audio-attached `/chat/completions`.
- Local STT-пути через benchmark runner (текущий runner работает text-only).

Это новая работа, выходящая за scope Phase 16. Передаётся в Phase 17 (CLOUD-06 latency/quality), где end-to-end audio benchmark уже планируется.

Преамбула в `.planning/phases/16-tests/16-DECISIONS.md` («BOTH a + b») была overridden orchestrator'ом по запросу Sanya на старте execution Plan 16-03 — «Execute A-only сейчас, B → Phase 17». Plan 16-03 SUMMARY это явно фиксирует.

## Рекомендация для Phase 17 (CLOUD-06 rollout)

Aggregate quality identical, distributional tradeoff чистый: cloud +medium / local +long. Ни один backend не доминирует достаточно убедительно, чтобы оправдать смену default'а. Поэтому:

**Рекомендация: Default-off, explicit opt-in (без изменений).**

- Cloud остаётся opt-in feature через Phase 15 CloudSettingsDisclosure flow с D-07 privacy consent.
- D-07 consent сохраняется как обязательная гарантия privacy (audio + text → серверы Sber).
- UI copy в Phase 17 не должна делать «cloud рекомендуется для лучшего качества» — данных для такого утверждения нет.
- Альтернативные варианты (default-on cloud, либо cloud-block) **отвергнуты** — для default-on нужна была бы delta ≥ +5 pp (нет), для блока — < −5 pp или completed_pct < 90% (тоже нет).
- Phase 17 Variant B (audio-in end-to-end) может изменить баланс, если Sber STT окажется заметно лучше/хуже локального GigaAM. До тех пор статус-кво.

## Reproduction

```bash
# Preflight (один раз):
# - Sanya создала .env.bench с SBER_CLIENT_ID и SBER_CLIENT_SECRET (Q2 = option-b, reuse prod)
# - llama-server запущен: bash scripts/run-gigachat-llm.sh (или GigaChat 3.1 GGUF модель loaded в порту 8080)

# Local baseline (Variant A, text-in):
python3 scripts/benchmark-llm-normalization.py \
  --mode local --pipeline-mode full-pipeline \
  --base-url http://127.0.0.1:8080/v1 --model gigachat-gguf \
  --super-style normal --warmup 0 \
  --output build/bench-local-$(date +%Y-%m-%d).jsonl \
  --summary build/bench-local-$(date +%Y-%m-%d)-summary.json

# Cloud comparison (Variant A, text-in via /chat/completions):
python3 scripts/benchmark-llm-normalization.py \
  --mode cloud --pipeline-mode full-pipeline \
  --super-style normal --warmup 0 --force-cost \
  --output build/bench-cloud-$(date +%Y-%m-%d).jsonl \
  --summary build/bench-cloud-$(date +%Y-%m-%d)-summary.json

# Side-by-side aggregate comparison:
jq -s '{
  local_quality: .[0].quality,
  cloud_quality: .[1].quality,
  cloud_tokens:  .[1].cloud_usage_total_tokens
}' \
  build/bench-local-$(date +%Y-%m-%d)-summary.json \
  build/bench-cloud-$(date +%Y-%m-%d)-summary.json
```

Per-bucket breakdown (для side-by-side):

```bash
jq '.buckets | with_entries(.value |= {samples, period_tolerant_pct})' \
  .planning/phases/16-tests/benchmark-summaries/bench-local-2026-04-25-summary.json
jq '.buckets | with_entries(.value |= {samples, period_tolerant_pct})' \
  .planning/phases/16-tests/benchmark-summaries/bench-cloud-2026-04-25-summary.json
```

## Open Issues / Follow-ups

- **4 long-bucket samples fail в обоих backend'ах** (`long-004`, `long-005`, `long-009`, `long-010`) — структурные seed-проблемы, не модельные. Кандидаты на review в Phase 17 либо отдельный seed-аудит:
  - Числовые форматы: «3 ночи» vs «три ночи» — нужна или директива в промпте, или toleration в matcher'е.
  - Самокоррекция говорящего: «не в среду, а в четверг» — обе модели предпочитают финальный фрагмент, expected требует сохранить full thought.
  - Союзы/запятые на стыке: пропуск «и», «потому что» — оба нормализатора удаляют как redundant.
- **Cloud capitalisation drift** (`long-008` `Demo` vs `demo`) — характерная для большой модели «причёска» названий. Можно или оговорить в промпте «сохраняй capitalisation», или принять как acceptable variance.
- **Cloud предложная форма** (`long-006` `с staging` vs `со staging`) — формальная грамматика; LLM-2-Max выбирает короче. Та же категория «оба корректны».
- **Variant B (audio-in)** — handoff в Phase 17 (CLOUD-06).

## Metadata

- **Benchmark script:** `scripts/benchmark-llm-normalization.py` (расширен в Plan 16-02 на `--mode cloud`)
- **Seed version:** `benchmarks/llm-normalization-seed.jsonl` (36 samples, prompt-source production `SuperTextStyle.normal`)
- **Q1 resolution:** option-a (text-in symmetric) — Plan 16-03 Task 1, orchestrator pre-resolved per Sanya 2026-04-25 (override of earlier «BOTH» в `16-DECISIONS.md`)
- **Q2 resolution:** option-b (reuse prod credentials) — Plan 16-02 Task 1, Sanya 2026-04-25 (см. `16-DECISIONS.md`)
- **Infrastructure:** Plan 16-02 (`.env.bench` gitignored, TLS pinning через `SberRootCA.pem`, OAuth scope `GIGACHAT_API_PERS`, explicit SSL DI per W6)
- **Cloud usage forwarding:** per-sample `usage.total_tokens` (Plan 16-02 I8) → aggregate `cloud_usage_total_tokens` в summary JSON
- **Summary JSON paths (committed in repo):**
  - `.planning/phases/16-tests/benchmark-summaries/smoke-cloud-summary.json` (3 samples, A1 validation)
  - `.planning/phases/16-tests/benchmark-summaries/bench-local-2026-04-25-summary.json` (36 samples local)
  - `.planning/phases/16-tests/benchmark-summaries/bench-cloud-2026-04-25-summary.json` (36 samples cloud)
- **Per-sample raw transcripts:** `build/*.jsonl` + `*.log` остались в gitignored `build/` (PII-adjacent, не коммитятся)
- **XCTest suite после Phase 16:** 1311 tests (1299 baseline + 9 CredentialStoreKeychainTests + 3 AppStateCloudShim error-path tests, см. `16-01-SUMMARY.md`)
- **Variant B handoff:** Phase 17 / CLOUD-06 — audio-in end-to-end benchmark + latency p50/p90/p95
