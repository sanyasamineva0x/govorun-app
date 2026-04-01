---
phase: 05-postflight
plan: 01
status: complete
completed: 2026-04-01
duration: ~5m
tasks: 2
files_modified: 5
---

# Summary: Phase 05, Plan 01

## Что сделано

1. **SuperTextStyle.terminalPeriod** -- computed property: formal → true, relaxed/normal → false
2. **NormalizationPipeline.postflight()** -- `effectiveTerminalPeriod = superStyle?.terminalPeriod ?? terminalPeriodEnabled` + `applyDeterministic` на финальный текст
3. **PipelineEngine.processPipeline()** -- `effectiveTerminalPeriod` вычисляется один раз после `snapshotConfig()`, заменяет `terminalPeriodEnabled` во всех вызовах. `applyDeterministic` применяется на всех return-точках (standalone snippet, embedded snippet ×2, trivial, LLM failed)
4. **5 новых тестов** в NormalizationPipelineTests: relaxed/normal/formal × period + caps, rejected + caps, nil backward compat
5. **Фикс IntegrationTests** -- `MockWorkspaceProvider` вместо реального `NSWorkspace` для предсказуемого bundleId

## Файлы

| Файл | Изменение |
|------|-----------|
| Govorun/Models/SuperTextStyle.swift | +terminalPeriod computed property |
| Govorun/Core/NormalizationPipeline.swift | effectiveTerminalPeriod + applyDeterministic в postflight |
| Govorun/Core/PipelineEngine.swift | effectiveTerminalPeriod + applyDeterministic на всех путях |
| GovorunTests/NormalizationPipelineTests.swift | +5 тестов POST-01, POST-02, TEST-05 |
| GovorunTests/IntegrationTests.swift | MockWorkspaceProvider для детерминированного bundleId |

## Решения

- **D-POSTFLIGHT-01**: `effectiveTerminalPeriod` -- одна локальная переменная заменяет `terminalPeriodEnabled` когда стиль активен. nil-coalescing гарантирует backward compat.
- **D-POSTFLIGHT-02**: Порядок: сначала period (strip/keep), потом caps (applyDeterministic) -- как в спеке.
- **D-POSTFLIGHT-03**: Integration tests получили MockWorkspaceProvider -- фиксирует хрупкость, где результат зависел от frontmost app при запуске тестов.

## Тесты

1064 тестов, 0 failures.
