# Phase 2: Type Extraction - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Вынос SnippetPlaceholder, SnippetContext, NormalizationHints из TextMode.swift в отдельные файлы Models/. Удаление поля textMode из NormalizationHints и обновление всех потребителей. После этой фазы TextMode.swift содержит только enum TextMode и его extensions — готов к удалению в Фазе 9.

</domain>

<decisions>
## Implementation Decisions

### NormalizationHints без textMode
- **D-01:** Удалить поле `textMode: TextMode` из NormalizationHints. Не заменять на superStyle — это задача Фазы 3 (Pipeline Integration). После удаления struct содержит: personalDictionary, appName, currentDate, snippetContext.
- **D-02:** Обновить ВСЕ потребители NormalizationHints (7 файлов): убрать передачу textMode: параметра. Включая тесты — они тоже обновляются для компиляции.

### Файловая структура
- **D-03:** Каждый тип в отдельном файле (как в REQUIREMENTS): `Models/SnippetPlaceholder.swift`, `Models/SnippetContext.swift`, `Models/NormalizationHints.swift`. Не объединять.

### Claude's Discretion
- Порядок MARK-секций в новых файлах
- Нужно ли добавлять Sendable conformance при извлечении (если компилятор ругается)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Спека стилей
- `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md` — полная спецификация v2 стилей

### Исходный файл (источник извлечения)
- `Govorun/Models/TextMode.swift` — строки 192-224: SnippetPlaceholder, SnippetContext, NormalizationHints

### Потребители NormalizationHints (все 7 файлов)
- `Govorun/App/AppState.swift` — создаёт NormalizationHints
- `Govorun/Core/PipelineEngine.swift` — хранит и передаёт hints
- `Govorun/Services/LLMClient.swift` — протокол normalize(hints:)
- `Govorun/Services/LocalLLMClient.swift` — реализация, читает hints.textMode
- `GovorunTests/LocalLLMClientTests.swift` — тесты с NormalizationHints
- `GovorunTests/PipelineEngineTests.swift` — тесты с NormalizationHints
- `GovorunTests/TestHelpers.swift` — фабрики NormalizationHints

### Потребители SnippetPlaceholder/SnippetContext
- `Govorun/Models/SuperTextStyle.swift` — systemPrompt() использует оба типа
- `Govorun/Core/PipelineEngine.swift` — работает с SnippetContext
- `GovorunTests/NormalizationGateTests.swift` — использует SnippetContext
- `GovorunTests/SnippetEngineTests.swift` — тесты сниппетов

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SnippetPlaceholder` — caseless enum, 2 строки, один static let token
- `SnippetContext` — struct Equatable, 3 строки, одно поле trigger: String
- `NormalizationHints` — struct Equatable, 21 строка, 5 полей + init с defaults

### Established Patterns
- Models/ — чистые value types, `import Foundation` only
- Один тип = один файл (ProductMode.swift, SuperTextStyle.swift, etc.)
- Caseless enum для namespace-like типов (SnippetPlaceholder, NormalizationGate)

### Integration Points
- SuperTextStyle.systemPrompt() уже ссылается на SnippetPlaceholder и SnippetContext (созданы в Фазе 1)
- LocalLLMClient.normalize() читает hints.textMode для systemPrompt — после удаления textMode эта строка должна перестать зависеть от TextMode (Фаза 3 подключит superStyle)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — механический рефакторинг с чёткими EXTRACT-01/02/03 требованиями.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-type-extraction*
*Context gathered: 2026-03-29*
