# Project Research Summary

**Project:** Стили текста v2
**Domain:** Text formality system for macOS voice input app
**Researched:** 2026-03-29
**Confidence:** HIGH

## Executive Summary

SuperTextStyle заменяет TextMode — это breaking change по всему pipeline Говоруна. Три уровня формальности (relaxed/normal/formal) с авто-режимом (bundleId→стиль) и ручным (один стиль на всё). Спека чрезвычайно детальна: определены все API, файлы, таблицы alias'ов, gate logic и тесты.

Ключевой архитектурный подход — bottom-up: foundation types → pipeline integration → gate → UI → TextMode deletion. Каждая фаза должна оставлять проект компилируемым. Наибольший риск — в gate modernization (style-neutral edit distance) и каскаде broken tests при смене сигнатуры LLMClient.

Всё строится на существующих паттернах проекта: protocol-based DI, enum-driven behavior, Models/Services/Core layering. Новых зависимостей нет.

## Key Findings

### Recommended Stack

Новых технологий не требуется. Всё строится на существующем Swift 5.10+ стеке:

- **CaseIterable enum** с computed properties — для SuperTextStyle
- **Protocol-based DI** — обновление сигнатуры LLMClient через протокол
- **UserDefaults** с register(defaults:) — для superStyleMode/manualSuperStyle
- **SwiftData** String field — без model migration, только смена записываемых значений

### Expected Features

**Must have (table stakes):**
- SuperTextStyle enum (relaxed/normal/formal) — основа
- SuperStyleEngine (авто bundleId mapping + ручной) — ключевая ценность
- Two-axis gate (contract + superStyle) — валидация
- Style-aware LLM промпт + postflight — стилизация
- Удаление TextMode — breaking change, чистка

**Should have (competitive):**
- Style-sensitive бренды (24 шт: Slack↔слак и т.д.)
- Style-sensitive техтермины (4 шт: PDF↔пдф)
- Slang expansion в formal (спс→спасибо)

**Defer (v2.5):**
- LLMOutputContract.rewriting (formal → деловой стиль)
- Морфологическое ты→Вы

### Architecture Approach

Bottom-up integration: Models → Services → Pipeline → Gate → UI → Deletion. Два новых файла в Models (SuperTextStyle, LLMOutputContract), один в Services (SuperStyleEngine). Остальное — модификации существующих файлов. Data flow: AppContextEngine.bundleId → SuperStyleEngine.resolveStyle() → PipelineEngine → LLM prompt → Gate evaluate → Postflight → History.

**Major components:**
1. **SuperTextStyle** (Models/) — enum стилей с styleBlock, systemPrompt, contract, applyDeterministic
2. **SuperStyleEngine** (Services/) — resolveStyle() по bundleId или manual setting
3. **NormalizationGate** (Core/) — two-axis: contract (масштаб) × superStyle (валидные замены)

### Critical Pitfalls

1. **Style-neutral edit distance** — gate должен нормализовать style aliases перед подсчётом, иначе false rejections в relaxed
2. **Cascading broken tests** — смена сигнатуры LLMClient ломает все моки одновременно, обновлять атомарно
3. **UserDefaults migration order** — register(defaults:) для новых ключей ДО первого чтения
4. **SwiftData legacy values** — никогда force unwrap SuperTextStyle(rawValue:), fallback для legacy
5. **Analytics gap** — новый ключ effective_style должен начать писаться ДО удаления старого text_mode

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Foundation Types
**Rationale:** Все компоненты зависят от SuperTextStyle и LLMOutputContract
**Delivers:** SuperTextStyle.swift, LLMOutputContract.swift, SuperStyleEngine.swift
**Addresses:** STYLE-01, STYLE-02, ENGINE-01, ENGINE-02
**Avoids:** Circular dependency (оба enum в Models/)

