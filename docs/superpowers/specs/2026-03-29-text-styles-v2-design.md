# Стили текста v2 (Super-only)

Три уровня формальности для Говорун Super с глобальным переключателем авто/ручной. Фича только для Super-режима — classic path (TextMode, AppModeSettingsView, AppModeOverriding) не затрагивается.

## Три стиля

Новый enum `SuperTextStyle` (`relaxed`, `normal`, `formal`), отдельный от существующего `TextMode`.

| | Расслабленный | Обычный | Формальный |
|---|---|---|---|
| Капитализация | строчная | С заглавной | С заглавной |
| Точка в конце | нет | нет | да |
| Обращение | как сказал пользователь | как сказал пользователь | как сказал пользователь |
| Бренды | кириллица (слак, зум, телега) | оригинал (Slack, Zoom, Telegram) | оригинал (Slack, Zoom, Telegram) |
| Техтермины | естественные транслитерации (пдф, апи, урл, пр) | оригинал (PDF, API, URL, PR) | оригинал (PDF, API, URL, PR) |
| Сленг (норм, спс) | сохранять | сохранять | раскрывать (нормально, спасибо) |
| Филлеры (ну, короче) | убирать | убирать | убирать |

### LLM-контракт

Все три стиля работают в рамках **нормализации**: не перефразировать, не удалять предложения, не менять порядок слов. Стиль влияет на форматирование и точечные замены.

**Уровень 2.5 (следующий шаг):** формальный стиль с rewriting contract — морфологическое ты→Вы, переписывание оборотов в деловой стиль. Отдельный скоуп, отдельный seed corpus. См. `docs/llm-normalization-roadmap.md`.

### Что стиль контролирует

- Начальная капитализация
- Конечная точка
- Бренды (кириллица/оригинал)
- Техтермины (естественные транслитерации/оригинал)
- Сленг (сохранять/раскрывать)

### Что не зависит от стиля (единый канон)

Source of truth: `docs/canonical-style-spec.md`. Один канон для classic и Super — стили НЕ меняют эти формы:

- Числа (25, 3 200 000)
- Проценты (12,5%)
- Валюты (900 рублей, 20 000 рублей)
- Даты (23 марта 2026)
- Время (15:30)
- Единицы измерения (5 килограммов, 2 литра, 10 километров)
- Обращение (ты/Вы) — как сказал пользователь во всех стилях
- Филлеры — убираются всегда
- Самокоррекция — убирается всегда

Стили влияют **только** на бренды и техтермины (см. таблицы ниже). Всё остальное — canonical-style-spec.

### Style-aware Gate и Postflight

LLM-слой финальный — стиль может менять то, что deterministic layer поставил. Это создаёт три конфликта с текущим pipeline, которые нужно решить:

**1. Protected tokens (NormalizationGate)**

Gate извлекает бренды из input (например "Slack") и проверяет их наличие в output. В relaxed output будет "слак" — gate отклонит как `missingProtectedTokens`.

Решение: gate получает `SuperTextStyle`. В relaxed — protected tokens проверяются с учётом style-sensitive маппинга (Slack↔слак оба валидны). В normal/formal — без изменений.

**2. Edit distance (NormalizationGate)**

Relaxed меняет капитализацию + бренды + техтермины. Суммарный edit distance ratio может превысить threshold.

Решение: перед подсчётом edit distance нормализовать оба текста к canonical form (lowercase, бренды к одной форме). Стилистические трансформации не должны считаться "правками".

**3. Postflight terminal period**

`terminalPeriodEnabled` из настроек применяется после gate. Если пользователь включил точки, postflight добавит точку в relaxed output.

Решение: в Super mode стиль владеет конечной точкой, `terminalPeriodEnabled` игнорируется. Relaxed/normal → без точки, formal → с точкой. Пользовательская настройка `terminalPeriodEnabled` действует только в classic mode.

## Style-sensitive бренды

