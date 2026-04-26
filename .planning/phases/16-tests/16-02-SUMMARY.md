---
phase: 16-tests
plan: 02
subsystem: benchmark-cloud-infra
tags: [benchmark, python, sber, gigachat, oauth, tls, cloud-infra, ssl-di]

requires:
  - phase: 16-tests/16-DECISIONS
    provides: Q2 product decision (option-b — reuse prod credentials)
  - phase: 13-cloud-llm
    provides: SberAuthService + CloudLLMClient contracts (OAuth + chat/completions)
  - phase: 12-cloud-foundation
    provides: SberRootCA.pem (Минцифры root CA для TLS pinning)
provides:
  - .env.bench gitignored, .env.bench.example template (literal "ВАРИАНТ B")
  - scripts/benchmark-llm-normalization.py --mode cloud (OAuth + chat/completions)
  - load_cloud_credentials / obtain_sber_token / build_cloud_ssl_ctx / estimate_cloud_token_cost
  - request_completion 4-tuple: (text, first_ms, total_ms, usage)
  - cloud_usage_total_tokens aggregate в summary
  - Cost guard: > 50K tokens require --force-cost
affects: [16-03, 16-04, future-cloud-benchmarks]

tech-stack:
  added: []  # Python stdlib only — base64, ssl, uuid (уже доступны)
  patterns:
    - Explicit SSL DI через function параметры (build_cloud_ssl_ctx + cloud_ssl_ctx param)
    - In-process token cache (_SBER_TOKEN_CACHE) с 5min refresh margin (match SberAuthService)
    - 4-tuple usage forwarding (downstream без grep'а логов)

key-files:
  created:
    - .env.bench.example (Sber credentials template, ВАРИАНТ B)
  modified:
    - .gitignore (Phase 16 secrets section: .env.bench + !.env.bench.example)
    - scripts/benchmark-llm-normalization.py (+298 строк cloud branch)

key-decisions:
  - "Q2 = option-b: reuse prod SBER_CLIENT_ID/SBER_CLIENT_SECRET. Risk accepted: bench жгёт ~1% от 2M GigaChat Max budget per run"
  - "Python stdlib only — нет requests/certifi/python-dotenv (CLAUDE.md §Python Conventions)"
  - "SSL ctx через explicit DI (W6) — НЕТ module-level _CLOUD_SSL_CTX/_get_cloud_ssl_ctx"
  - "Non-streaming /chat/completions для cloud — simplicity (research recommends)"
  - "request_completion возвращает 4-tuple включая usage (I8) — local mode возвращает None для usage"

patterns-established:
  - "Pattern: cloud-mode opt-in через --mode флаг с дефолтом local — zero regression existing"
  - "Pattern: token coalesced per-run (один OAuth call на batch, 5min refresh margin)"
  - "Pattern: TLS pinning через ssl.create_default_context(cafile=...) — match Swift SberTrustPolicy"
  - "Pattern: cost guard prompt + --force-cost flag для CI/auto"

requirements-completed:
  - TEST-02

duration: ~25min
completed: 2026-04-25
---

# Phase 16 Plan 02 — Cloud Benchmark Infrastructure

**Benchmark runner расширен на Sber GigaChat cloud backend с TLS pinning, OAuth + usage tracking. Готова инфраструктура для Plan 16-03 запусков (Variant A + Variant B side-by-side).**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-04-25
- **Tasks:** 3 (Task 1 pre-resolved checkpoint, Task 2 + Task 3 executed)
- **Files modified:** 3 (.gitignore, .env.bench.example created, scripts/benchmark-llm-normalization.py)

## Accomplishments

1. **Q2 resolved:** option-b (reuse prod credentials). `.env.bench.example` помечен `ВАРИАНТ B (reuse prod)` с описанием risk acceptance (~1% от 2M GigaChat Max quota per run).
2. **Secrets infrastructure:** `.env.bench` gitignored (defence-in-depth поверх `.env`/`*.key`/`*.pem`), `.env.bench.example` whitelisted и коммитится как template.
3. **Cloud benchmark mode:** scripts/benchmark-llm-normalization.py поддерживает `--mode cloud` через 7 новых CLI args, 4 helper functions, OAuth + Bearer chat/completions, TLS pinning через SberRootCA.pem.

## Q2 Decision Recap

**Answer: option-b (reuse prod)**

Sanya использует те же `SBER_CLIENT_ID` / `SBER_CLIENT_SECRET` из Keychain прод-приложения для benchmark runs. Rationale:
- Не надо тратить 5 минут на создание второго клиента в developers.sber.ru
- Все токены из одной 2M GigaChat Max квоты (общий budget)
- Risk accepted: bench-прогоны могут конкурировать за rate-limit с prod диктовкой если оба активны одновременно
- Researcher оценил ≈20-30K tokens на full run ≈ 1% quota — margin OK

`.env.bench` всё равно остаётся gitignored как defence-in-depth — секреты не попадают в git history.

## Task Commits

Каждая задача committed atomically:

1. **Task 1: [CHECKPOINT] Q2 bench-vs-prod credentials** — pre-resolved by Sanya (см. `.planning/phases/16-tests/16-DECISIONS.md`), не было промпта
2. **Task 2: .gitignore + .env.bench.example template** — `770415f` (chore)
3. **Task 3: benchmark script --mode cloud** — `37a0d30` (feat)

## Files Created/Modified

- **`.env.bench.example`** (created) — Sber GigaChat credentials template, литерал `ВАРИАНТ B (reuse prod)`, ссылка на developers.sber.ru, scope `GIGACHAT_API_PERS`
- **`.gitignore`** — добавлена секция `# Benchmark credentials (Phase 16)` с `.env.bench` + `!.env.bench.example`
- **`scripts/benchmark-llm-normalization.py`** (+298 строк) — cloud mode branch без новых pip deps

## Implementation Highlights

### Surface для Plan 16-03

| Surface | Detail |
|---------|--------|
| Env vars | `SBER_CLIENT_ID`, `SBER_CLIENT_SECRET` (читаются из `.env.bench` по дефолту) |
| TLS pin | `Govorun/Resources/Certificates/SberRootCA.pem` (passed via `--cloud-cert-path`) |
| OAuth | `https://ngw.devices.sberbank.ru:9443/api/v2/oauth`, scope `GIGACHAT_API_PERS` |
| Chat URL | `https://gigachat.devices.sberbank.ru/api/v1/chat/completions` (default `--cloud-base-url`) |
| Cloud model | `GigaChat-2-Max` (default) |
| Token cache | `_SBER_TOKEN_CACHE` dict, 5-min refresh margin, single OAuth call per batch |
| SSL DI | `build_cloud_ssl_ctx(cert_path) -> ssl.SSLContext`, передаётся как `cloud_ssl_ctx` параметр |
| Usage aggregate | `summary["cloud_usage_total_tokens"]` (sum of `usage.total_tokens` across recorded samples) |
| Per-sample usage | `row["usage"] = {prompt_tokens, completion_tokens, total_tokens}` для cloud rows |
| Cost guard | > 50K estimated tokens → prompt `[y/N]` или `--force-cost` |

### W6 — Explicit SSL DI (no module-level state)

`build_cloud_ssl_ctx(cert_path)` строит контекст в `main()`, передаётся как параметр в:
- `obtain_sber_token(ssl_ctx=cloud_ssl_ctx, ...)`
- `request_completion(cloud_ssl_ctx=cloud_ssl_ctx, ...)`

Verified: нет `_CLOUD_SSL_CTX` global, нет `_get_cloud_ssl_ctx()` getter.

### I8 — Usage forwarding (no log grepping)

`request_completion()` теперь возвращает 4-tuple `(text, first_token_ms, total_ms, usage)`:
- Local: `usage = None`
- Cloud: `usage = response_body["usage"]` (dict с `prompt_tokens` / `completion_tokens` / `total_tokens`)

Per-sample row сохраняет `usage` если non-None. Summary aggregates `cloud_usage_total_tokens` из recorded rows. Plan 16-04 BENCHMARK-RESULTS.md читает напрямую без grep'а stderr.

### W4 — `--mode cloud --pipeline-mode full-pipeline --help` exits 0

Verified: argparse layer не падает на cloud + full-pipeline комбинации. Реальные runs (не --help) Plan 16-03 проверит.

## Local Mode Regression — Zero

`request_completion` для local mode сохраняет существующее SSE streaming поведение. Только signature расширена: `return ..., None` (4-й элемент = None для usage). Все 2 callsite в main() обновлены unpack'ом 4-tuple.

`python3 scripts/benchmark-llm-normalization.py --help` показывает все existing args + 7 cloud-specific. `python3 scripts/benchmark-llm-normalization.py --mode local --help` работает identical.

## Decisions Made

- **Q2 → option-b** (Sanya pre-resolved, см. 16-DECISIONS.md)
- **stdlib only**: `base64` + `ssl` + `uuid` добавлены в imports — все Python 3.13 stdlib (нет requests/certifi/python-dotenv per CLAUDE.md)
- **Non-streaming cloud**: research recommends для simplicity; usage возвращается в одном response body

## Deviations from Plan

None — plan executed exactly as written. Все 3 task'и + post-conditions verified.

## Verification Results

| Check | Status |
|-------|--------|
| `ast.parse(...)` | OK (no SyntaxError) |
| `--help` shows --mode/--cloud-*/--force-cost | OK (18 cloud refs) |
| `--mode cloud --pipeline-mode full-pipeline --help` exits 0 | OK (W4) |
| Missing `.env.bench` → BenchmarkConfigurationError, not traceback | OK |
| `git check-ignore .env.bench` matches | OK |
| `git check-ignore .env.bench.example` does NOT match | OK |
| No `_CLOUD_SSL_CTX` global, no `_get_cloud_ssl_ctx()` | OK (W6) |
| `cloud_ssl_ctx` param + `build_cloud_ssl_ctx` helper present | OK (W6) |
| `cloud_usage_total_tokens` in summary cloud branch | OK (I8) |
| `verify=False` absent | OK |
| `cafile=` present (TLS pinning) | OK |
| `GIGACHAT_API_PERS` scope set | OK |
| Local mode `--help` works unchanged | OK |
| Literal "ВАРИАНТ B" in .env.bench.example | OK (W7 literal-match) |

## Next Step

**Plan 16-03** — Q1 checkpoint (resolved BOTH в DECISIONS.md) + benchmark smoke + 4 runs (Variant A local/cloud + Variant B local/cloud). Plan 16-03 reads:
- `SBER_CLIENT_ID`/`SBER_CLIENT_SECRET` из `.env.bench`
- TLS via `--cloud-cert-path Govorun/Resources/Certificates/SberRootCA.pem` (default)
- Token coalesced per-run автоматически
- Aggregate `cloud_usage_total_tokens` в summary для cost audit

Plan 16-04 потом документирует BENCHMARK-RESULTS.md side-by-side.
