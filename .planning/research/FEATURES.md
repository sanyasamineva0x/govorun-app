# Feature Research

**Domain:** Текстовые стили формальности для macOS voice input
**Researched:** 2026-03-29
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Must Have)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| SuperTextStyle enum (relaxed/normal/formal) | Основа всей фичи | LOW | CaseIterable, rawValue, computed properties |
| Авто-режим (bundleId mapping) | Ключевая ценность — стиль адаптируется к контексту | MEDIUM | SuperStyleEngine + жёсткая таблица bundleId→style |
| Ручной режим (один стиль на всё) | Альтернатива для тех кто хочет контроль | LOW | SettingsStore.manualSuperStyle |
| Style-aware LLM промпт | LLM должен знать о стиле | LOW | SuperTextStyle.systemPrompt() + styleBlock |
| Стиль владеет точкой (postflight) | Формальный добавляет, расслабленный убирает | LOW | Заменяет terminalPeriodEnabled в Super mode |
| Удаление TextMode | Breaking change, спека требует полной замены | HIGH | Каскад по всему pipeline, 986 тестов |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Style-sensitive бренды (24 шт) | "слак" в телеге, "Slack" в почте | MEDIUM | LLM-driven, таблица alias'ов в промпте |
| Style-sensitive техтермины (4 шт) | "пдф" в телеге, "PDF" в почте | LOW | Subset of brand logic |
| Slang expansion в formal | "спс" → "спасибо" | LOW | LLM-driven через промпт |
| Two-axis gate (contract × style) | Точная валидация с учётом стиля | HIGH | Style-neutral edit distance, protected tokens |
| Caps/точка через applyDeterministic | Работает даже без LLM (trivial path) | LOW | Расширение существующего метода |

### Anti-Features (Explicitly Out of Scope)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Per-app style overrides | Гибкость | Усложняет UI и логику, спека исключает | Авто/ручной глобальный переключатель |
| Level 2.5 rewriting | "Вы" → формальный тон | Отдельный seed corpus, другой contract | Отдельный скоуп, заглушка .rewriting |
| Onboarding для стилей | Discovery | Не критично для v1 | Вкладка в menubar menu |
| Новый seed corpus | Точнее стилизация | Отдельная работа | Используем существующий |

## Feature Dependencies

```
SuperTextStyle enum
    └──requires──> LLMOutputContract enum
                       └──used by──> NormalizationGate

SuperStyleEngine
    └──requires──> SuperTextStyle
    └──requires──> AppContextEngine (bundleId)

Pipeline integration
    └──requires──> SuperTextStyle
    └──requires──> SuperStyleEngine
    └──requires──> LLMClient new signature

UI (menubar tab)
    └──requires──> SuperStyleEngine
    └──requires──> SettingsStore (superStyleMode + manualSuperStyle)

TextMode deletion
    └──requires──> All above complete
    └──requires──> Type extraction (SnippetPlaceholder, SnippetContext, NormalizationHints)
```

### Dependency Notes

- **SuperTextStyle requires LLMOutputContract:** `SuperTextStyle.contract` возвращает `.normalization` (сейчас все три)
- **Gate requires SuperTextStyle:** для style-aware protected tokens и edit distance normalization
- **TextMode deletion requires everything else:** последний шаг, когда все ссылки на TextMode уже заменены
- **Type extraction before deletion:** SnippetPlaceholder, SnippetContext, NormalizationHints живут в TextMode.swift — вынести до удаления

## MVP Definition (v1 = этот milestone)

### Launch With

- [x] SuperTextStyle enum с тремя стилями
- [x] SuperStyleEngine (авто + ручной)
- [x] LLM промпт с styleBlock
- [x] Gate с двумя осями (contract + superStyle)
- [x] Postflight: стиль владеет точкой
- [x] Pipeline integration (новые сигнатуры)
- [x] Удаление TextMode целиком
- [x] UI вкладка "Стиль текста"
- [x] Аналитика (effective_style, style_selection_mode)
- [x] Миграция всех тестов

### Future (v2.5)

- [ ] LLMOutputContract.rewriting (formal → деловой стиль)
- [ ] Морфологическое ты→Вы
- [ ] Отдельный seed corpus для стилей

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| SuperTextStyle enum | HIGH | LOW | P1 |
| SuperStyleEngine авто/ручной | HIGH | MEDIUM | P1 |
| Style-sensitive бренды | HIGH | MEDIUM | P1 |
| Two-axis gate | HIGH | HIGH | P1 |
| TextMode deletion | MEDIUM | HIGH | P1 |
| UI вкладка | MEDIUM | MEDIUM | P1 |
| Аналитика | LOW | LOW | P1 |
| Миграция тестов | — | HIGH | P1 |

---
*Feature research for: SuperTextStyle text formality system*
*Researched: 2026-03-29*