В relaxed — кириллицей, в normal/formal — оригинал:

| Оригинал | Relaxed |
|---|---|
| Slack | слак |
| Zoom | зум |
| Telegram | телега |
| Jira | жира |
| Notion | ношен |
| GitHub | гитхаб |
| YouTube | ютуб |
| Google | гугл |
| WhatsApp | вотсап |
| Discord | дискорд |
| Figma | фигма |
| Docker | докер |
| Chrome | хром |
| Safari | сафари |
| Teams | тимс |
| Trello | трелло |
| Confluence | конфлюенс |
| Excel | эксель |
| Word | ворд |
| Photoshop | фотошоп |
| iPhone | айфон |
| MacBook | макбук |
| Windows | винда |
| Linux | линукс |
| Python | питон |

### Style-sensitive техтермины (только естественные)

| Оригинал | Relaxed |
|---|---|
| PDF | пдф |
| API | апи |
| URL | урл |
| PR | пр |

Остальные техтермины (CSV, CI/CD, QA, ML, iOS) — canonical во всех стилях.

## Режим выбора: Авто vs Ручной

Глобальный переключатель. Per-app overrides не поддерживаются — осознанное упрощение. Ручной режим — один стиль на всё приложение.

### Авто — жёсткий bundleId mapping

| Стиль | BundleId |
|---|---|
| Расслабленный | `ru.keepcoder.Telegram`, `net.whatsapp.WhatsApp`, `com.viber.osx`, `com.vk.messenger`, `com.apple.MobileSMS`, `com.hnc.Discord` |
| Формальный | `com.apple.mail`, `com.readdle.smartemail-macos`, `com.microsoft.Outlook` |
| Обычный | всё остальное |

Неизвестные приложения → `normal`.

### Ручной

Пользователь выбирает один из трёх стилей, он применяется ко всем приложениям.

## UI

### Название в UI

**"Стиль текста"** — коротко, не путается с classic/super режимами.

### Вкладка Говорун Супер в menubar-меню

Не в onboarding.

**Модель есть:**
- Сегмент: Авто | Ручной
- Авто — подпись текущего стиля серым ("Расслабленный · Telegram")
- Ручной — три карточки стилей с кратким описанием, чекмарк на выбранном

**Модель не скачана:**
- Пункт активен, но стилизован как недоступный (серый текст, иконка замка)
- При нажатии — окно: "Для работы Супер-режима нужна ИИ-модель. Скачайте её в настройках приложения." + кнопка "Понял"

### Classic path — без изменений

`TextMode`, `AppModeSettingsView`, `AppModeOverriding` остаются нетронутыми.

## Реализация

- Новый enum `SuperTextStyle` (`relaxed`, `normal`, `formal`) — отдельный от `TextMode`
- `SuperStyleEngine` — bundleId → `SuperTextStyle` mapping (переиспользует `AppContextEngine.detectCurrentApp()`)
- `SettingsStore` — новые поля: `superStyleMode: .auto | .manual`, `manualSuperStyle: SuperTextStyle`
- Стиль-блоки в Super промпте перегенерируются под три стиля
- Старые event values в аналитике не трогаем — исторические события остаются со старыми значениями

## Аналитика

Новые поля в событиях:
- `product_mode` (standard/super)
- `style_selection_mode` (auto/manual)
- `effective_style` (relaxed/normal/formal)
- `detected_app_bundle`

## Тестирование

- Unit-тесты `SuperStyleEngine`: маппинг bundleId → стиль, авто/ручной переключение
- Unit-тесты `SuperTextStyle`: styleBlock для каждого стиля
- Unit-тесты `SettingsStore`: переключение auto/manual, персистенция manualSuperStyle
- UI-тесты: состояние вкладки Супер при наличии/отсутствии модели, переключение сегмента, выбор стиля
- Style-aware бенчмарк: один input → три expected outputs (по стилю). Расширить seed dataset.
