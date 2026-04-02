# Phase 5: Postflight - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Финальная обработка текста (точка, капитализация) определяется стилем. При superStyle != nil стиль владеет точкой и caps во всех путях PipelineEngine (LLM postflight, тривиальные фразы, сниппеты). При superStyle == nil (classic) поведение определяется terminalPeriodEnabled из настроек. applyDeterministic применяется принудительно на любом выходе — safety net для caps.

</domain>

<decisions>
## Implementation Decisions

### Охват стиля
- **D-01:** Стиль влияет на caps и точку во ВСЕХ путях PipelineEngine — LLM postflight, тривиальные фразы (без LLM), standalone сниппеты, embedded сниппеты. Пользователь не должен замечать разницу между LLM и не-LLM путями.
- **D-02:** При superStyle == nil (classic path, Говорун standard) — все пути работают как раньше через terminalPeriodEnabled.

### Капитализация
- **D-03:** postflight и все callers принудительно применяют `superStyle.applyDeterministic()` на финальный текст. LLM может не следовать промпту — applyDeterministic гарантирует правильный регистр (relaxed → строчная, normal/formal → заглавная).
- **D-04:** При superStyle == nil — caps определяется DeterministicNormalizer (всегда uppercase, текущее поведение).

### Точка: стиль vs настройка
- **D-05:** При superStyle != nil — стиль побеждает terminalPeriodEnabled. relaxed/normal → без точки, formal → с точкой. Настройка terminalPeriodEnabled игнорируется. Простая ментальная модель: Super = стиль решает всё.
- **D-06:** При superStyle == nil — terminalPeriodEnabled из SettingsStore (POST-02, текущее поведение).

### DeterministicNormalizer
- **D-07:** Сигнатура DeterministicNormalizer.normalize() НЕ меняется — остаётся style-agnostic. Caller (PipelineEngine) применяет `superStyle?.applyDeterministic(result) ?? result` после вызова normalize(). Минимальные изменения, 0 затронутых callsites в тестах.

### Claude's Discretion
- Вспомогательный метод/property на SuperTextStyle для определения точки (computed `var terminalPeriod: Bool`)
- Порядок применения: сначала точка, потом caps или наоборот
- Рефакторинг дублирования terminalPeriodEnabled logic в PipelineEngine (3+ мест)
- Структура тестов: отдельный test case class или расширение NormalizationPipelineTests

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Спека стилей — секция Postflight
- `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md` — секция postflight: стиль владеет точкой и caps

### Текущая реализация postflight
- `Govorun/Core/NormalizationPipeline.swift` — строки 629-657: postflight(), terminalPeriodEnabled logic, stripTrailingPeriods
- `Govorun/Core/NormalizationPipeline.swift` — строки 97-142: DeterministicNormalizer.normalize(), uppercase на строке 129, terminalPeriod logic строки 133-139

### PipelineEngine — все пути с terminalPeriodEnabled
- `Govorun/Core/PipelineEngine.swift` — строка 393: preflight terminalPeriodEnabled
- `Govorun/Core/PipelineEngine.swift` — строки 426, 531: ранние return-ы с terminalPeriodEnabled (сниппеты, embedded)
- `Govorun/Core/PipelineEngine.swift` — строки 619-625: LLM postflight вызов

### SuperTextStyle — applyDeterministic
- `Govorun/Models/SuperTextStyle.swift` — строки 33-41: applyDeterministic (relaxed → lowercase, normal/formal → uppercase)

### Существующие тесты postflight
- `GovorunTests/NormalizationPipelineTests.swift` — строки 38-110: test_postflight_* (6 тестов)
- `GovorunTests/PipelineEngineTests.swift` — строки 1156-1226: DeterministicNormalizer.normalize с terminalPeriodEnabled

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SuperTextStyle.applyDeterministic(_:)` — готовый метод для caps (Phase 1)
- `DeterministicNormalizer.stripTrailingPeriods()` — уже используется в postflight для удаления точки
- `NormalizationPipeline.postflight()` — уже принимает superStyle parameter (Phase 4 добавил)

### Established Patterns
- `terminalPeriodEnabled` ternary: `terminalPeriodEnabled ? text : stripTrailingPeriods(text)` — паттерн в 3+ местах PipelineEngine
- postflight struct `NormalizationPipelinePostflight` — finalText, path, gateFailureReason, failureContext
- PipelineEngine lock pattern: `_terminalPeriodEnabled` с NSLock getter/setter

### Integration Points
- `AppState.wireSettingsChange()` строка 850 → устанавливает `pipelineEngine.terminalPeriodEnabled`
- `NormalizationPipeline.postflight()` → вызывается из PipelineEngine.processPipeline()
- `NormalizationPipeline.preflight()` → вызывается до LLM, тоже использует terminalPeriodEnabled
- `PipelineEngine.processPipeline()` → 3 ранних return-а + 1 LLM postflight = 4 точки для стилевой обработки

</code_context>

<specifics>
## Specific Ideas

- При superStyle != nil достаточно вычислить `superStyle.terminalPeriod` (formal → true, relaxed/normal → false) и использовать вместо terminalPeriodEnabled
- applyDeterministic применяется ПОСЛЕ точки — сначала strip/add period, потом caps

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 05-postflight*
*Context gathered: 2026-04-01*
