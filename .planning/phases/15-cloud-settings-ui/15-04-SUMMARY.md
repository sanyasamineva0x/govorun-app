---
phase: 15-cloud-settings-ui
plan: 04
subsystem: AppState / Composition Root
tags: [appstate, shim, credentials, cloud-probe, landmine-2, tdd]
status: complete
requires: [15-01, 15-02]
provides:
  - AppState.saveCloudCredentials(clientId:clientSecret:)
  - AppState.deleteCloudCredentials()
  - AppState.probeCloudConnection() async -> Result<Void, AuthError>
  - AppState.authServiceFactory (test-only injection seam)
affects:
  - Views layer может получить доступ к credential/probe операциям без импорта Services/ или Storage/ протоколов
tech-stack:
  added: []
  patterns:
    - "Shim method pattern: @MainActor AppState экспозирует узкое API вместо прямого доступа к private credentialStore"
    - "Factory-based test injection: var authServiceFactory: () -> AuthService (PATTERNS.md §7)"
    - "@Sendable closure capture credentialStore для конструирования SberAuthService по запросу"
key-files:
  created:
    - GovorunTests/AppStateCloudShimTests.swift
  modified:
    - Govorun/App/AppState.swift
decisions:
  - "D-03: кнопка Сохранить вызывает AppState.saveCloudCredentials + auto-probe"
  - "D-04: кнопка Проверить вызывает AppState.probeCloudConnection для manual re-test"
  - "D-05: кнопка Удалить вызывает AppState.deleteCloudCredentials"
  - "D-07: deleteCloudCredentials НЕ трогает settings.cloudConsentAcceptedAt (consent — отдельная сущность)"
  - "RESEARCH Landmine #2 Option A: shim-методы, а не making credentialStore public/internal"
  - "probeCloudConnection возвращает Result<Void, AuthError> (не async throws) — вызывающий pattern-matches на .success/.failure без do/catch"
  - "Catch-all в probe возвращает .failure(.networkError(...)) чтобы View всегда работала с AuthError — не thrown unexpected exception"
metrics:
  duration_seconds: 411
  completed_date: 2026-04-20
  tasks_completed: 2
  tests_added: 4
  tests_baseline_after: 1288
  files_created: 1
  files_modified: 1
  commits: 2
---

# Phase 15 Plan 04: AppState Cloud Shim Summary

Added three `@MainActor` shim methods to `AppState` (`saveCloudCredentials`, `deleteCloudCredentials`, `probeCloudConnection`) plus a test-only `authServiceFactory` injection seam — Views layer теперь может управлять cloud credentials и пробовать соединение с Сбером без прямого импорта `CredentialStoring` / `AuthService`. Это закрывает Landmine #2 (RESEARCH) по Option A.

## Objective

Сохранить encapsulation `private let credentialStore` в AppState (CONVENTIONS.md §Layer Separation требует что Views/ не импортируют Services/ или Storage/ протоколы напрямую), одновременно дав новому `CloudSettingsDisclosure` чистый API для трёх UX-действий:

- Save creds → auto-probe OAuth token (без /chat/completions вызовов)
- Delete creds → сбросить `cloudAvailable`, но сохранить `cloudConsentAcceptedAt`
- Manual re-probe (кнопка «Проверить»)

## What Was Built

### New AppState API (all `@MainActor`)

```swift
func saveCloudCredentials(clientId: String, clientSecret: String) throws {
    try credentialStore.save(clientId: clientId, clientSecret: clientSecret)
    cloudAvailable = true
}

func deleteCloudCredentials() throws {
    try credentialStore.delete()
    cloudAvailable = false
    // consent не трогаем — D-07
}

func probeCloudConnection() async -> Result<Void, AuthError> {
    let authService = authServiceFactory()
    do {
        _ = try await authService.getAccessToken()
        return .success(())
    } catch let error as AuthError {
        return .failure(error)
    } catch {
        return .failure(.networkError(
            urlError: error as? URLError,
            description: error.localizedDescription
        ))
    }
}
```

### Test Injection Seam

```swift
var authServiceFactory: () -> AuthService = { SberAuthService(credentialProvider: { nil }) }
```

Default value — `nil`-credentialProvider SberAuthService — это безопасный stub на случай если `init` не переопределит фабрику. Оба init body (production, test) перезаписывают фабрику сразу после назначения `self.credentialStore`, захватывая реальный store через `[credentialStore]`:

```swift
authServiceFactory = { @Sendable [credentialStore] in
    SberAuthService(credentialProvider: { credentialStore.get() })
}
```

Тесты переопределяют фабрику напрямую:

```swift
appState.authServiceFactory = { mockAuthService }
```

### New Tests

`GovorunTests/AppStateCloudShimTests.swift` (4 тест-кейса):

