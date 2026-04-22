---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Говорун Cloud
status: executing
stopped_at: Phase 15 closed — live cloud round-trip verified, REVIEW-FIX done, UAT passed/skipped per product decision
last_updated: "2026-04-23T00:10:00+03:00"
last_activity: 2026-04-22 -- REVIEW-FIX: H-01/M-01/M-02/L-01/I-02/I-03 закрыты + WAV-wrapper для /files upload (commit 27d5861). I-01 accepted-risk. 1299/1299 tests PASS (baseline 1297 + 2 новых TDD H-01). Live UAT 2026-04-22 23:58: Sanya «Проверить» + диктовка → полный OAuth + /files (76KB WAV) + /chat/completions round-trip, 0 errors, local llama idle (no silent Super fallback). Phase 15 passed.
progress:
  total_phases: 8
  completed_phases: 6
  total_plans: 18
  completed_plans: 18
  percent: 100
---

# Project State

<!-- [skip-review: STATE.md is mechanical progress tracking, not spec/plan; end-of-phase Codex review covers cumulative state] -->

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-02)

**Core value:** Cloud dictate через GigaChat-2-Max — audio-in, text-out за один API вызов
**Current focus:** Phase 16 — Tests (next up; Phase 15 closed 2026-04-23 с live cloud round-trip)

## Current Position

Phase: **15 CLOSED** — live cloud round-trip verified, REVIEW-FIX done. Ready for Phase 16.
Status: Phase 15 Cloud Settings UI — все 6 планов shipped + REVIEW-FIX (H-01/M-01/M-02/L-01/I-02/I-03 closed, I-01 accepted-risk) + WAV-wrapper для /files upload. 1299/1299 tests PASS. Live UAT: OAuth + /files (76KB WAV) + /chat/completions round-trip 2026-04-22 23:58 MSK — реальный Cloud, без Super-фолбэка.
Last activity: 2026-04-22 20:06 -- REVIEW-FIX 7 commits на main (WAV 27d5861, H-01 9533b5a, M-01 2e749f5, M-02 07fe4d0, L-01 a8ce6e2, I-02 4b114d2, I-03 1d70657, docs 1b91bdd). 2026-04-22 23:58 live UAT prod DMG: OAuth + audio upload + chat/completions успешны; locals llama-server idle в окне диктовки (no silent fallback).

Progress: [███████░] 75% (6/8 phases done, Phase 16 Tests + 17 Polish remain)

Resume file: .planning/ROADMAP.md §Phase 16 (next up — Tests)

## Performance Metrics

**Velocity:**

