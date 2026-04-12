---
phase: 13-mode-routing
plan: 02
subsystem: app-state
tags: [product-mode, cloud, guard-audit, credential-gate, tdd]
dependency_graph:
  requires: [ProductMode.cloud, CloudAudioProcessing, PipelineEngine.updateCloudClient]
  provides: [AppState.cloudWiring, AppState.guardAudit, AppState.cloudAvailable, AppState.credentialGate]
  affects: [Govorun/App/AppState.swift, GovorunTests/IntegrationTests.swift]
tech_stack:
  added: []
  patterns: [switch-based-mode-routing, credential-gate-guard, lazy-client-creation, cloud-auto-downgrade]
key_files:
  created: []
  modified:
    - Govorun/App/AppState.swift
    - GovorunTests/IntegrationTests.swift
decisions:
  - Switch-based applyProductMode вместо if/else usesLocalLLM -- каждый case обрабатывается явно
  - CloudLLMClient пересоздаётся при каждом переключении в .cloud (credentials могут измениться)
  - trustPolicy?.urlSession ?? URLSession.shared как fallback при отсутствии PEM
metrics:
  duration: 14m
  completed: "2026-04-12T18:27:29Z"
  tasks: 2
  files: 2
  tests_added: 16
  tests_total: 1245
---

# Phase 13 Plan 02: Guard Audit + Cloud Wiring in AppState Summary

Аудит 10 guard sites usesLLM->usesLocalLLM, applyProductMode(.cloud) с credential gate и lazy CloudLLMClient, cloudAvailable для UI, auto-downgrade при отсутствии credentials

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Guard audit usesLLM->usesLocalLLM + CredentialStore/TrustPolicy properties | a2901c6 | AppState.swift, IntegrationTests.swift |
| 2 | applyProductMode(.cloud) wiring -- credential gate, CloudLLMClient, cloudAvailable | dbb574c | AppState.swift, IntegrationTests.swift |

## Key Changes

### AppState.swift -- Guard Audit (Task 1)
- 9 guard sites заменены на `usesLocalLLM` (G1-G5, G6-G7, G9-G10)
- G8 (applyProductMode) переработан в switch: cloud case обрабатывается отдельно
- `usesLLM` сохранён только для: superStyle resolution (line 904) и analytics metadata (line 924)
- `handleActivated` использует `effectiveProductMode.usesLLM` для superStyle (cloud тоже получает стили)
- Cloud auto-downgrade в `start()`: если .cloud и нет credentials, откат на .standard

### AppState.swift -- New Properties (Task 1)
- `private var cloudLLMClient: CloudLLMClient?`
- `private let credentialStore: CredentialStoring`
- `private let trustPolicy: TrustPolicyProviding?`
- `@Published var cloudAvailable: Bool`
- Production init: `CredentialStore()` + `try SberTrustPolicy()`
- Test init: `credentialStore: CredentialStoring? = nil`, `trustPolicy: TrustPolicyProviding? = nil`

### AppState.swift -- applyProductMode Switch (Task 2)
- `case .standard`: sets productMode, clears cloudClient, stops llmRuntime
- `case .superMode`: clears cloudClient, delegates to handleSuperAssetsChanged
- `case .cloud`: credential gate, creates SberAuthService + CloudLLMClient lazily, wires updateCloudClient + updateLLMClient, stops llmRuntime
- `cloudAvailable = credentialStore.get() != nil` обновляется после каждого switch

### IntegrationTests.swift
- `makeTestAppState` расширен: `credentialStore: CredentialStoring?`, `llmRuntimeManager: LLMRuntimeManaging?`
- 8 тестов guard audit: cloud не ставит .notStarted, не даунгрейдится, disabled для updateLLMRuntimeState, noop для handleSuperAssetsChanged/start/applyLLMConfiguration, no downgrade при отсутствии super assets, super unchanged
- 8 тестов cloud wiring: pipeline wired, credential gate blocks, stops llmRuntime, standard/super clear cloudClient, cloudAvailable true/false, updates after switch

## Test Results

- 16 новых тестов (8 guard audit + 8 cloud wiring)
- Полный прогон: 1245 тестов, 0 failures

## Decisions Made

- **Switch-based applyProductMode**: Вместо if/else на `usesLocalLLM`, полный switch по ProductMode. Каждый case обрабатывает cleanup предыдущего режима явно. G8 больше не нужен как отдельный usesLocalLLM guard.
- **Lazy CloudLLMClient creation (D-05/D-06)**: SberAuthService + CloudLLMClient создаются только при переключении в .cloud, пересоздаются каждый раз (credentials могут измениться между переключениями).
- **TrustPolicy fallback (T-13-08)**: Если SberTrustPolicy не инициализируется (PEM отсутствует), используется URLSession.shared. Certificate pinning теряется, но TLS остаётся.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] LLMRuntimeState.running не существует**
- **Found during:** Task 1 RED phase
- **Issue:** Тест использовал `.running` вместо `.ready`
- **Fix:** Заменено на `.ready` (корректное значение enum)
- **Files modified:** IntegrationTests.swift

**2. [Rule 3 - Blocking] xcodegen regeneration required**
- **Found during:** Task 1 GREEN phase
- **Issue:** CredentialStore/SberTrustPolicy/CloudLLMClient не видны в AppState (xcodeproj stale)
- **Fix:** `xcodegen generate` для пересоздания project файла
- **Files modified:** Govorun.xcodeproj (generated)

**3. [Rule 1 - Bug] applyPendingSettings fileprivate access**
- **Found during:** Task 2 RED phase
- **Issue:** Тесты не могут вызвать fileprivate applyPendingSettings напрямую
- **Fix:** Тесты используют settings.productMode = .cloud + Task.sleep для Combine pipeline
- **Files modified:** IntegrationTests.swift

## Threat Mitigations Applied

- T-13-05 (EoP): `guard credentialStore.get() != nil` в applyProductMode(.cloud) -- cloud не активируется без credentials
- T-13-06 (DoS): `start()` проверяет `currentProductMode.isCloud && credentialStore.get() == nil` -- auto-downgrade при отсутствии credentials
- T-13-09 (Tampering): Все 10 guard sites проверены тестами для .cloud mode, P1/P2/A1 сохранены с usesLLM

## Self-Check: PASSED
