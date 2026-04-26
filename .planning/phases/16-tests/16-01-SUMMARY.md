---
phase: 16-tests
plan: 01
subsystem: testing
tags: [xctest, keychain, credentialstore, appstate, cloud-coverage, tdd]

requires:
  - phase: 11-cloud-auth
    provides: CredentialStore + AppStateCloudShim (saveCloudCredentials/deleteCloudCredentials/probeCloudConnection)
  - phase: 15-cloud-settings-ui
    provides: AppStateCloudShimTests (4 baseline тестов)
provides:
  - Реальная Keychain integration coverage для CredentialStore — 9 тестов через unique service-identifier (UUID-suffix per test)
  - Error-path тесты для AppStateCloudShim — проброс CredentialStoreError + non-AuthError → networkError wrap
  - DI-точка `init(serviceOverride: String? = nil)` в CredentialStore (production callsites не затронуты)
affects:
  - Phase 16-02 (benchmark runner) — coverage closure базис
  - Phase 17 polish & rollout — confidence на shim error paths

tech-stack:
  added: []
  patterns:
    - "DI через optional override-parameter с default nil — zero-regression для production callsites"
    - "Unique service-identifier per test (UUID-suffix) — изолирует blast radius от production Keychain"

key-files:
  created:
    - GovorunTests/CredentialStoreKeychainTests.swift
  modified:
    - Govorun/Storage/CredentialStore.swift
    - GovorunTests/AppStateCloudShimTests.swift

key-decisions:
  - "Option A (serviceOverride DI) выбрана вместо Option B (tearDown-cleanup на shared service) — изоляция между тестами без shared state, не загрязняет production Keychain"
  - "AppState.swift не редактировался — research был прав, 3 error-path теста прошли GREEN сразу (saveCloudCredentials throws через try, deleteCloudCredentials throws через try, probeCloudConnection уже оборачивает non-AuthError в .networkError catch-block lines 393-398)"
  - "Keys.service переименован в Keys.defaultService — namespace остаётся, имя теперь честнее отражает роль (default override target, не единственное значение)"

patterns-established:
  - "Pattern: `serviceOverride: String? = nil` для Keychain DI — analogous SettingsStore UserDefaults suite-name override (CLAUDE.md §Settings/UserDefaults)"
  - "Pattern: `try? store.delete()` в tearDown — обязательная подчистка Keychain entries даже на упавших тестах"
  - "Pattern: `DispatchQueue.concurrentPerform` для concurrency stress-test через NSLock — финальный get() возвращает один из записанных вариантов"

requirements-completed: [TEST-01]

duration: 12min
completed: 2026-04-25
---

# Phase 16 Plan 1: Coverage Closure Summary

**Закрыты GAP-A (CredentialStore Keychain integration) и GAP-B (AppStateCloudShim error paths) — +12 тестов, full suite 1299 → 1311.**

## Performance

- **Duration:** ~12 min wall-clock (без запусков xcodebuild)
- **Started:** 2026-04-25T12:55+03:00
- **Completed:** 2026-04-25T13:00+03:00
- **Tasks:** 3 (Task 1 TDD, Task 2 TDD, Task 3 verification)
- **Files modified:** 3 (1 created, 2 edited)

## Accomplishments

- **GAP-A закрыт:** `CredentialStoreKeychainTests.swift` с 9 тестами на реальный Keychain через `SecItem*` API. Покрывает round-trip save/get/delete, idempotency (errSecItemNotFound tolerated), upsert overwrite, edge cases (empty strings, unicode), concurrency (NSLock через `DispatchQueue.concurrentPerform`), и изоляцию двух экземпляров с разными service-identifier.
- **GAP-B закрыт:** `AppStateCloudShimTests.swift` расширен с 4 → 7 тестов; новая MARK секция `TEST-01: Error-path propagation` покрывает (1) проброс `CredentialStoreError.saveFailed` без флипа `cloudAvailable=true`, (2) проброс `CredentialStoreError.deleteFailed`, (3) обёртку non-`AuthError` в `AuthError.networkError` из `probeCloudConnection`.
- **Production zero-regression:** `CredentialStore.swift` теперь имеет `init(serviceOverride: String? = nil)` с default `nil` — все existing callsites (`AppState.swift:215`, `GovorunApp.swift`, инициализация в release) работают без изменений.
- **Full XCTest suite PASS:** 1311 tests, 0 failures (baseline 1299 + 9 KeychainTests + 3 ShimTests = 1311 exact).
- **Keychain hygiene:** `security dump-keychain | grep com.govorun.tests` возвращает `0` после прогона — `try? store.delete()` в `tearDown` корректно подчищает.

