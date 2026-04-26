---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: Говорун Cloud
status: phase_complete
stopped_at: |
  Phase 16 closed Complete — coverage closure (KeychainTests + AppStateCloudShim error-paths,
  +12 тестов, 1311 total) + cloud benchmark Variant A executed (text-in symmetric, identical
  83.3% aggregate, distributional tradeoff: cloud +medium, local +long). Variant B (audio-in)
  deferred to Phase 17 (CLOUD-06). 16-BENCHMARK-RESULTS.md published. Ready for Phase 17 Polish & Rollout.
last_updated: "2026-04-25T13:30:00+03:00"
last_activity: |
  2026-04-25 — Phase 16 Tests shipped Complete.
  Plan 01: +12 тестов (CredentialStoreKeychain 9 + AppStateCloudShim 3 error-paths), 1311 total PASS.
  Plan 02: benchmark-llm-normalization.py --mode cloud + .env.bench infra (Q2=B reuse prod, SSL DI per W6, usage forwarding per I8).
  Plan 03: Q1=A (text-in symmetric); A1 valid; smoke (3) + local (36) + cloud (36) = 19594 tokens (~1% of 2M Max).
  Plan 04: 16-BENCHMARK-RESULTS.md published (cloud=local 83.3% aggregate, cloud +medium / local +long); full XCTest regression PASS; Variant B → Phase 17.
  TEST-01 + TEST-02 закрыты Complete.
progress:
  total_phases: 8
  completed_phases: 7
  total_plans: 22
  completed_plans: 22
  percent: 87
---

# Project State

<!-- [skip-review: STATE.md is mechanical progress tracking, not spec/plan; end-of-phase Codex review covers cumulative state] -->

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-02)

**Core value:** Cloud dictate через GigaChat-2-Max — audio-in, text-out за один API вызов
**Current focus:** Phase 16 CLOSED Complete — Phase 17 (Polish & Rollout) next up

## Current Position

Phase: **16 CLOSED — Phase 17 next up (Polish & Rollout)**
Status: Phase 16 Tests shipped Complete на 2026-04-25 — coverage closure (Plan 01) + cloud benchmark infra (Plan 02) + Variant A symmetric benchmark execution (Plan 03) + RESULTS.md / regression / phase-close (Plan 04). 1311 XCTest PASS, 0 failures. Cloud (GigaChat-2-Max) и local (GigaChat 3.1 10B Q4) показали identical 83.3% exact-match aggregate с distributional tradeoff (cloud +medium 100%, local +long 58.3%). Variant B (audio-in asymmetric) deferred → Phase 17 CLOUD-06. TEST-01 + TEST-02 закрыты.
Last activity: 2026-04-25 — Phase 16 closed Complete. 22/22 plans done. ROADMAP.md / REQUIREMENTS.md / STATE.md синхронизированы.

Progress: [████████░] 87% milestone (7/8 phases complete, 22/22 plans complete)

Resume file: .planning/ROADMAP.md §Phase 17 (next up — Polish & Rollout)
Next command: `/gsd-discuss-phase 17` (или `/gsd-plan-phase 17` если scope уже ясен)

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
- [Phase 16-01]: CredentialStore тестируемость — добавлен init(serviceOverride: String? = nil), default nil сохраняет production compatibility. UUID-suffixed test services предотвращают засорение user Keychain (security dump-keychain | grep com.govorun.tests = 0).
- [Phase 16-02]: Bench credentials Q2=B (reuse prod) per Sanya. .env.bench gitignored explicitly (defence-in-depth). SSL context через explicit DI (build_cloud_ssl_ctx + cloud_ssl_ctx param), без module-level state — per CLAUDE.md §Conventions.
- [Phase 16-03]: Q1=A (text-in symmetric) per orchestrator surfaced choice. Variant B (audio-in) deferred к Phase 17. A1 (GigaChat-2-Max text-only chat/completions) валидирован smoke 3 samples.
- [Phase 16-04]: Phase close — 1311 XCTest PASS; 16-BENCHMARK-RESULTS.md published. Cloud (GigaChat-2-Max) и local (GigaChat 3.1 10B Q4) дали identical 83.3% aggregate с разной distribution (cloud +medium, local +long). Recommendation: Phase 17 default-off explicit opt-in (D-07 preserved).

### Pending Todos

- Phase 15 Task 06-03: Human UAT delegated — 11 шагов в 15-06-SUMMARY.md §UAT Checkpoint. После approval: флипнуть ROADMAP checkbox 15-06 и закрыть Phase 15.

### Blockers/Concerns

- Phase 4: алгоритм style-neutral edit distance не описан в спеке -- определить при планировании
- Phase 8: layout карточек стилей в NSMenu -- определить при планировании

## Session Continuity

Last session: 2026-04-20T20:31:38+03:00
Stopped at: Phase 15 — все 6 планов shipped на main (1297/1297 tests). Последним merged 15-06 (CloudSettingsDisclosure + ProductModeCard integration). Task 06-03 UAT делегирован человеку — см. 15-06-SUMMARY.md §UAT Checkpoint для 11 шагов ручной верификации.
Resume file: .planning/phases/15-cloud-settings-ui/15-06-SUMMARY.md (UAT pending)
