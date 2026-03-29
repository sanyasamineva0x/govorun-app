# Stack Research

**Domain:** Текстовые стили формальности для macOS voice input app
**Researched:** 2026-03-29
**Confidence:** HIGH

## Recommended Stack

### Core Technologies (уже в проекте)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift 5.10+ | 5.10 | Основной язык | Уже в проекте, CaseIterable + computed properties идеальны для enum-driven styles |
| SwiftUI | macOS 14+ | UI компоненты | Picker/segmented control для авто/ручной, карточки стилей |
| SwiftData | macOS 14+ | Персистенция истории | HistoryItem уже использует SwiftData, String поле — без migration |
| UserDefaults | Foundation | Настройки пользователя | superStyleMode + manualSuperStyle — простые enum rawValues |

### Паттерны для SuperTextStyle

| Pattern | Purpose | When to Use |
|---------|---------|-------------|
| `CaseIterable` enum с `rawValue: String` | SuperTextStyle перечисление | Для serialization в UserDefaults и SwiftData |
| Computed properties на enum | `styleBlock`, `systemPrompt`, `contract` | Для инкапсуляции стиль-зависимой логики в одном месте |
| `@AppStorage` wrapper | Binding к UserDefaults | Для UI настроек авто/ручной режим |
| Protocol-based DI | MockLLMClient для тестов | Уже используется — обновить сигнатуру normalize() |

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Enum с computed properties | Protocol + struct per style | Если стили нужно расширять плагинами — не наш случай, 3 фиксированных стиля |
| Жёсткий bundleId mapping (dict) | NSWorkspace.shared.frontmostApplication | Уже есть AppContextEngine — использовать его bundleId |
| String rawValue в SwiftData | Custom Transformer | Не нужно — String достаточно, без model migration |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| SwiftData model migration | Поле `textMode` уже String, новые значения вписываются | Оставить String, менять только записываемые значения |
| NSWorkspace для bundleId | AppContextEngine уже абстрагирует это | SuperStyleEngine использует bundleId из AppContext |
| Per-app override system | Спека явно исключает per-app overrides | Глобальный авто/ручной переключатель |
| Перегрузки LLMClient.normalize() | Две сигнатуры = путаница | Одна сигнатура: `normalize(_:superStyle:hints:)` |

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| Swift 5.10 CaseIterable | macOS 14+ | Полная поддержка, включая allCases |
| SwiftData @Model | String properties | Нет migration при смене значений, только при смене типа |
| UserDefaults | RawRepresentable enums | register(defaults:) для начальных значений |

---
*Stack research for: SuperTextStyle text formality system*
*Researched: 2026-03-29*
