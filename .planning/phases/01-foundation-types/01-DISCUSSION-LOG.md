# Phase 1: Foundation Types - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 1-foundation-types
**Areas discussed:** SuperStyleEngine API, Alias tables, LLM prompt format

---

## SuperStyleEngine API

| Option | Description | Selected |
|--------|-------------|----------|
| Pure static (Recommended) | enum SuperStyleEngine { static func resolve(bundleId:mode:manualStyle:) }. Как NormalizationGate, в Core/. | ✓ |
| Stateful service | class SuperStyleEngine: ObservableObject с @Published currentStyle. В Services/. | |

**User's choice:** Pure static
**Notes:** Следует паттерну NormalizationGate — caseless enum, чистые static functions.

---

### SuperStyleMode

| Option | Description | Selected |
|--------|-------------|----------|
| Отдельный enum (Recommended) | enum SuperStyleMode { case auto, manual }. Две оси. | ✓ |
| Внутри SuperTextStyle | auto/manualRelaxed/manualNormal/manualFormal. Смешивает режим и стиль. | |

**User's choice:** Отдельный enum

---

### LLMOutputContract location

| Option | Description | Selected |
|--------|-------------|----------|
| Оставить в Core/ (Recommended) | Один target, SuperTextStyle свободно ссылается. Меньше изменений. | ✓ |
| Перенести в Models/ | Чистый value type. Но лишний diff. | |

**User's choice:** Оставить в Core/

---

### SuperStyleEngine file

| Option | Description | Selected |
|--------|-------------|----------|
| Core/SuperStyleEngine.swift (Recommended) | Собственный файл, как NormalizationGate. | ✓ |
| В SuperTextStyle.swift | Всё в одном месте. | |

**User's choice:** Core/SuperStyleEngine.swift

---

## Alias Tables

| Option | Description | Selected |
|--------|-------------|----------|
| В SuperTextStyle.swift (Recommended) | static let brandAliases/techAliases на enum. Просто, одно место. | ✓ |
| Отдельный StyleAliases | Models/StyleAliases.swift. Независимый тип. | |

**User's choice:** В SuperTextStyle.swift

---

### Slang expansions

| Option | Description | Selected |
|--------|-------------|----------|
| Только через LLM (Recommended) | LLM раскрывает в formal, без таблицы. Gate считает допустимыми. | ✓ |
| Фиксированная таблица | static let slangExpansions. Gate как protected tokens. | |

**User's choice:** Только через LLM

---

## LLM Prompt Format

| Option | Description | Selected |
|--------|-------------|----------|
| Полная таблица (Recommended) | Все 24+4 пары инлайн в styleBlock. Больше токенов, лучше качество. | ✓ |
| Только правило | "бренды → кириллица" без списка. Меньше токенов, риск ошибок. | |
| Benchmark first | Оба варианта, прогнать через бенчмарк. | |

**User's choice:** Полная таблица

---

### systemPrompt structure

| Option | Description | Selected |
|--------|-------------|----------|
| basePrompt + styleBlock (Recommended) | basePrompt (контракт) + styleBlock (стиль). Как текущий TextMode. | ✓ |
| Монолитный | Полный промпт для каждого стиля. Больше дублирования. | |

**User's choice:** basePrompt + styleBlock

---

## Claude's Discretion

- Точная формулировка basePrompt и styleBlock строк
- Структура тестов
- Порядок properties на enum
- displayName для стилей

## Deferred Ideas

None.