## Task Commits

Каждая задача закоммичена атомарно:

1. **Task 1 RED — failing Keychain tests** — `9c969c5` (test)
2. **Task 1 GREEN — init(serviceOverride:) DI** — `a8df974` (feat)
3. **Task 2 — error-path tests (RED+GREEN в одном коммите, AppState уже корректен)** — `6bab9ea` (test)

Refactor commits для Task 1 не понадобился — после GREEN код чистый.

**SUMMARY commit:** будет создан финальным шагом этого плана.

## Files Created/Modified

- `GovorunTests/CredentialStoreKeychainTests.swift` (NEW, 9 тестов, ~110 lines) — реальный Keychain integration через unique service-identifier
- `Govorun/Storage/CredentialStore.swift` (MODIFIED, +9/-4 lines) — `private let service: String` instance property + `init(serviceOverride:)` + замена `Keys.service` на `service` в saveItem/readItem/deleteItem; `Keys.service` переименован в `Keys.defaultService`
- `GovorunTests/AppStateCloudShimTests.swift` (MODIFIED, +45/-0 lines) — 3 теста error-path propagation в новой `MARK: - TEST-01` секции

## Decisions Made

- **Option A (serviceOverride DI) — implemented.** Per RESEARCH.md GAP-A анализ: «Опция (A) предпочтительнее — изоляция между тестами без shared state, не загрязняет prod Keychain.» Альтернатива Option B (cleanup `com.govorun.app.credentials` в setUp/tearDown) отклонена — риск гонок с production-запущенным Govorun.app на dev-машине.
- **AppState.swift НЕ редактировался.** Research предсказал что `probeCloudConnection` уже оборачивает non-AuthError в `.networkError` (lines 393-398 в AppState.swift) — 3 error-path теста прошли GREEN сразу, без production-фикса. RED commit сепарированно не делался для Task 2 (одиночный test commit обоснован через research-evidence что код корректен).
- **Keys.service → Keys.defaultService rename.** Семантически точнее — теперь имя отражает что это default value для override-параметра, а не единственное значение. Production callsites остаются без изменений (init без аргументов → используется defaultService).

## Deviations from Plan

**None — plan executed exactly as written.**

Все acceptance criteria из 16-01-PLAN.md выполнены:
- `grep -c "func test_" GovorunTests/CredentialStoreKeychainTests.swift` → `9` ✓
- `grep -c "func test_" GovorunTests/AppStateCloudShimTests.swift` → `7` ✓
- `grep -q "init(serviceOverride: String? = nil)" Govorun/Storage/CredentialStore.swift` ✓
- `grep -q "MARK: - TEST-01" GovorunTests/AppStateCloudShimTests.swift` ✓
- `xcodebuild test ... 2>&1 | grep "Test Suite 'All tests' passed"` ✓ — 1311 tests PASS
- `security dump-keychain | grep -c "com.govorun.tests\."` → `0` ✓
- Все commits на русском, без Co-Authored-By ✓

## Surprise Findings

- **AppState.probeCloudConnection уже корректен.** Research предсказал GREEN сразу для всех 3 error-path тестов — подтвердилось без правки production кода. catch-block lines 393-398 в AppState.swift корректно делает `error as? URLError` и формирует `AuthError.networkError(urlError:description:)` — non-AuthError случай покрыт.
- **save/delete throws — `try` пробрасывает прозрачно.** `saveCloudCredentials` и `deleteCloudCredentials` в AppState.swift это просто `try credentialStore.{save,delete}(...)` + `cloudAvailable = ...` после успеха. При throw из store cloudAvailable не меняется — наблюдаемое поведение через `XCTAssertFalse(appState.cloudAvailable)` после throw подтверждает корректность.
- **Concurrency test passes без contention warnings.** `DispatchQueue.concurrentPerform(iterations: 10)` через NSLock в `CredentialStore.save` — финальный `get()` возвращает один из записанных id-N вариантов. NSLock корректно сериализует SecItemAdd/SecItemDelete.

## Next Step Pointer

→ **Plan 16-02:** Benchmark runner cloud mode (`scripts/benchmark-llm-normalization.py --mode cloud|local` extension + `.env.bench` infrastructure). Параллельный agent уже работает в worktree. После merge plans 16-01 + 16-02 → Wave 2 (16-03 cloud bench execution) → Wave 3 (16-04 BENCHMARK-RESULTS.md + Phase 16 close).
