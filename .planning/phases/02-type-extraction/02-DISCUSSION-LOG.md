# Phase 2: Type Extraction - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 02-type-extraction
**Areas discussed:** NormalizationHints без textMode, Объём обновления потребителей, Файловая структура

---

## NormalizationHints без textMode

| Option | Description | Selected |
|--------|-------------|----------|
| Убрать, не заменять | Удалить textMode сейчас, superStyle добавит Фаза 3. Чистая экстракция. | ✓ |
| Заменить на superStyle | Добавить superStyle: SuperTextStyle? = nil сразу. Фаза 2 толще, но Фаза 3 проще. | |
| Оставить временно | Вынести struct как есть с textMode. Минимальная Фаза 2, но нарушает EXTRACT-03. | |

**User's choice:** Убрать, не заменять
**Notes:** Чистое разделение ответственности — Фаза 2 только экстракция, Фаза 3 добавляет superStyle.

---

## Объём обновления потребителей

| Option | Description | Selected |
|--------|-------------|----------|
| Убрать textMode: отовсюду | Удалить передачу textMode: во всех 7 файлах включая тесты. | ✓ |
| Минимально: только структ | Убрать поле из struct, но потребителей обновлять минимально. | |

**User's choice:** Убрать textMode: отовсюду
**Notes:** Полная очистка всех вызовов.

---

## Файловая структура

| Option | Description | Selected |
|--------|-------------|----------|
| Отдельные файлы (как в REQ) | SnippetPlaceholder.swift + SnippetContext.swift + NormalizationHints.swift | ✓ |
| Один файл Snippet.swift | Объединить SnippetPlaceholder и SnippetContext в один файл | |

**User's choice:** Отдельные файлы (как в REQ)
**Notes:** Соответствует EXTRACT-01/02 буквально и паттерну кодовой базы (один тип = один файл).

---

## Claude's Discretion

- Порядок MARK-секций в новых файлах
- Sendable conformance при необходимости

## Deferred Ideas

None
