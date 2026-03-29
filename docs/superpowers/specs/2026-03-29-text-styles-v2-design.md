# Стили текста v2

Три уровня формальности с глобальным переключателем авто/ручной. `TextMode` удаляется — `SuperTextStyle` становится единственным enum стилей.

- **Classic path:** без стилей. Единственная настройка — `terminalPeriodEnabled`.
- **Super path:** `SuperTextStyle` (relaxed/normal/formal) управляет промптом, gate, точкой.

## Три стиля

Enum `SuperTextStyle` (`relaxed`, `normal`, `formal`).

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

Стили контролируют капитализацию, точку, бренды, техтермины и сленг (см. секцию "Что стиль контролирует"). Canonical forms выше — не зависят от стиля.

### Gate: две оси — contract и style

`NormalizationGate.evaluate(input:output:contract:superStyle:)` принимает два параметра стиля:

- **`contract: LLMOutputContract`** — какие проверки делать:
  - `.normalization` — strict: edit distance ≤40%, protected tokens, длина
  - `.rewriting` — lenient: только NER + длина ±50%, без edit distance
- **`superStyle: SuperTextStyle?`** — какие трансформации считать валидными:
  - `.relaxed` — Slack↔слак ок, PDF↔пдф ок
  - `.formal` — спс↔спасибо ок
  - `nil` (classic) — gate работает как раньше

Это разные оси. Стиль определяет допустимые замены, contract определяет допустимый масштаб изменений. `SuperTextStyle` имеет свойство `var contract: LLMOutputContract` — сейчас все три → `.normalization`. В 2.5 formal → `.rewriting`.

| | Normalization | Rewriting (2.5) |
|---|---|---|
| Relaxed | v2: бренды кириллицей, strict distance | — |
| Normal | v2: стандартные проверки | — |
| Formal | v2: сленг раскрыт, strict distance | v2.5: переписывание, lenient |

**Protected tokens:** если `superStyle == .relaxed`, brand aliases (Slack↔слак) и tech aliases (PDF↔пдф) — обе формы валидны. Если `.formal` — slang expansions (спс↔спасибо) валидны.

**Edit distance:** перед подсчётом нормализовать оба текста к style-neutral form. Стилистические трансформации не считаются "правками".

### Postflight: стиль владеет точкой

Если `superStyle != nil` — стиль определяет точку (relaxed/normal → без, formal → с). Если `nil` (classic) — `terminalPeriodEnabled` из настроек.

### Известное ограничение v1: trivial path

Trivial path (короткие фразы, `shouldInvokeLLM == false`) не вызывает LLM. `applyDeterministic()` покрывает только caps и точку. Бренды, техтермины, сленг — только через LLM. Если LLM упал (graceful degradation) — то же ограничение. Осознанный компромисс: полная стилизация требует LLM.

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

Глобальный переключатель. Per-app overrides не поддерживаются. Ручной режим — один стиль на всё приложение.

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

**"Стиль текста"**.

### Вкладка Говорун Супер в menubar-меню

Не в onboarding.

**Модель есть:**
- Сегмент: Авто | Ручной
- Авто — подпись текущего стиля серым ("Расслабленный · Telegram")
- Ручной — три карточки стилей с кратким описанием, чекмарк на выбранном

**Модель не скачана:**
- Пункт активен, но стилизован как недоступный (серый текст, иконка замка)
- При нажатии — NSAlert: "Для работы Супер-режима нужна ИИ-модель. Скачайте её в настройках приложения." + кнопка "Понял"

## Удаление TextMode

Breaking change. `TextMode` удаляется вместе со всей инфраструктурой:

**Удаляются файлы:**
- `Govorun/Models/TextMode.swift`
- `Govorun/Views/AppModeSettingsView.swift`

**Удаляются протоколы и классы:**
- `AppModeOverriding` протокол
- `UserDefaultsAppModeOverrides` класс
- Вкладка App Modes в настройках

**Изменяются:**
- `AppContextEngine` — возвращает только `bundleId`/`appName`, без `textMode`
- `LLMClient.normalize()` — одна сигнатура с `SuperTextStyle` вместо `TextMode`
- `LocalLLMClient` — `sendChatCompletion` использует `SuperTextStyle.systemPrompt()`
- `NormalizationHints` — теряет поле `textMode`
- `NormalizationGate.evaluate()` — принимает `contract: LLMOutputContract` + `superStyle: SuperTextStyle?` (две разных оси: contract = какие проверки, style = какие трансформации валидны). `SuperTextStyle` имеет свойство `contract` → сейчас все три → `.normalization`, в 2.5 formal → `.rewriting`
- `NormalizationPipeline.postflight()` — `superStyle: SuperTextStyle?` вместо `textMode: TextMode`
- `PipelineEngine` — только `superStyle: SuperTextStyle?` (nil в classic)
- `SettingsStore` — удалить `defaultTextMode`, добавить `superStyleMode` + `manualSuperStyle`
- `AppState` — убрать TextMode из handleActivated, superStyle привязан к effective pipeline state

**Миграция UserDefaults:**
- `defaultTextMode` — удалить при первом запуске
- `superStyleMode` — новый ключ, default `.auto`
- `manualSuperStyle` — новый ключ, default `.normal`
- Старые event values в аналитике не трогаем

**Миграция тестов:**
- `AppContextEngineTests` — убрать проверки TextMode
- `SettingsStoreTests` — убрать тесты defaultTextMode, добавить superStyle тесты
- `TestHelpers.MockLLMClient` — обновить сигнатуру
- `SnippetEngineTests`, `HistoryStoreTests` — убрать TextMode references

## Аналитика

Поля в событиях:
- `product_mode` (standard/super)
- `style_selection_mode` (auto/manual) — только в Super
- `effective_style` (relaxed/normal/formal/none)
- `detected_app_bundle`

## Тестирование

- Unit-тесты `SuperTextStyle`: enum, styleBlock, systemPrompt, applyDeterministic
- Unit-тесты `SuperStyleEngine`: маппинг bundleId → стиль, авто/ручной
- Unit-тесты `SettingsStore`: superStyleMode, manualSuperStyle
- Unit-тесты `NormalizationGate`: style-aware protected tokens, slang expansion, edit distance
- Unit-тесты `NormalizationPipeline`: postflight с SuperTextStyle
- UI-тесты: вкладка Супер при наличии/отсутствии модели
- Style-aware бенчмарк: один input → три expected outputs
