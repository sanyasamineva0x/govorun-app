# Phase 3: Pipeline Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-30
**Phase:** 03-pipeline-integration
**Areas discussed:** SuperTextStyle wiring, TextMode removal scope, PipelineResult consumers, NormalizationGate bridge

---

## SuperTextStyle Wiring

| Option | Description | Selected |
|--------|-------------|----------|
| Захардкодить .auto + .normal | SuperStyleEngine.resolve(bundleId, mode: .auto, manualStyle: .normal) до Фазы 6 | ✓ |
| Подтянуть DATA-01/DATA-02 раньше | Добавить superStyleMode + manualSuperStyle в SettingsStore сейчас | |
| Мост TextMode → SuperTextStyle | Конвертировать TextMode маппингом (chat→relaxed, email→formal, universal→normal) | |

**User's choice:** Захардкодить .auto + .normal
**Notes:** По рекомендации Claude — мост создаёт мёртвый код, подтягивание DATA рано = лишняя связанность.

---

## TextMode Removal Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Всё за раз | Полная замена _textMode → _superStyle во всём PipelineEngine | ✓ |
| Только LLM path | Заменить только в normalize() вызове, textMode оставить в gate/result | |

**User's choice:** Всё за раз
**Notes:** По рекомендации Claude — требования говорят "вместо", а не "рядом". SuperTextStyle.contract даёт тот же результат что и textMode.llmOutputContract.

---

## PipelineResult Consumers

| Option | Description | Selected |
|--------|-------------|----------|
| Минимально для компиляции | HistoryStore/analytics минимальные правки, полные фичи в Фазах 6-7 | |
| Полный обнов сейчас | Все потребители полностью переходят на superStyle | ✓ |

**User's choice:** Полный обнов сейчас
**Notes:** —

---

## NormalizationGate Bridge

| Option | Description | Selected |
|--------|-------------|----------|
| superStyle.contract | Заменить currentTextMode.llmOutputContract → currentSuperStyle.contract | ✓ |
| Хардкод .normalization | Все стили в v2 возвращают .normalization, захардкодить до Phase 4 | |
| Ты решай | Claude's discretion | |

**User's choice:** superStyle.contract
**Notes:** —

---

## Claude's Discretion

- Порядок обновления файлов
- Обработка nil superStyle в PipelineResult
- Имена параметров в snapshotConfig()

## Deferred Ideas

None — discussion stayed within phase scope.
