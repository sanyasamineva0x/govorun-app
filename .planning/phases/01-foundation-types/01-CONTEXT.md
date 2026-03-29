# Phase 1: Foundation Types - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

SuperTextStyle enum (relaxed/normal/formal), LLMOutputContract (уже существует), SuperStyleEngine (авто/ручной), SuperStyleMode enum, и unit-тесты для всего. Фундамент для всех последующих фаз — downstream зависят от этих типов.

</domain>

<decisions>
## Implementation Decisions

### SuperStyleEngine API
- **D-01:** Pure static — caseless enum `SuperStyleEngine` с `static func resolve(bundleId:mode:manualStyle:) -> SuperTextStyle`. Без состояния, caller передаёт все параметры.
- **D-02:** Файл: `Govorun/Core/SuperStyleEngine.swift`. Паттерн как NormalizationGate — caseless enum + static methods.
- **D-03:** SuperStyleMode — отдельный enum `enum SuperStyleMode: String, CaseIterable { case auto, manual }`. Две независимые оси: режим (авто/ручной) + стиль (relaxed/normal/formal).

### LLMOutputContract
- **D-04:** Оставить в `Core/NormalizationGate.swift` где уже живёт. Один target, нет модульных границ — SuperTextStyle из Models/ свободно ссылается на Core/. Не перемещать.

### Alias tables
- **D-05:** Таблицы 24 брендов + 4 техтерминов определяются как static let на SuperTextStyle в `Models/SuperTextStyle.swift`. Формат: `[(original: String, relaxed: String)]`.
- **D-06:** Сленговые раскрытия (formal) — только через LLM, без фиксированной таблицы. Gate считает сленговые замены допустимыми в formal (lenient для сленга).

### LLM prompt format
- **D-07:** systemPrompt() = basePrompt + styleBlock. basePrompt содержит нормализационный контракт (не перефразировать, точечные замены). styleBlock зависит от стиля.
- **D-08:** styleBlock для relaxed включает полную таблицу брендов + техтерминов инлайн (все 24+4 пары). Больше токенов, но точнее замены.
- **D-09:** styleBlock для normal — минимальный (стандартные проверки, бренды/техтермины → оригинал).
- **D-10:** styleBlock для formal — оригинал для брендов/техтерминов + "сленг раскрывать в полные формы".

### Claude's Discretion
- Точная формулировка basePrompt и styleBlock строк
- Структура тестов (XCTestCase layout, test naming)
- Порядок properties на SuperTextStyle enum
- displayName для UI (локализованные названия стилей)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Спека стилей
- `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md` — полная спецификация: три стиля, таблица брендов/техтерминов, bundleId mapping, gate design, postflight, удаление TextMode

### Существующие паттерны (reference)
- `Govorun/Models/TextMode.swift` — текущий enum стилей с styleBlock, systemPrompt (заменяется)
- `Govorun/Models/ProductMode.swift` — паттерн enum: String, CaseIterable, Codable + computed properties
- `Govorun/Core/NormalizationGate.swift` — LLMOutputContract (уже существует, строки 5-8), caseless enum паттерн

### Canonical style spec
- `docs/canonical-style-spec.md` — единый канон форм (числа, проценты, валюты, даты, время, единицы) — НЕ зависит от стиля

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TextMode.styleBlock` / `TextMode.systemPrompt()` — шаблон для SuperTextStyle. Формат строк, структура промпта.
- `LLMOutputContract` в NormalizationGate.swift — уже имеет .normalization и .rewriting. TextMode.llmOutputContract computed property.
- `ProductMode` в Models/ — паттерн `String, CaseIterable, Codable` с computed properties.

### Established Patterns
- Caseless enum для utility namespaces: `NormalizationGate`, `DeterministicNormalizer`
- `SettingsStore.Keys` nested enum для UserDefaults ключей
- Models/ — чистые value types, без SwiftUI/AppKit imports
- Core/ — Foundation only, без AppKit

### Integration Points
- `SuperTextStyle.contract` → ссылается на `LLMOutputContract` из Core/NormalizationGate.swift
- `SuperStyleEngine.resolve()` → используется PipelineEngine (Phase 3) и UI (Phase 8)
- `SuperTextStyle.systemPrompt()` → используется LocalLLMClient (Phase 3)
- `SuperTextStyle.applyDeterministic()` → используется NormalizationPipeline (Phase 5)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches following established codebase patterns.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 01-foundation-types*
*Context gathered: 2026-03-29*
