# Phase 14: Pipeline Hardening - Context

**Gathered:** 2026-04-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Cloud output доходит до всех post-processing стадий (SnippetEngine, DictionaryStore, ListFormatter) и красиво падает при отсутствии сети. Standard и Super режимы не трогаем — zero regression. Phase 14 работает внутри `PipelineEngine.processCloudPath()`.

**In scope:** CLOUD-05 (снипеты на cloud output), MODE-05 (Gate/ListFormatter совместимость), offline fast-fail через NetworkMonitor.
**Out of scope:** NormalizationGate implementation для cloud (skipped для MVP), output sanity checks (deferred), UI для offline индикатора (Phase 15).

</domain>

<decisions>
## Implementation Decisions

### Snippets в Cloud (CLOUD-05)

- **D-01:** Option G — snippet dictionary передаётся в `systemPrompt` первого (и единственного) cloud вызова. Cloud делает substitution inline с учётом грамматики. Формат prompt addendum: список триггеров и их content с инструкцией «сохраняй токены/значения дословно, перестраивай фразу грамматически».
- **D-02:** Post-process safety net: после cloud output запускаем `SnippetEngine.match(cloudOutput)`. Если cloud не сделал substitution (trigger всё ещё в тексте), применяем локальный fallback.
- **D-03:** **Standalone fallback:** литеральная замена всего текста на content (существующее поведение).
- **D-04:** **Embedded fallback:** новый helper `SnippetReinserter.cleanSubstitute(text, trigger, content)` — использует существующий `triggerRange` (word-boundary safe) и `replacingCharacters(in:with:)` для direct substitution БЕЗ `trigger:` префикса. Отличие от `mechanicalFallback` в Standard — более чистый output. В Standard поведение не меняем.
- **D-05:** Порядок snippet match в cloud path: **после** DictionaryStore replacements (D-10), **до** applyPostProcessing.

### NormalizationGate в Cloud (MODE-05)

- **D-06:** Gate **не запускается** в cloud path. Обоснование: отсутствует reference input для edit distance check; cloud с temperature=0.1 и production-grade moderation имеет low hallucination risk.
- **D-07:** MODE-05 интерпретируется как «Gate код не модифицируется» — скипаем Gate в cloud fork, не переписываем его логику. В Standard/Super режимах Gate работает как прежде.
- **D-08:** Output-only sanity check (refusal detection, system prompt leak, anomalous length) — **отложен** в deferred ideas. Если production feedback покажет проблемы — добавим в отдельной фазе.

### Offline Degradation (Phase 14 criterion #4)

- **D-09:** Graceful fallback: на входе в `processCloudPath()` проверяем `NetworkMonitor.isCurrentlyConnected`. Если false → routing в существующий local STT flow (как в Standard режиме): `sttClient.recognize` → `DictionaryStore.applyReplacements` → `SnippetEngine.match` (mechanical fallback для embedded, т.к. нет LLM) → `DeterministicNormalizer.preflight` → `applyPostProcessing`. Cloud API не вызывается, 30s timeout избегается.
- **D-09a:** Toast/notification уровня info: «Нет сети — использую локальную обработку». Не блокирующий diagnostic (UI может быть minimal, detail вынесем в Phase 15 если нужно).
- **D-09b:** NetworkMonitor inject в PipelineEngine (сейчас живёт в AppState). Два варианта: (1) передать NetworkMonitor в PipelineEngine init как протокол, (2) передать `cloudAvailable: () -> Bool` closure в `processCloudPath` snapshot. Выбор реализации — в плане.

### Dictionary Replacements

- **D-10:** `DictionaryStore.applyReplacements(cloudOutput, replacements: hints.personalDictionary)` вызывается **после** cloud output, **до** SnippetEngine.match. Cloud уже нормализует общие бренды — dictionary подхватит персональные термины юзера. Идемпотентно.

### Flow Order в processCloudPath (Phase 14 final)

```
1. stopRecording → audioData
2. NetworkMonitor check → if offline, route to local STT fallback (D-09)
3. cloudClient.processAudio(audioData, superStyle, snippet-aware systemPrompt) → cloudOutput
4. DictionaryStore.applyReplacements(cloudOutput, personalDictionary) → dictText (D-10)
5. SnippetEngine.match(dictText) fallback (D-02, D-03, D-04):
   - Standalone match → content literal
   - Embedded match → cleanSubstitute(trigger, content)
   - No match → dictText passthrough
6. applyPostProcessing(snippetText) → caps + ListFormatter → finalText
7. TextInsertion
```

### Claude's Discretion

- Конкретная форма snippet-aware system prompt extension (wording, placement относительно стилевого промпта) — определяется в плане с тестами
- NetworkMonitor injection strategy в PipelineEngine (protocol vs closure) — выбор в плане
- Toast UI реализация при offline fallback (существующий notification pattern vs новый)
- Расположение `cleanSubstitute` — static method в `SnippetReinserter` рядом с `mechanicalFallback`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Cloud path (Phase 12-13 output)

