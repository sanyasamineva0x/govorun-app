# Phase 3: Pipeline Integration - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Pipeline переключается с TextMode на SuperTextStyle для LLM запросов. LLMClient получает новую сигнатуру normalize(_:superStyle:hints:), LocalLLMClient использует SuperTextStyle.systemPrompt(), PipelineEngine хранит и прокидывает SuperTextStyle вместо TextMode, PipelineResult возвращает superStyle. Все потребители PipelineResult (HistoryStore, analytics, AppState) обновляются. Тесты мигрируются.

</domain>

<decisions>
## Implementation Decisions

### SuperTextStyle wiring (откуда берётся стиль)
- **D-01:** Хардкод `.auto` + `.normal` — AppState вызывает `SuperStyleEngine.resolve(bundleId: context.bundleId, mode: .auto, manualStyle: .normal)` и передаёт результат в PipelineEngine. Фаза 6 заменит хардкод на реальные значения из SettingsStore (DATA-01, DATA-02). Не создавать мост TextMode→SuperTextStyle.

### TextMode removal scope
- **D-02:** Полная замена textMode→superStyle в PipelineEngine за один раз. Удалить `_textMode` property, заменить на `_superStyle: SuperTextStyle?`. Все 30+ ссылок на textMode в PipelineEngine обновляются. snapshotConfig() возвращает SuperTextStyle вместо TextMode.

### PipelineResult
- **D-03:** `PipelineResult.superStyle: SuperTextStyle?` полностью заменяет `textMode: TextMode`. Не добавлять оба поля одновременно. Все потребители обновляются в Фазе 3:
  - AppState.handlePipelineResult() — читает result.superStyle
  - HistoryStore.save() — пишет result.superStyle?.rawValue ?? "none"
  - AnalyticsService — пишет superStyle info в события

### NormalizationGate bridge
- **D-04:** Заменить `currentTextMode.llmOutputContract` → `currentSuperStyle?.contract ?? .normalization` в вызове NormalizationGate.evaluate(). Сигнатура gate не меняется (это Фаза 4). Результат тот же (.normalization), но путь через SuperTextStyle.

### LLMClient protocol
- **D-05:** Одна сигнатура `normalize(_ text: String, superStyle: SuperTextStyle, hints: NormalizationHints) async throws -> String`. Старая сигнатура с `mode: TextMode` удаляется полностью (PIPE-01). PlaceholderLLMClient тоже обновляется.

### Claude's Discretion
- Порядок обновления файлов (LLMClient → LocalLLMClient → PipelineEngine → PipelineResult consumers → Tests)
- Обработка nil superStyle в PipelineResult (optional vs default .normal)
- Имена параметров в snapshotConfig() — `currentSuperStyle` vs `currentStyle`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Спека стилей
- `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md` — полная спецификация v2 стилей, включая pipeline flow

### Текущие сигнатуры (источник рефакторинга)
- `Govorun/Services/LLMClient.swift` — текущий протокол normalize(_:mode:hints:)
- `Govorun/Services/LocalLLMClient.swift` — текущая реализация normalize(), sendChatCompletion()
- `Govorun/Core/PipelineEngine.swift` — 30+ ссылок на TextMode, snapshotConfig(), PipelineResult
- `Govorun/App/AppState.swift` — wiring textMode в PipelineEngine, handlePipelineResult()

### Типы из Phase 1 (уже существуют)
- `Govorun/Models/SuperTextStyle.swift` — enum с systemPrompt(), contract, styleBlock, applyDeterministic
- `Govorun/Core/SuperStyleEngine.swift` — static resolve(bundleId:mode:manualStyle:)

### Тесты (обновляются в этой фазе)
- `GovorunTests/TestHelpers.swift` — MockLLMClient с normalizeCalls tuple
- `GovorunTests/PipelineEngineTests.swift` — тесты pipeline с textMode
- `GovorunTests/AppContextEngineTests.swift` — тесты контекста
- `GovorunTests/HistoryStoreTests.swift` — тесты истории
- `GovorunTests/SnippetEngineTests.swift` — тесты сниппетов

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SuperTextStyle.systemPrompt()` — готовый промпт для LLM (Phase 1)
- `SuperTextStyle.contract` — возвращает LLMOutputContract (.normalization для всех v2 стилей)
- `SuperStyleEngine.resolve()` — ready to use, нужны только bundleId + mode + manualStyle
- `NormalizationHints` — уже без textMode (Phase 2)

### Established Patterns
- LLMClient protocol → LocalLLMClient + PlaceholderLLMClient + MockLLMClient (тройка)
- PipelineEngine: NSLock + private stored + public computed property
- PipelineResult: struct с let полями, создаётся в processPipeline()
- snapshotConfig(): lock → copy всех mutable полей → unlock → return tuple

### Integration Points
- AppState.wireSettingsChange() → устанавливает pipelineEngine.textMode (→ станет .superStyle)
- AppState.handleActivated() → устанавливает textMode из context (→ станет superStyle из SuperStyleEngine)
- PipelineEngine.processPipeline() → создаёт PipelineResult
- LocalLLMClient.normalize() → получает mode, строит промпт

</code_context>

<specifics>
## Specific Ideas

No specific requirements — механический рефакторинг сигнатур с чёткими PIPE-01..04 + TEST-06.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 03-pipeline-integration*
*Context gathered: 2026-03-30*
