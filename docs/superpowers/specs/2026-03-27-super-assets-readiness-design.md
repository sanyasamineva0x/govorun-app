# Super Assets Readiness — Design Spec

## Проблема

Говорун Super существует как UI-переключатель, но пользователь не понимает: готов ли Super к работе, чего не хватает, и что делать. При отсутствии llama-server или GGUF модели Super молча падает через 20-секундный timeout.

## Цель этого PR

Readiness foundation: discovery ассетов, state machine, UI статусов, блокировка старта без ассетов. Скачивание/установка — следующий PR.

## Ассеты Super

| Ассет | Источник | Путь | Размер |
|-------|----------|------|--------|
| llama-server binary | App bundle (`Resources/llama-server`) | `Bundle.main.resourcePath` | ~5 MB |
| GigaChat GGUF model | Скачивается отдельно (будущий PR) | `~/.govorun/models/` | ~6 GB |

## SuperAssetsManager

### Протокол

```swift
protocol SuperAssetsManaging: Sendable {
    var state: SuperAssetsState { get }
    var runtimeBinaryURL: URL? { get }
    var modelURL: URL? { get }
    func check() async -> SuperAssetsState
}
```

### State Machine

```swift
enum SuperAssetsState: Equatable, Sendable {
    case unknown          // ещё не проверяли
    case checking         // проверка идёт
    case installed        // бинарник + модель на месте
    case modelMissing     // бинарник есть, модели нет
    case runtimeMissing   // бинарника нет (сломанный bundle)
    case error(String)    // файл нечитаем / повреждён
}
```

Переходы:
```
unknown → checking → installed
                   → modelMissing
                   → runtimeMissing
                   → error(String)
```

### Discovery логика

1. Ищем llama-server:
   - `Bundle.main.resourceURL/llama-server`
   - Fallback: `which llama-server` (PATH) — для dev-режима
   - Не найден → `.runtimeMissing`

2. Ищем GGUF модель:
   - `~/.govorun/models/*.gguf` — первый найденный файл
   - Env override: `GOVORUN_LLM_MODEL_PATH`
   - Не найден → `.modelMissing`

3. Валидация:
   - Binary: `FileManager.isExecutableFile(atPath:)`
   - Model: `FileManager.isReadableFile(atPath:)` + размер > 100 MB (sanity check)
   - Невалиден → `.error("описание")`

4. Оба на месте → `.installed`, заполняем `runtimeBinaryURL` и `modelURL`

### Resolved Paths

`LLMRuntimeManager` больше не ищет файлы сам. `AppState` передаёт resolved paths из `SuperAssetsManager`:

```swift
// AppState
let assetsState = await assetsManager.check()
guard assetsState == .installed,
      let binaryURL = assetsManager.runtimeBinaryURL,
      let modelURL = assetsManager.modelURL else {
    updateLLMRuntimeState(.disabled)
    return
}
let config = LocalLLMRuntimeConfiguration(
    runtimeBinaryPath: binaryURL.path,
    modelPath: modelURL.path,
    ...
)
try await llmRuntimeManager.updateConfiguration(config)
try await llmRuntimeManager.start()
```

## Изменения в AppState

### Cold Start

```
start()
├─ assetsManager.check()
├─ if .installed → runtimeManager.start(resolvedPaths)
├─ if .modelMissing → llmRuntimeState = .disabled, log
├─ if .runtimeMissing → llmRuntimeState = .disabled, log
└─ Standard mode не зависит от ассетов
```

### Mode Switch (standard → super)

```
handleSettingsChanged(productMode: .superMode)
├─ assetsManager.check()
├─ if .installed → applyProductMode(.superMode)
├─ if != .installed → остаёмся на .standard, UI показывает причину
```

## Изменения в SettingsView

### ProductModeCard — расширение

Picker Super заблокирован если `assetsState != .installed`. Под picker — явная причина:

| State | Текст | Иконка |
|-------|-------|--------|
| `.unknown` / `.checking` | "Проверяю готовность Super..." | `progress` |
| `.installed` | "Super готов к работе" | `checkmark.circle` |
| `.modelMissing` | "Модель не найдена. Скачайте GigaChat GGUF в ~/.govorun/models/" | `exclamationmark.triangle` |
| `.runtimeMissing` | "Бинарник llama-server отсутствует" | `xmark.circle` |
| `.error(msg)` | "Ошибка: {msg}" | `xmark.circle` |

Picker disabled когда state ∉ {`.installed`} и пользователь пытается выбрать Super. Переключение на Standard всегда доступно.

## Изменения в LLMRuntimeManager

### Убрать internal discovery

`resolveModelPath()` и `resolveRuntimeBinary()` удаляются из `LLMRuntimeManager`. Вместо этого `LLMRuntimeConfiguration` получает явные `runtimeBinaryPath` и `modelPath` от `AppState`, который берёт их из `SuperAssetsManager`.

### resolveStartMode упрощается

```swift
func resolveStartMode() throws -> StartMode {
    // Только проверяем что config содержит валидные пути
    guard !configuration.runtimeBinaryPath.isEmpty else {
        throw LLMRuntimeError.configurationMissing("runtimeBinaryPath не задан")
    }
    guard !configuration.modelPath.isEmpty else {
        throw LLMRuntimeError.configurationMissing("modelPath не задан")
    }
    // ...остальная логика endpoint detection
}
```

## Тесты

### SuperAssetsManagerTests
- `test_check_withBothAssets_returnsInstalled` — mock файловая система, оба файла есть
- `test_check_withoutModel_returnsModelMissing` — бинарник есть, модели нет
- `test_check_withoutBinary_returnsRuntimeMissing` — бинарника нет
- `test_check_withUnreadableModel_returnsError` — файл есть но нечитаем
- `test_resolvedPaths_populatedWhenInstalled` — runtimeBinaryURL и modelURL заполнены
- `test_resolvedPaths_nilWhenNotInstalled` — runtimeBinaryURL/modelURL = nil

### AppState/ColdStartUITests
- `test_superMode_coldStart_withInstalledAssets_startsRuntime`
- `test_superMode_coldStart_withMissingModel_disablesRuntime`
- `test_switchToSuper_withMissingAssets_staysOnStandard`
- `test_standardMode_ignoresAssetsState`

### PipelineEngineTests
- Существующие тесты не меняются — PipelineEngine не знает про ассеты

## Файлы

| Файл | Действие |
|------|----------|
| `Govorun/Services/SuperAssetsManager.swift` | NEW |
| `GovorunTests/SuperAssetsManagerTests.swift` | NEW |
| `Govorun/App/AppState.swift` | MODIFY — wiring assetsManager |
| `Govorun/Views/SettingsView.swift` | MODIFY — assetsState в ProductModeCard |
| `Govorun/Services/LLMRuntimeManager.swift` | MODIFY — убрать discovery, принимать resolved paths |
| `GovorunTests/ColdStartUITests.swift` | MODIFY — тесты assets + runtime |

## Не в scope

- Скачивание модели (следующий PR)
- Bundling llama-server в DMG (build script, отдельно)
- First-run setup wizard
- Автоматический retry при ошибке ассетов