- `Govorun/Core/PipelineEngine.swift` — `processCloudPath` (строка 728-844), `applyPostProcessing` (строка 338-344)
- `Govorun/Core/PipelineEngine.swift` — existing snippet flow для reference (строки 433-586): `SnippetEngine.match`, `SnippetReinserter.reinsert`, `SnippetReinserter.mechanicalFallback`
- `Govorun/Services/CloudLLMClient.swift` — `processAudio` signature, systemPrompt construction
- `Govorun/Models/SuperTextStyle.swift` — `systemPrompt()` method (where snippet instructions will be appended)

### Snippets & Dictionary

- `Govorun/Core/SnippetEngine.swift` — `SnippetMatching` protocol, `match` method, `tokenize`
- `Govorun/Core/PipelineEngine.swift` — `SnippetReinserter` enum (строки 124-228): `reinsert`, `mechanicalFallback`, `triggerRange` (приватный — сделать internal или reuse)
- `Govorun/Storage/DictionaryStore.swift` — `applyReplacements(to:replacements:)` static method
- `Govorun/Models/NormalizationHints.swift` — `personalDictionary` field

### Network & Offline

- `Govorun/Core/NetworkMonitor.swift` — `isCurrentlyConnected` sync property, `isConnected` published
- `Govorun/App/AppState.swift` — existing `networkMonitor` ownership (строка 103)

### Pipeline Gate (для понимания что НЕ делаем)

- `Govorun/Core/NormalizationGate.swift` — Gate signature (skipped в cloud path, referenced но не вызывается)
- `Govorun/Models/LLMOutputContract.swift` — `.normalization` / `.rewriting` contracts

### Requirements

- `.planning/REQUIREMENTS.md` — CLOUD-05 (snippet matching on LLM output), MODE-05 (Gate/ListFormatter compat)

### Phase 13 Context (для baseline)

- `.planning/phases/13-mode-routing/13-CONTEXT.md` — cloud fork decisions, CloudLLMClient lifecycle, credentials gate

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `SnippetEngine.match(_)` — работает на любом входном тексте, tokenization уже robust (case/diacritic insensitive)
- `SnippetReinserter.triggerRange` — word-boundary safe matching, найти и сделать internal для cleanSubstitute
- `DictionaryStore.applyReplacements` — static, idempotent, подходит для cloudOutput
- `NetworkMonitor.isCurrentlyConnected` — sync snapshot, не зависит от async callback
- `applyPostProcessing` closure в `stopRecording` — уже captures superStyle/terminalPeriod, переиспользуется
- Local STT path в `stopRecording` (строки 358-683) — полный flow для offline fallback

### Established Patterns

- `@unchecked Sendable + NSLock + snapshotConfig` в PipelineEngine — расширяем под `CloudAudioProcessing?` уже сделано; для NetworkMonitor — расширяем snapshot или inject как closure
- DI через init parameters — NetworkMonitor injection согласуется с pattern
- Typed errors: `PipelineError.networkUnavailable` (new case) для очевидной диагностики

### Integration Points

- `processCloudPath` — точка входа для всех изменений Phase 14
- `SuperTextStyle.systemPrompt()` — добавить snippet extension method
- Phase 15 (UI) будет использовать `AppState.cloudAvailable` для picker disable; Phase 14 не меняет AppState public API

### Constraints

- Standard/Super режимы должны работать identically — regression-нулевые изменения в non-cloud code path (строки 358-683)
- Новый helper `cleanSubstitute` живёт рядом с `mechanicalFallback` в SnippetReinserter — не мутируем Standard behavior

</code_context>

<specifics>
## Specific Ideas

- Option G (snippet-aware systemPrompt) — prompt engineering требует аккуратного wording. Пример: «Пользователь может использовать ключевые слова. Заменяй их в выходном тексте, перестраивая фразу грамматически: 'почта' → 'sanya@example.com', 'моё имя' → 'Саша Самнева'. Никогда не добавляй оригинальное ключевое слово рядом с замещённым текстом.» Plan должен включать RED test с реалистичными фразами
- `cleanSubstitute` для embedded fallback — 5 строк, reuse `triggerRange`, direct `replacingCharacters(in:with:)`. Отличается от mechanicalFallback отсутствием `trigger: ` префикса
- NetworkMonitor тестирование — через protocol `NetworkAvailabilityProviding { var isCurrentlyConnected: Bool { get } }` + `NetworkMonitor` conformance + mock в тестах

</specifics>

<deferred>
## Deferred Ideas

- **Output-only sanity check для Cloud** — refusal detection, system prompt leak detection, anomalous length. Отложено до production feedback. Отдельная фаза при необходимости.
- **NormalizationGate адаптация для Cloud** — если появятся случаи cloud hallucination, можно построить content-only contract check. Не блокирует MVP.
- **Snippet-aware systemPrompt как отдельный компонент** — сейчас extension к `SuperTextStyle.systemPrompt()`. Если станет сложнее — выделить в `CloudSnippetPromptBuilder`. Phase 14 не создаёт этот компонент.
- **Offline indicator в menubar UI** — Phase 15 scope (settings UI в целом).
- **Quality benchmark cloud vs local для embedded snippets** — Phase 16 scope (tests).

</deferred>

---

*Phase: 14-pipeline-hardening*
*Context gathered: 2026-04-19*
