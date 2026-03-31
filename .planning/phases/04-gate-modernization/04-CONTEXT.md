# Phase 4: Gate Modernization - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

NormalizationGate учится про SuperTextStyle — двухосевой evaluate(contract + superStyle), style-aware protected tokens (alias-формы валидны), style-neutral edit distance (стилевые замены = 0 редактирований), таблица сленга для formal. False rejections для стилевых трансформаций исключены.

</domain>

<decisions>
## Implementation Decisions

### Таблица сленга для formal
- **D-01:** Фиксированная таблица ~15-20 сленговых пар как `static let slangExpansions` на SuperTextStyle. Формат: `[(slang: String, full: String)]`. Включает: норм→нормально, спс→спасибо, ок→хорошо, чё→что, щас→сейчас, инфа→информация, комп→компьютер, прога→программа, чел→человек и др. Конкретный список определяется при планировании.
- **D-02:** Gate использует таблицу сленга только для валидации в formal стиле — считает обе формы (slang и full) валидными protected tokens и нормализует к одной форме при edit distance.

### Style-neutral edit distance
- **D-03:** Перед подсчётом distance оба текста нормализуются: все известные алиасы (brand, tech, slang) заменяются на каноническую форму. Стилевые трансформации = 0 редактирований.
- **D-04:** Каноническая форма — оригинал для brand/tech (Slack, PDF), полная форма для сленга (спасибо, нормально).

### Пороги edit distance
- **D-05:** Ослабить пороги для relaxed и formal — дополнительный запас поверх style-neutral нормализации. Relaxed имеет 25 brand + 4 tech трансформаций, formal имеет ~15-20 сленговых раскрытий. Конкретные значения определяются при планировании (текущие: <10 токенов → 0.25, ≥10 → 0.4).

### Protected tokens с алиасами
- **D-06:** Если protected token имеет известный алиас (Slack↔слак, PDF↔пдф, спс↔спасибо), обе формы считаются валидными. Проверка: token присутствует в выходе в ЛЮБОЙ из форм → ок.
- **D-07:** Для токенов без алиаса (URL, email, числа, незнакомые бренды) — проверка как раньше, без изменений.

### Незнакомые бренды/сленг
- **D-08:** Осознанный компромисс: таблица покрывает топ-25 брендов + 4 техтермина + ~15-20 сленговых пар. Незнакомые бренды/сленг обрабатываются общим edit distance (ослабленным для relaxed/formal). Таблицу можно расширять позже без архитектурных изменений.

### Claude's Discretion
- Конкретный список ~15-20 сленговых пар (на основе частотности в русской разговорной речи)
- Конкретные значения ослабленных порогов для relaxed/formal
- Реализация style-neutral нормализации (отдельная функция или inline в tokenizeForDistance)
- Порядок проверок в evaluate() (guard → protected tokens → distance)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Спека стилей — секция Gate
- `docs/superpowers/specs/2026-03-29-text-styles-v2-design.md` — строки 52-74: Gate две оси, protected tokens, edit distance, таблица брендов/техтерминов

### Текущая реализация gate
- `Govorun/Core/NormalizationGate.swift` — полный файл: evaluate(), protectedTokensForNormalization(), tokenizeForDistance(), canonicalize(), tokenEditDistance(), editDistanceThreshold()

### Таблицы алиасов (Phase 1)
- `Govorun/Models/SuperTextStyle.swift` — строки 232-266: brandAliases (25), techTermAliases (4), static let формат

### Существующие тесты
- `GovorunTests/NormalizationGateTests.swift` — текущие тесты gate (без style-awareness)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SuperTextStyle.brandAliases` / `.techTermAliases` — готовые таблицы [(original, relaxed)], gate будет использовать
- `NormalizationGate.canonicalize()` — lowercased + case/diacritic insensitive, база для расширения
- `NormalizationGate.tokenizeForDistance()` — принимает ignoredLiterals, можно расширить для style-neutral нормализации
- `NormalizationGate.protectedTokensForNormalization()` — regex-based extraction, нужно расширить для alias-aware проверки

### Established Patterns
- Caseless enum `NormalizationGate` — static methods, private helpers
- `LLMOutputContract` уже в том же файле — gate знает про contract
- `ignoredOutputLiterals: Set<String>` — паттерн для исключения токенов, можно использовать для алиасов
- `editDistanceThreshold(for:input:)` — уже адаптивный (short vs long, correction cue), расширяется на стили

### Integration Points
- `PipelineEngine.processPipeline()` → вызывает `NormalizationGate.evaluate()` — нужно добавить superStyle параметр
- Phase 3 D-04: вызов уже bridged на `currentSuperStyle?.contract ?? .normalization` — сигнатура gate ещё не менялась
- `SuperTextStyle.contract` → возвращает LLMOutputContract — gate получает contract и superStyle как отдельные оси

</code_context>

<specifics>
## Specific Ideas

- Таблица сленга должна быть расширяемой (static let, тот же формат что brandAliases) — чтобы добавлять пары без архитектурных изменений
- При superStyle == nil (classic path) gate работает точно как раньше — никакие style-aware проверки не активируются

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 04-gate-modernization*
*Context gathered: 2026-03-31*