- Total plans completed: 1
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 11 | 1 | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01 P01 | 6m | 2 tasks | 2 files |
| Phase 01 P02 | 4m | 2 tasks | 3 files |
| Phase 02 P01 | 5m | 2 tasks | 7 files |
| Phase 04 P01 | 6m | 2 tasks | 3 files |
| Phase 04 P02 | 2m | 1 tasks | 2 files |
| Phase 05 P01 | 5m | 2 tasks | 5 files |
| Phase 06 P01 | 3m | 2 tasks | 4 files |
| Phase 08 P01 | 2m | 2 tasks | 4 files |
| Phase 08-ui P02 | 3m | 2 tasks | 2 files |
| Phase 14 P01 | 3m | 2 tasks | 2 files |
| Phase 14 P02 | 7m | 2 tasks | 4 files |
| Phase 14 P03 | 4m | 2 tasks | 4 files |
| Phase 14 P04 | 11m | 5 tasks | 4 files |
| Phase 15 P06 | 5m | 2 tasks (Task 06-03 UAT pending) | 2 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- TDD: тесты внутри каждой фазы, не в отдельной Phase 10
- Bottom-up: types --> pipeline --> gate --> UI --> deletion
- TEST-06 (миграция моков) в Phase 3 -- каскад от смены сигнатуры LLMClient
- [Phase 01]: brandAliases count 25 (spec table has 25 including Python, not 24)
- [Phase 01]: SuperStyleEngine: caseless enum с Set<String> для O(1) lookup bundleId
- [Phase 02]: NormalizationHints textMode field removed entirely (D-01) -- pipeline receives textMode as separate parameter
- [Phase 04]: allOutputWords Set for Cyrillic alias matching in gate -- protected token regexes only capture Latin
- [Phase 04]: test_relaxed_does_not_accept_slang_alias uses multi-slang input for robust threshold testing
- [Phase 04]: nil default for superStyle in postflight() preserves all existing test callsites without modification
- [Phase 08]: Placeholder Text view в SettingsView.swift для textStyle case — Exhaustive switch requirement -- Plan 02 заменит на TextStyleSettingsContent
- [Phase 08-ui]: xcodegen regeneration needed after creating new Swift file — Standard step when adding files to XcodeGen-based project
- [Phase 14-01]: SnippetReinserter.cleanSubstitute reuses private triggerRange via same-enum scope — triggerRange остаётся private без повышения видимости
- [Phase 14-01]: SwiftFormat pre-commit hook преобразует `//` комментарии в `///` doc comments — проектная конвенция, принимаем
- [Phase 14-02]: systemPrompt snippetDictionary добавляется в КОНЕЦ списка параметров с default `[:]` — zero-regression для всех существующих 14+ callsites NormalizationHints()
- [Phase 14-02]: SwiftFormat `redundantSelf` vs Swift strict concurrency в Logger macro autoclosure — используем `// swiftformat:disable:next redundantSelf` directive для точечного обхода
- [Phase 14-02]: Блок ГОЛОСОВЫЕ СОКРАЩЕНИЯ размещён ПОСЛЕ ПОДСТАНОВКА блока — ближе к задаче LLM, меньше риск переопределения стилевым блоком
- [Phase 14-03]: NetworkAvailabilityProviding: Sendable protocol + NetworkMonitor class-declaration conformance (не extension) — единая декларация с @unchecked Sendable, consistent с остальными DI протоколами (STTClient, LLMClient, CloudAudioProcessing)
- [Phase 14-03]: networkAvailability параметр в КОНЦЕ списка PipelineEngine init с default nil — zero-regression для всех 1263+ существующих тестов и production callsites
- [Phase 14-03]: _networkAvailability storage под NSLock consistent с _cloudClient/_llmClient/_hints паттерном; accessor private до Plan 14-04 (который прочитает его в processCloudPath)
- [Phase 14-04]: stopRecording становится тонким диспетчером (~40 строк) — cloud fork вызывает processCloudPath, default вызывает processLocalSTTPath helper; разделение cloud/local explicit и testable
- [Phase 14-04]: processLocalSTTPath принимает productMode параметр (не читает из snapshot) — позволяет offline-cloud-fallback передать .standard без infinite recursion
- [Phase 14-04]: snippetDictionary enrichment только в processCloudPath (не в processLocalSTTPath) — cloud prompt единственное место где словарь нужен inline
- [Phase 14-04]: bottomBarController создаётся как локальный let до PipelineEngine init — обходит ограничение Swift «нельзя self в init до всех stored props», closure захватывает weak
- [Phase 14-04]: offline fallback productMode == .standard (D-09) — cloud при offline НЕ пытается использовать local llama-server
- [Phase 15-06]: applyProductMode остался private в AppState — consent accept/revoke в CloudSettingsDisclosure пишут settings.productMode и полагаются на wireSettingsChange observer (который вызывает applyProductMode или откладывает в pendingProductMode если sessionManager.state != .idle). Строже плана, корректнее уважает D-07.1 revoke-during-dictation race rule.
- [Phase 15-06]: Landmine #4 (picker dropdown lock icon opacity) shipped as-is — HStack+lock.fill+.foregroundStyle(Color.ink.opacity(0.25)) в .menu pickerStyle. Если dropdown не применит opacity на macOS 14.x — lock-иконка сама по себе сигнал (UAT шаг A).
- [Phase 15-06]: SwiftUI .alert destructive вместо AppKit NSAlert shipped (D-05 deviation preserved from Plan-level per PATTERNS.md HistoryView.swift precedent).

### Pending Todos

- Phase 15 Task 06-03: Human UAT delegated — 11 шагов в 15-06-SUMMARY.md §UAT Checkpoint. После approval: флипнуть ROADMAP checkbox 15-06 и закрыть Phase 15.

### Blockers/Concerns

- Phase 4: алгоритм style-neutral edit distance не описан в спеке -- определить при планировании
- Phase 8: layout карточек стилей в NSMenu -- определить при планировании

## Session Continuity

Last session: 2026-04-20T20:31:38+03:00
Stopped at: Phase 15 — все 6 планов shipped на main (1297/1297 tests). Последним merged 15-06 (CloudSettingsDisclosure + ProductModeCard integration). Task 06-03 UAT делегирован человеку — см. 15-06-SUMMARY.md §UAT Checkpoint для 11 шагов ручной верификации.
Resume file: .planning/phases/15-cloud-settings-ui/15-06-SUMMARY.md (UAT pending)
