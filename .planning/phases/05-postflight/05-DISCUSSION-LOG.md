# Phase 5: Postflight - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 05-postflight
**Areas discussed:** Охват стиля за пределами LLM, Капитализация в postflight, Точка: взаимодействие стиля и настройки, DeterministicNormalizer и стиль

---

## Охват стиля за пределами LLM

| Option | Description | Selected |
|--------|-------------|----------|
| Стиль везде | Все пути в PipelineEngine уважают superStyle — relaxed всегда строчная без точки, formal всегда с точкой. Консистентный UX. | ✓ |
| Только LLM путь | Стиль влияет только на postflight (после LLM). Тривиальные фразы и сниппеты используют classic поведение. | |
| Стиль везде кроме сниппетов | Тривиальные фразы уважают стиль, но сниппеты вставляются as-is. | |

**User's choice:** Стиль везде
**Notes:** Консистентный UX — пользователь не должен замечать разницы между LLM и не-LLM путями.

---

## Капитализация в postflight

| Option | Description | Selected |
|--------|-------------|----------|
| Принудительно | postflight всегда применяет applyDeterministic на финальный текст. Гарантированный результат. | ✓ |
| Доверять LLM | systemPrompt уже инструктирует LLM про caps. Не менять выход. Проще, но ненадёжно. | |

**User's choice:** Принудительно
**Notes:** applyDeterministic как safety net — LLM может не следовать промпту на 100%.

---

## Точка: взаимодействие стиля и настройки

| Option | Description | Selected |
|--------|-------------|----------|
| Стиль побеждает | superStyle != nil → стиль определяет точку, terminalPeriodEnabled игнорируется. Простая ментальная модель. | ✓ |
| Настройка побеждает | terminalPeriodEnabled всегда имеет приоритет над стилем. Смысл стилей теряется. | |
| Объединение (OR) | Точка ставится если стиль требует OR настройка включена. Сложная ментальная модель. | |

**User's choice:** Стиль побеждает
**Notes:** Соответствует POST-01/POST-02. Super = стиль решает всё.

---

## DeterministicNormalizer и стиль

| Option | Description | Selected |
|--------|-------------|----------|
| applyDeterministic после | DeterministicNormalizer.normalize() не трогаем. Caller применяет superStyle?.applyDeterministic(). 0 затронутых callsites. | ✓ |
| Добавить superStyle в normalize() | Меняем сигнатуру normalize(_:terminalPeriodEnabled:superStyle:). Единая точка, но 30+ callsites обновляются. | |

**User's choice:** applyDeterministic после
**Notes:** Минимальные изменения. DeterministicNormalizer остаётся style-agnostic.

---

## Claude's Discretion

- Вспомогательный property `var terminalPeriod: Bool` на SuperTextStyle
- Порядок операций: точка → caps
- Рефакторинг дублирования terminalPeriodEnabled в PipelineEngine
- Структура тестов

## Deferred Ideas

None — discussion stayed within phase scope.
