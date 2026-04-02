# Phase 8: UI - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 08-ui
**Areas discussed:** Размещение UI, Layout карточек, Состояние без модели, Авто-режим отображение

---

## Размещение UI

| Option | Description | Selected |
|--------|-------------|----------|
| NSMenuItem с кастомным NSHostingView | SwiftUI карточка прямо в NSMenu | |
| Submenu "Говорун Супер" | NSMenuItem с подменю для стилей | |
| Секция в основном меню | Плоские пункты между разделителями | |
| Секция в SettingsView | Новая вкладка в окне настроек (сайдбар) | ✓ |

**User's choice:** Секция в SettingsView — "сделай карточку в самом приложении а не в менюбаре"
**Notes:** Спека писалась под menubar, решение — перенести в Settings. Вкладка всегда видна, без модели показывает disabled контент.

---

## Layout карточек стилей

| Option | Description | Selected |
|--------|-------------|----------|
| Горизонтально в ряд | Три карточки одинаковой ширины рядом | |
| Вертикально списком | Карточки друг под другом, полная ширина | ✓ |
| Сегмент + описание | Picker .segmented как у ProductMode/RecordingMode | |

**User's choice:** Вертикально списком
**Notes:** Больше места под описания стилей

---

## Состояние "без модели"

| Option | Description | Selected |
|--------|-------------|----------|
| BrandedEmptyState | Стандартный empty state с иконкой и кнопкой | |
| Карточки disabled + overlay | Карточки серые/размытые, overlay с пояснением | ✓ |

**User's choice:** Карточки disabled + overlay
**Notes:** Пользователь видит что его ждёт после скачивания модели

---

## Авто-режим отображение

| Option | Description | Selected |
|--------|-------------|----------|
| Live стиль + имя приложения | "Расслабленный · Telegram", обновляется | |
| Статический текст | "Стиль определяется автоматически по приложению" | ✓ |
| Пример с last app | "Сейчас было бы: Расслабленный · Telegram" | |

**User's choice:** Статический текст
**Notes:** Окно настроек = Говорун активное приложение, live-обновление не имеет смысла

---

## Claude's Discretion

- Иконка и title для секции в сайдбаре
- Точный текст описаний на карточках
- Визуальный стиль disabled overlay
- Анимации и структура View

## Deferred Ideas

None
