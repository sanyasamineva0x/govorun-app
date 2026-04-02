---
status: partial
phase: 08-ui
source: [08-VERIFICATION.md]
started: 2026-04-01T16:00:00.000Z
updated: 2026-04-01T16:00:00.000Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Tab navigation and rendering
expected: Click "Стиль текста" in sidebar → SectionPageHeader with icon "textformat", title "Стиль текста", subtitle "Настройка стиля для Супер-режима". Segmented picker (Авто/Ручной) visible below.
result: [pending]

### 2. Picker mode switching
expected: Click "Ручной" → 3 style cards appear (Расслабленный, Обычный, Формальный) with staggered animation. Click "Авто" → static text "Стиль определяется автоматически по приложению".
result: [pending]

### 3. Style card selection
expected: Tap a different card → checkmark (cottonCandy color) moves to selected card. Selection persists after closing and reopening Settings.
result: [pending]

### 4. Model-missing overlay
expected: When superAssetsState != .installed → cards visible but dimmed (opacity 0.4, slight blur), overlay with "Для стилей нужна ИИ-модель" and "Перейти к скачиванию" button. Segmented picker still works under overlay.
result: [pending]

### 5. Overlay navigation button
expected: Tap "Перейти к скачиванию" → sidebar switches to "Основные" tab where ProductModeCard handles download.
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
