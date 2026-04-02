# Стили текста v2

## What This Is

Замена системы TextMode на SuperTextStyle — три уровня формальности (relaxed/normal/formal) с глобальным переключателем авто/ручной для Говорун Super. Удаление TextMode и всей его инфраструктуры. Фича затрагивает модели, pipeline, gate, UI, аналитику и тесты.

## Core Value

Стиль текста адаптируется к контексту — расслабленный в мессенджерах, формальный в почте, обычный везде остальном. Одна точка настройки вместо per-app оверрайдов.

## Requirements

### Validated

- ✓ Голосовой ввод через GigaAM STT — existing
- ✓ Deterministic normalization pipeline — existing
- ✓ LLM normalization через llama-server (Говорун Super) — existing
- ✓ NormalizationGate с edit distance проверками — existing
- ✓ TextMode per-app mapping (удаляется в рамках этой фичи) — existing
- ✓ Menubar UI с настройками — existing
- ✓ Аналитика событий — existing
- ✓ SwiftData история — existing

### Active

- [x] SuperTextStyle enum (relaxed/normal/formal) с styleBlock, systemPrompt, applyDeterministic — Validated in Phase 01: foundation-types
- [x] SuperStyleEngine: авто (bundleId mapping) и ручной режим — Validated in Phase 01: foundation-types
- [ ] LLMOutputContract enum (.normalization, .rewriting заглушка)
- [ ] NormalizationGate с двумя осями (contract + superStyle)
- [ ] Style-aware protected tokens и edit distance
- [ ] Postflight: стиль владеет точкой
- [ ] Удаление TextMode и всей инфраструктуры (AppModeOverriding, UserDefaultsAppModeOverrides, AppModeSettingsView)
- [x] Переезд типов: SnippetPlaceholder, SnippetContext, NormalizationHints в отдельные файлы — Validated in Phase 02: type-extraction
- [x] LLMClient.normalize() новая сигнатура (superStyle вместо mode) — Validated in Phase 03: pipeline-integration
- [ ] AppContextEngine без textMode
- [x] PipelineResult.superStyle вместо textMode — Validated in Phase 03: pipeline-integration
- [ ] SettingsStore: superStyleMode + manualSuperStyle вместо defaultTextMode
- [ ] HistoryStore/HistoryItem миграция на superStyle
- [ ] Аналитика: effective_style, style_selection_mode
- [ ] UI: вкладка "Стиль текста" в menubar (авто/ручной, три карточки, состояние без модели)
- [ ] Миграция всех тестов на SuperTextStyle
- [ ] Новые тесты: SuperTextStyle, SuperStyleEngine, gate style-aware, postflight

### Out of Scope

- Уровень 2.5 (formal rewriting contract, ты→Вы морфология) — отдельный скоуп, см. docs/llm-normalization-roadmap.md
- Per-app style overrides — глобальный переключатель авто/ручной, без per-app
- Новый seed corpus для стилей — используем существующий, расширяем потом
- Onboarding для стилей — только menubar вкладка

## Context

- Brownfield: govorun-app — macOS menu bar приложение для голосового ввода на русском
- Текущий TextMode привязывает нормализацию к типу приложения (chat/email/universal). SuperTextStyle заменяет это на уровни формальности
- Pipeline: Activation → AudioCapture → STT → Dictionary → Snippets → DeterministicNormalizer → [Super?] → LLM → Gate → TextInserter
- Спека: `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md`
- 986 существующих тестов, TDD подход
- Style-sensitive бренды (24 шт) и техтермины (4 шт) определены в спеке

## Constraints

- **Tech stack**: Swift 5.10+, macOS 14.0+, Apple Silicon only
- **Architecture**: Core/ без SwiftUI/AppKit, Services/ без AppKit, Models/ чистые value types
- **Testing**: TDD, моки через протоколы, без реального Python worker или LLM
- **Conventions**: коммиты на русском, без Co-Authored-By, минимальные комментарии на русском
- **Backward compat**: HistoryItem.textMode поле остаётся String, без SwiftData migration
- **Trivial path**: короткие фразы без LLM — applyDeterministic покрывает только caps и точку (осознанный компромисс)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| LLMOutputContract.rewriting как заглушка | Подготовка к 2.5, formal.contract = .normalization пока | — Pending |
| HistoryItem.textMode без SwiftData migration | String поле, новые значения relaxed/normal/formal/none, legacy не трогаем | — Pending |
| Удаление TextMode целиком | Breaking change, SuperTextStyle полная замена | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-30 after Phase 03 completion*