| Тест | Проверяет |
|------|-----------|
| `test_saveCloudCredentials_writesToStore_and_flipsCloudAvailableTrue` | Save прокидывает `clientId`/`clientSecret` через `credentialStore.save` + `cloudAvailable = true` |
| `test_deleteCloudCredentials_clearsStore_and_flipsCloudAvailableFalse_keepsConsent` | Delete чистит store, `cloudAvailable = false`, НО `cloudConsentAcceptedAt` остаётся (D-07) |
| `test_probeCloudConnection_returnsSuccess_whenTokenFetched` | MockAuthService возвращает токен → `.success(())`, callCount == 1 |
| `test_probeCloudConnection_returnsFailure_whenAuthErrorThrown` | MockAuthService бросает `AuthError.invalidResponse(401)` → `.failure(.invalidResponse(401))` |

## Encapsulation Verified

- `private let credentialStore: CredentialStoring` — **остаётся `private`** (grep: 1 hit, строка 36)
- `authServiceFactory` — `var` (не `private`) только для тестовой подмены; Views вызывают только три shim-метода
- Zero logging в shim-региональ (T-15-04-01 mitigation): `awk '/MARK: - Cloud Settings.../,/MARK: - Super Model Download/' | grep -cE 'Logger|os_log|print\('` → 0

## TDD Cycle

1. **RED** — `GovorunTests/AppStateCloudShimTests.swift` создан с 4 failing-at-compile тестами + xcodegen regenerate (commit `de5fa05`)
   - xcodebuild вывалил 5 ошибок: `'AppState' has no member 'authServiceFactory' | 'saveCloudCredentials' | 'deleteCloudCredentials' | 'probeCloudConnection' | 'probeCloudConnection'`
2. **GREEN** — 3 shim-метода + `authServiceFactory` property + assignment в обоих init добавлены в AppState (commit `926ff04`)
   - 4 новых теста: GREEN за 0.030s
   - IntegrationTests 31/31: GREEN (no regression в cloud-guard тестах)
   - Full suite: **1288 tests / 0 failures / 57.5s**

## Commits

- `de5fa05` — `test(15-04): AppState cloud shim 4 теста (RED)`
- `926ff04` — `feat(15-04): AppState cloud shim — save/delete/probe (GREEN)`

## Deviations from Plan

Plan предусматривал default factory через extract `let store = self.credentialStore` с пустым placeholder default, но требовал "assign in both init bodies". Реализация:

- **Default value** для property установлен как тривиальный `SberAuthService(credentialProvider: { nil })` stub (безопасный no-op) — нужен потому что property stored and non-optional, Swift требует initial value (явный default до init-assignment).
- **Production init:** после `self.credentialStore = credentialStore` (строка 213) добавлен `authServiceFactory = { @Sendable [credentialStore] in SberAuthService(...) }` используя local-let capture (не через `self.`, т.к. в init-фазе).
- **Test init:** после `self.credentialStore = credentialStore ?? MockCredentialStore()` используется промежуточный `let resolvedCredentialStore = self.credentialStore` чтобы захватить фактическое хранилище (локальный parameter `credentialStore` в test init — optional и может быть `nil`).

Оба варианта соответствуют гайду plan'а (capture only the `get()` closure — фактически мы captures сам `credentialStore`, но `CredentialStoring: Sendable` уже проверено в preflight, так что `@Sendable` closure законно).

Никаких Rule 1-3 багфиксов не потребовалось — план исполнен как написан.

## Known Stubs

Отсутствуют.

## Requirements Addressed

- **UI-01** (data-plane): Views могут сохранять/удалять credentials без импорта `Storage/`.
- **UI-02** (probe-plane): Views могут выполнить probe без импорта `Services/`.

## Threat Flags

Отсутствуют — новая поверхность полностью покрыта `<threat_model>` плана (T-15-04-01..04 все mitigated/accepted по плану).

## Baseline Delta

- Full suite до: ~1284 (1288 − 4)
- Full suite после: **1288 tests**

Plan 15-04 указывает baseline «1293 → 1297» — расчёт сделан при условии уже смёрдженного Plan 03. Текущий worktree основан на 68f86dd (main после Wave 1 merge), где Plan 03 ещё не смёржен. Факт: +4 тестов. Delta совпадает с планом.

## Self-Check: PASSED

- [x] File exists: `GovorunTests/AppStateCloudShimTests.swift`
- [x] File exists: `.planning/phases/15-cloud-settings-ui/15-04-SUMMARY.md`
- [x] Commit exists: `de5fa05` (RED)
- [x] Commit exists: `926ff04` (GREEN)
- [x] All 4 new tests GREEN
- [x] IntegrationTests 31/31 GREEN (no regression)
- [x] Full suite 1288/1288 GREEN
- [x] `private let credentialStore` preserved
- [x] `authServiceFactory` has 4 grep hits (declaration + 2 init assignments + 1 usage in probeCloudConnection)
- [x] Zero logging in shim region (T-15-04-01)
