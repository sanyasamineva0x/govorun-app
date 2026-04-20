---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Говорун Cloud
status: executing
stopped_at: Phase 15 planned — ready to execute (Cloud Settings UI)
last_updated: "2026-04-20T19:35:00+03:00"
last_activity: 2026-04-20 -- Phase 15 planned — 6 PLAN файлов в 3 waves, plan-checker 0 blockers + 4 warnings (2 patched inline), D-11.2 Path B override принят (AuthError preserves URLError)
progress:
  total_phases: 8
  completed_phases: 5
  total_plans: 18
  completed_plans: 12
  percent: 67
---

# Project State

<!-- [skip-review: STATE.md is mechanical progress tracking, not spec/plan; end-of-phase Codex review covers cumulative state] -->

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-02)

**Core value:** Cloud dictate через GigaChat-2-Max — audio-in, text-out за один API вызов
**Current focus:** Phase 15 — cloud-settings-ui (PLANNED, ready to execute)

## Current Position

Phase: 15 (cloud-settings-ui) — READY TO EXECUTE
Plan: 0 of 6 (не начат)
Status: 6 PLAN файлов в 3 waves, plan-checker PASSED (0 blockers), all UI-01..UI-04 covered
Last activity: 2026-04-20 -- Planning complete: RESEARCH + VALIDATION + PATTERNS + 6 PLANs. D-11.2 override: AuthError.networkError будет нести URLError? (Path B — Plan 15-02). Wave 1 parallel: 01/02/05; Wave 2: 03/04; Wave 3: 06 (UAT checkpoint).

Progress: [          ] 0% plans of Phase 15

Resume file: .planning/phases/15-cloud-settings-ui/15-01-PLAN.md

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

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 4: алгоритм style-neutral edit distance не описан в спеке -- определить при планировании
- Phase 8: layout карточек стилей в NSMenu -- определить при планировании

## Session Continuity

Last session: 2026-04-19T23:44:00+03:00
Stopped at: Phase 14 complete — cloud pipeline hardening end-to-end. All 4 plans shipped: SnippetReinserter.cleanSubstitute (14-01), snippet-aware systemPrompt (14-02), NetworkAvailabilityProviding DI (14-03), processCloudPath integration (14-04). 1280 tests PASS.
Resume file: .planning/phases/15-cloud-settings-ui/ (next phase — не начат)
