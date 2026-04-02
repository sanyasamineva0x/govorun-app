# Phase 9: TextMode Deletion - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 09-textmode-deletion
**Areas discussed:** History display, HistoryStore.save(), AppContextEngine scope

---

## History Display

| Option | Description | Selected |
|--------|-------------|----------|
| Ничего не показывать | Если SuperTextStyle не распознал — бейдж стиля не выводится | ✓ |
| Показать как есть | Вывести сырое значение ("chat", "email") | |
| Маппинг старых значений | chat→"Чат", email→"Почта" и т.д. | |

**User's choice:** Ничего не показывать
**Notes:** Старые записи с TextMode значениями не получают бейдж стиля

---

## HistoryStore.save()

| Option | Description | Selected |
|--------|-------------|----------|
| Да, писать стиль | superStyle?.rawValue ?? "none" как сейчас | ✓ |
| Нет, оставить пустым | Поле есть, но ничего не пишем | |

**User's choice:** Да, писать стиль
**Notes:** Пользователь хочет видеть стиль в новых записях истории

---

## AppContextEngine Scope

Техническое решение (не требовало выбора пользователя):
- AppContextEngine нельзя удалить целиком — bundleId нужен для SuperStyleEngine и аналитики
- Удаляется только TextMode-специфичный код (textMode поле, defaultAppModes, resolveTextMode, AppModeOverriding)

---

## Claude's Discretion

- Порядок удаления файлов и правок
- Структура тестовых правок
- Необходимость xcodegen generate

## Deferred Ideas

None
