# Phase 16: Tests — Context

**Gathered:** 2026-04-23 (lite mode — Sanya «летим», discuss-phase skipped per product decision)
**Status:** Ready for planning
**Source:** Inline brief by orchestrator after Phase 15 close

<domain>
## Phase Boundary

Завершить test coverage для всего Cloud-стека и сделать quality benchmark cloud-vs-local. Пхаза подчищает тестовый долг v2.0 перед Phase 17 Polish & Rollout.

**In scope:**
- Аудит существующих unit-тестов для cloud-сервисов (SberAuthService, CloudLLMClient, CredentialStore, SberTrustPolicy, AppStateCloudShim, CloudSettingsErrorMessage)
- Заполнение coverage-gaps если аудит найдёт
- Repair или замена `scripts/benchmark-full-pipeline-helper.swift` (сломан после удаления TextMode в v1.0)
- Запуск cloud-vs-local benchmark на существующем eval seed
- Документирование результатов benchmark в `.planning/phases/16-tests/16-BENCHMARK-RESULTS.md`

**Out of scope:**
- Integration / E2E тесты с живым Sber API (live UAT в Phase 15 уже подтвердил end-to-end через network-уровень)
- UI-тесты (XCUITest) — отложены до публичного релиза
- Performance benchmark (latency p50/p90/p95) — это аналитика рантайма, см. Phase 17 (CLOUD-06)

</domain>

<decisions>
## Implementation Decisions

### Test coverage policy
- **Audit-first:** не добавлять тесты вслепую. Сначала анализ существующих 69 тестов, потом таргетированное закрытие gaps.
- **Mock-only:** unit-тесты не делают сетевых вызовов. `MockHTTPClient`, `MockAuthService`, `MockTrustPolicy` уже есть.
- **Coverage targets per service** (минимум):
  - SberAuthService — happy path, token expiry, refresh, retry, parse errors, credentialsNotFound (✓ 17 тестов — выглядит достаточно)
  - CloudLLMClient — upload (WAV), chat, attachments, retry, cancellation, error mapping (✓ 24 теста — достаточно после моих H-01 добавлений)
  - CredentialStore — save/get/delete, Keychain errors (✓ 9 тестов — проверить что edge cases закрыты)
  - SberTrustPolicy — match `*.sberbank.ru`, fallback на system CA (✓ 15 тестов — достаточно)
  - AppStateCloudShim — saveCloudCredentials, deleteCloudCredentials, probeCloudConnection (✓ 4 теста — может быть мало, проверить)
  - CloudSettingsErrorMessage / cloudErrorMessage(for:) — все AuthError/LLMError кейсы → user copy

### Benchmark methodology
- **Dataset:** существующий eval seed (`scripts/benchmark-llm-normalization.py` или его эквивалент в репо). Если seed устарел или мал — **остановиться и спросить Sanya**, не выдумывать.
- **Models compared:** `GigaChat-2-Max` (cloud) vs `GigaChat 3.1 10B-A1.8B Q4_K_M` (local llama-server)
- **Metric:** zero-edit rate (% выходных строк, не требующих ручной правки) — основной. Token diff / character-level edit distance — secondary.
- **Scoring:** automatic via diff против ground-truth в seed. Если ground-truth недостаточен или субъективен — flag для human eval (out of scope).
- **Threshold:** не зашивать «cloud должен быть не хуже local на X%» — записать results, дать Sanya решить про Phase 17 rollout.

### Benchmark script repair
- **UPDATE 2026-04-23 per RESEARCH.md:** `benchmark-full-pipeline-helper.swift` на самом деле **НЕ сломан** — researcher скомпилил через `xcrun swiftc` и прогнал smoke-test успешно. TextMode уже замигрирован на SuperTextStyle, legacy `--text-mode` alias работает. Initial memory-based assumption был устаревшим. Repair task отменён.
- `benchmark-llm-normalization.py` — основной runner, должен поддержать `--mode cloud|local`. Cloud путь делает реальные вызовы к Sber API → требует sourced credentials (`.env.bench` или прямые args, **не коммитить ключи**). Researcher оценил integration в ~80-100 строк Python.

### Безопасность тестов
- Bench-credentials отдельно от prod (developers.sber.ru → создать второй клиент или использовать тот же — Sanya решает)
- `.env.bench` в `.gitignore`
- Benchmark-результаты можно коммитить (агрегаты), сами audio + transcripts — нет (PII)

### Claude's Discretion
- Точные имена test-файлов и функций
- Структура BENCHMARK-RESULTS.md
- Конкретный shape новых mock-helpers если понадобятся

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing test infrastructure
- `GovorunTests/CloudLLMClientTests.swift` — 24 tests, паттерн SequentialMockHTTPClient
- `GovorunTests/SberAuthServiceTests.swift` — 17 tests
- `GovorunTests/CredentialStoreTests.swift` — 9 tests
- `GovorunTests/SberTrustPolicyTests.swift` — 15 tests
- `GovorunTests/AppStateCloudShimTests.swift` — 4 tests
- `GovorunTests/CloudSettingsErrorMessageTests.swift` — `cloudErrorMessage(for:)` coverage
- `Govorun/Services/HTTPClient.swift` — содержит `MockHTTPClient`
- `Govorun/Services/SberAuthService.swift` — содержит `MockAuthService`

### Benchmark infrastructure
- `scripts/benchmark-llm-normalization.py` — существующий runner на eval seed
- `scripts/benchmark-full-pipeline-helper.swift` — **СЛОМАН** после удаления TextMode

### Phase context
- `.planning/phases/15-cloud-settings-ui/15-REVIEW.md` + `15-REVIEW-FIX.md` — что закрыто на Phase 15
- `.planning/phases/14-pipeline-hardening/` — pipeline integration patterns
- `CLAUDE.md` — Conventions §Testing, §Mock injection через protocols

### Project decisions
- `.planning/PROJECT.md` — общий контекст продукта
- `.planning/ROADMAP.md` Phase 16 success criteria

</canonical_refs>

<specifics>
## Specific Ideas

- Audit может выдать «coverage достаточен → benchmark only». Это валидный исход, не насиловать тесты ради счёта.
- Benchmark должен быть **повторяемым** — фиксированный seed, deterministic temperature (0 для местного, 0.1 для cloud по умолчанию — задокументировать)
- Cloud calls в benchmark стоят токены — посчитать примерный cost при N тестов на eval seed перед запуском, surface Sanya если > 50K токенов

</specifics>

<deferred>
## Deferred Ideas

- XCUITest для CloudSettingsDisclosure flows (UAT-J VoiceOver) — pre-release pass
- Latency p50/p90/p95 cloud vs local — Phase 17 (CLOUD-06)
- Live integration tests с реальным Sber sandbox — too costly, не нужно

</deferred>

---

*Phase: 16-tests*
*Context gathered: 2026-04-23 lite-mode*
