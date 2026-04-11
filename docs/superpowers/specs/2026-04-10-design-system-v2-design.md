# Дизайн-система Говоруна v2

Полная замена визуальной идентичности: палитра, типографика, поверхности, компоненты.
Вдохновение: pampam.city — тепло из типографики, сдержанность в цвете, воздух.

## Мотивация

Текущий дизайн generic: `.ultraThinMaterial` + системный шрифт + Cotton Candy на opacity 4-6% = неотличим от любой macOS-утилиты. Новая система строится на serif-типографике, одном живом цвете и чёрных действиях.

## Палитра

| Имя | Hex | Роль |
|-----|-----|------|
| **Snow** | `#FEFEFE` | Основной фон |
| **Mist** | `#F0EEEC` | Разделители, бордеры, выключенный toggle |
| **Ink** | `#1B1917` | Основной текст, кнопки primary, toggle on |
| **Sage** | `#3D7B6E` | Waveform bars, статусная точка, иконки секций |
| **Ember** | `#C85046` | Ошибки |

### Производные

- Вторичный текст: `Ink` opacity 0.38
- Третичный текст: `Ink` opacity 0.25
- Лейблы: `Ink` opacity 0.28
- Processing pill tint: `Sage` opacity 0.07
- Recording pill tint: `Sage` opacity 0.12
- Error pill tint: `Ember` opacity 0.12
- Waveform glow: `Sage` opacity 0.3, radius 5

### Удаляемые цвета

| Старый | Hex | Замена |
|--------|-----|--------|
| Cotton Candy | `#B36A5E` | Sage `#3D7B6E` |
| Sky Aqua | `#0ACDFF` | Sage `#3D7B6E` (opacity 0.5 для processing) |
| Ocean Mist | `#60AB9A` | Sage `#3D7B6E` |
| Petal Frost | `#FBDCE2` | удалить |
| Alabaster Grey | `#DEDEE0` | Mist `#F0EEEC` |

## Типографика

### Заголовки — Source Serif 4 (bundled)

| Уровень | Размер | Вес | Letter-spacing |
|---------|--------|-----|----------------|
| Page title | 28pt | 700 (bold) | -0.03em |
| Section | 22pt | 700 (bold) | -0.02em |
| Subsection | 18pt | 600 (semibold) | -0.01em |
| Empty state title | 17pt | 600 | -0.01em |

### Body — System (SF Pro)

| Уровень | Размер | Вес |
|---------|--------|-----|
| Body | 14pt | regular |
| Row title | 13pt | regular |
| Row description | 11pt | regular, Ink 0.35 |
| Caption | 12pt | regular |
| Label | 11pt | medium, uppercase, 1.5px tracking |
| Small label | 10pt | medium |

### Реализация

Source Serif 4 Variable — один файл `.ttf`, ~200 КБ. Добавить в bundle через `project.yml` copy phase + зарегистрировать в `Info.plist` (`ATSApplicationFontsPath`). В SwiftUI: `Font.custom("SourceSerif4-Bold", size: 28)`.

## Поверхности

### Убрать

- `.ultraThinMaterial` — везде
- `.background.opacity(0.8)` — везде
- `SettingsCardModifier` (padding + material + roundedRect) — заменить на строки с разделителями
- `StatusCardModifier` (accent bar + material) — заменить на точку + текст

### Новый подход