### Phase 2: Type Extraction
**Rationale:** SnippetPlaceholder, SnippetContext, NormalizationHints должны покинуть TextMode.swift ДО его удаления
**Delivers:** Три новых файла в Models/, NormalizationHints без textMode поля
**Addresses:** EXTRACT-01, EXTRACT-02, EXTRACT-03
**Avoids:** Потеря типов при удалении TextMode.swift

### Phase 3: Pipeline Integration
**Rationale:** Основной data flow — LLMClient сигнатура, LocalLLMClient, PipelineEngine
**Delivers:** Новая сигнатура normalize(_:superStyle:hints:), pipeline использует SuperTextStyle
**Addresses:** PIPE-01, PIPE-02, PIPE-03
**Avoids:** Каскад broken tests (атомарная замена)

### Phase 4: Gate Modernization
**Rationale:** Gate зависит от SuperTextStyle + LLMOutputContract, требует style-aware logic
**Delivers:** evaluate(contract:superStyle:), style-neutral edit distance, protected tokens
**Addresses:** GATE-01, GATE-02, GATE-03
**Avoids:** False rejections для style transforms

### Phase 5: Postflight & Deterministic
**Rationale:** Зависит от SuperTextStyle, простая фаза
**Delivers:** Стиль владеет точкой, applyDeterministic с caps
**Addresses:** POST-01, POST-02

### Phase 6: Settings & Data Layer
**Rationale:** SettingsStore, HistoryStore, PipelineResult, UserDefaults migration
**Delivers:** Новые настройки, миграция данных, PipelineResult.superStyle
**Addresses:** DATA-01 через DATA-05
**Avoids:** UserDefaults порядок, SwiftData legacy values

### Phase 7: Analytics
**Rationale:** Зависит от pipeline (effective_style), до deletion (text_mode ещё жив)
**Delivers:** effective_style, style_selection_mode, product_mode
**Addresses:** ANALYTICS-01, ANALYTICS-02

### Phase 8: UI
**Rationale:** Зависит от SuperStyleEngine + SettingsStore
**Delivers:** Вкладка "Стиль текста" в menubar (авто/ручной, карточки, состояние без модели)
**Addresses:** UI-01, UI-02, UI-03
**UI hint:** yes

### Phase 9: TextMode Deletion
**Rationale:** Все ссылки на TextMode уже заменены — безопасно удалять
**Delivers:** Удалён TextMode.swift, AppModeSettingsView, протоколы, обновлён AppContextEngine
**Addresses:** DELETE-01, DELETE-02, DELETE-03

### Phase 10: Test Migration
**Rationale:** Все production changes готовы — обновить тесты
**Delivers:** Обновлённые тесты, новые тесты для SuperTextStyle/Engine/Gate
**Addresses:** TEST-01 через TEST-06

### Phase Ordering Rationale

- Types first (1) → dependency foundation
- Extract before delete (2→9) → preserve shared types
- Pipeline before gate (3→4) → gate needs new signature context
- Analytics before deletion (7→9) → no metrics gap
- UI after engine+settings (8) → needs both
- Tests last (10) → all production code finalized

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4:** Gate style-neutral edit distance — complex algorithm, needs careful unit testing
- **Phase 8:** UI — design patterns для карточек стилей в NSMenu, состояние без модели

Phases with standard patterns (skip research-phase):
- **Phase 1:** Standard enum + computed properties
- **Phase 2:** File extraction, mechanical
- **Phase 7:** Analytics key change, straightforward

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Всё уже в проекте, нового нет |
| Features | HIGH | Спека детальна, без неопределённости |
| Architecture | HIGH | Codebase map + спека покрывают всё |
| Pitfalls | HIGH | Паттерны breaking changes в Swift хорошо изучены |

**Overall confidence:** HIGH

### Gaps to Address

- Gate edit distance algorithm: конкретный алгоритм style-neutral normalization не описан в спеке → определить при planning Phase 4
- UI в NSMenu: точный layout карточек стилей → определить при planning Phase 8

---
*Research completed: 2026-03-29*
*Ready for roadmap: yes*