- Фон: `Snow` (#FEFEFE)
- Группа настроек: тонкий бордер `Mist` (#F0EEEC), border-radius 14pt, padding 24pt
- Строки внутри: разделитель `Mist` 1px, padding 12pt vertical
- Нет фоновых карточек, нет material, нет теней

## Компоненты

### SectionPageHeader

**Было:** Icon + title (.system 20pt semibold) + subtitle + gradient line
**Стало:** Icon (Sage, opacity 0.7) + title (Source Serif 4, 22pt, 700) + subtitle (Ink 0.38) + divider Mist 1px

### BrandedButton

**Было:** Capsule, Cotton Candy fill/outline
**Стало:**
- Primary: Ink fill, white text, border-radius 8pt
- Secondary: Mist border, Ink text opacity 0.5, border-radius 8pt

### SettingsToggleRow

**Было:** Icon + VStack + Toggle, обёрнуто в card
**Стало:** без карточки, разделители Mist. Toggle on = Ink fill. Toggle off = Mist fill.

### BrandedEmptyState

**Было:** Icon 30pt Cotton Candy + title callout + subtitle caption
**Стало:** Icon 26pt opacity 0.12 + title Source Serif 4 17pt/600 + subtitle Ink 0.38 + dark button

### StatusCard → StatusDot

**Было:** accent bar 3px + material background
**Стало:** dot 6px Sage + text Ink opacity 0.5, inline

### CountBadge

**Было:** Alabaster Grey background capsule
**Стало:** Mist background capsule, text Ink opacity 0.38

### AddButton

**Было:** plus.circle.fill Cotton Candy
**Стало:** plus.circle.fill Ink opacity 0.5, hover → opacity 0.8

### SettingsSearchBar

**Было:** Alabaster Grey 0.12 background
**Стало:** Mist background, Ink text, placeholder Ink 0.25

### Bottom Bar (BottomBarView)

Waveform bars: Sage вместо Cotton Candy. Glow: Sage opacity 0.3.
Processing bars: Sage вместо Sky Aqua.
Error icon/tint: Ember вместо Cotton Candy.
Model loading spinner tint: Sage вместо Sky Aqua.

## Sidebar (SettingsView)

Иконки секций: Sage opacity 0.7 (было Cotton Candy).
Selected state: Ink text, без цветного фона.

## Onboarding

Accent line (progress bar): Sage gradient вместо Cotton Candy gradient.
Кнопки: Ink fill вместо Cotton Candy fill.
Иконки шагов: Sage.

## Файлы для изменения

| Файл | Что менять |
|------|-----------|
| `Govorun/Views/SettingsTheme.swift` | Палитра, все модификаторы и компоненты |
| `Govorun/App/BottomBarView.swift` | Waveform/processing/error цвета |
| `Govorun/App/BottomBarWindow.swift` | BrandColors (AppKit NSColor) |
| `Govorun/Views/SettingsView.swift` | Sidebar, layout |
| `Govorun/Views/OnboardingView.swift` | Accent colors, buttons |
| `Govorun/Views/DictionaryView.swift` | Empty state, list styling |
| `Govorun/Views/SnippetListView.swift` | Empty state, list styling |
| `Govorun/Views/HistoryView.swift` | List styling |
| `Govorun/Views/TextStyleSettingsView.swift` | Accent colors |
| `Govorun/Views/GeneralSettingsView.swift` | Toggle rows, buttons |
| `Govorun/Views/SuperSettingsView.swift` | Status, download progress |
| `project.yml` | Copy phase для Source Serif 4 font file |
| `Govorun/Info.plist` | ATSApplicationFontsPath |

## Что НЕ меняется

- OrganicPillShape — остаётся как есть
- PillMotion choreography — таминги не трогаем
- LiquidGlassPillModifier — macOS 26+ glass остаётся
- Layout sidebar + content — структура та же
- Все протоколы и Core/Services слои — только Views/App

## Визуальная иерархия (уточнения после итераций)

### Принципы layout

- **Никаких карточек с бордерами** внутри секций. `.settingsCard()` = no-op.
- **Разделители (Divider)** только между крупными секциями, не внутри смысловых блоков.
- **Spacing 16pt** между блоками в content area.
- **Toggle rows без dividers** — vertical padding 6pt между рядами, единообразный формат: icon + text + Spacer + control.

### Hero-блок (KeyRecorderView + статус)

- Объединяет статус worker и горячую клавишу в одном блоке.
- Иконка 52×52, Sage фон (`sage.opacity(0.12)`), cornerRadius 12.
- Иконка **динамическая** — показывает `activationKey.displayName` (Text, monospaced 20pt), не хардкод.
- Заголовок: "Зажмите {клавиша} и говорите" — 16pt medium.
- Subtitle: контекстный статус (готов / качаю модель / ошибка) — caption, Ink 0.5.
- Hover: фоновая заливка `ink.opacity(0.03)` + "Изменить" справа.
- Карточка: Mist border 1px, cornerRadius 14.
- **Recording state** сохраняет размер hero (52px иконка, 16pt текст, sage border 2px).

### Dropdown вместо Segmented Picker

- "Режим Говоруна" и "Режим работы" используют `.pickerStyle(.menu)` вместо `.segmented`.
- Формат как toggle row: icon + label/description слева, picker `.fixedSize()` справа.
- Описание режима на второй строке (caption, Ink 0.5).

### Section Headers

- `SectionHeader` — Source Serif 4, 18pt semibold, tracking -0.2.
- Иконки убраны из section headers — serif шрифт создаёт иерархию.
- `padding(.top, 16)` для отступа от предыдущего контента.

### Описания (вторичный текст)

- Opacity 0.5 (было 0.35) — читабельнее.
- Максимум две иерархии текста: title + description. Третья убрана.

## Ограничения

- Source Serif 4 добавляет ~200 КБ к бандлу
- Dark mode: Ink и Snow инвертируются (Snow → #1B1917, Ink → #FEFEFE, Mist → rgba(255,255,255,0.08), Sage и Ember без изменений)
- Liquid Glass на macOS 26+ — Sage tint вместо Cotton Candy tint
- Segmented Picker tint нельзя поменять на macOS — остаётся системный accent
