# Super Assets Readiness — Design Spec

## Проблема

Говорун Super существует как UI-переключатель, но пользователь не понимает: готов ли Super к работе, чего не хватает, и что делать. При отсутствии llama-server или GGUF модели Super молча падает через 20-секундный timeout.

## Цель этого PR

Readiness foundation + bundling: discovery ассетов, state machine, UI статусов, блокировка старта без ассетов, llama-server в app bundle. Скачивание модели — следующий PR.

## Ассеты Super

| Ассет | Источник | Путь | Размер | В этом PR |
|-------|----------|------|--------|-----------|
| llama-server binary | App bundle (`Resources/llama-server`) | `Bundle.main.resourcePath` | ~5 MB | Да (build script) |
| GigaChat GGUF model | Скачивается отдельно | `~/.govorun/models/{model-alias}.gguf` | ~6 GB | Нет (следующий PR) |

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
   - `Bundle.main.resourceURL/llama-server` (primary — release)
   - Fallback: PATH lookup — **только в `#if DEBUG`** (dev-режим). В release PATH fallback отключён, чтобы не маскировать сломанный bundle.
   - Не найден → `.runtimeMissing`

2. Ищем GGUF модель:
   - Точное имя из конфига: `~/.govorun/models/{SettingsStore.llmModel}.gguf` (default: `gigachat-gguf.gguf`)
   - Env override: `GOVORUN_LLM_MODEL_PATH` (полный путь к файлу)
   - Не найден → `.modelMissing`

3. Валидация:
   - Binary: `FileManager.isExecutableFile(atPath:)`
   - Model: `FileManager.isReadableFile(atPath:)` + размер > 100 MB (sanity check)
   - Невалиден → `.error("описание")`

4. Оба на месте → `.installed`, заполняем `runtimeBinaryURL` и `modelURL`

### External Endpoint Bypass

Если `SettingsStore.llmBaseURL` указывает не на managed local endpoint (не `localhost:8080`), ассеты не нужны — пользователь использует внешний LLM сервер. В этом случае:

```swift
func check() async -> SuperAssetsState {
    if configuration.isExternalEndpoint {
        // Внешний endpoint — ассеты не требуются
        runtimeBinaryURL = nil
        modelURL = nil
        return .installed
    }
    // ...обычная discovery логика
}
```

`LLMRuntimeManager` уже различает managed/external в `resolveStartMode()` и не запускает процесс для внешнего endpoint.

### Resolved Paths

`LLMRuntimeManager` больше не ищет файлы сам. `AppState` передаёт resolved paths из `SuperAssetsManager`:

```swift
// AppState
let assetsState = await assetsManager.check()
guard assetsState == .installed else {
    updateLLMRuntimeState(.disabled)
    return
}
// Для external endpoint paths будут nil — LLMRuntimeManager использует HTTP
if let binaryURL = assetsManager.runtimeBinaryURL,
   let modelURL = assetsManager.modelURL {
    let config = LocalLLMRuntimeConfiguration(
        runtimeBinaryPath: binaryURL.path,
        modelPath: modelURL.path,
        ...
    )
    try await llmRuntimeManager.updateConfiguration(config)
}
try await llmRuntimeManager.start()
```

## Source of Truth в AppState

```swift
// AppState
@Published private(set) var superAssetsState: SuperAssetsState = .unknown

private let assetsManager: SuperAssetsManaging

func refreshSuperAssetsReadiness() async {
    superAssetsState = .checking
    superAssetsState = await assetsManager.check()
}
```

Вызовы `refreshSuperAssetsReadiness()`:
- Cold start (`start()`)
- Переключение product mode в Settings
- Открытие Settings (чтобы подхватить ручное копирование модели)

## Изменения в AppState

### Cold Start

```
start()
├─ refreshSuperAssetsReadiness()
├─ if superAssetsState == .installed && productMode.usesLLM
│  → runtimeManager.start(resolvedPaths)
├─ if superAssetsState != .installed && productMode.usesLLM
│  → llmRuntimeState = .disabled, log
└─ Standard mode не зависит от ассетов
```

### Mode Switch

Переключение на Super контролируется через UI: picker Super disabled если `superAssetsState != .installed`. AppState не содержит special-case логику "stays on standard" — блокировка целиком в SettingsView.

## Изменения в SettingsView

### ProductModeCard — расширение

Picker Super segment disabled если `superAssetsState != .installed`. Под picker — явная причина:

| State | Текст | Иконка |
|-------|-------|--------|
| `.unknown` / `.checking` | "Проверяю готовность Super..." | `progress` |
| `.installed` | (показывает runtime status как сейчас) | `sparkles` |
| `.modelMissing` | "Модель не найдена. Скопируйте GGUF в ~/.govorun/models/" | `exclamationmark.triangle` |
| `.runtimeMissing` | "Компонент llama-server отсутствует в приложении" | `xmark.circle` |
| `.error(msg)` | "Ошибка: {msg}" | `xmark.circle` |

Переключение на Standard всегда доступно.

## Изменения в LLMRuntimeManager

### Убрать internal discovery

`resolveModelPath()` и `resolveRuntimeBinary()` удаляются. `LLMRuntimeConfiguration` получает явные пути от `AppState` (через `SuperAssetsManager`).

### resolveStartMode упрощается

```swift
func resolveStartMode() throws -> StartMode {
    guard isLocalManagedEndpoint else { return .externalEndpoint }
    guard !configuration.runtimeBinaryPath.isEmpty else {
        throw LLMRuntimeError.configurationMissing("runtimeBinaryPath не задан")
    }
    guard !configuration.modelPath.isEmpty else {
        throw LLMRuntimeError.configurationMissing("modelPath не задан")
    }
    // ...build launch request
}
```

## Bundling llama-server

В `scripts/build-unsigned-dmg.sh` добавить копирование бинарника в app bundle:

```bash
# Копируем llama-server в Resources
LLAMA_SERVER=$(which llama-server 2>/dev/null)
if [[ -n "$LLAMA_SERVER" ]]; then
    cp "$LLAMA_SERVER" "$APP_RESOURCES/llama-server"
    chmod +x "$APP_RESOURCES/llama-server"
    echo "[build] llama-server скопирован в bundle"
else
    echo "[build] ВНИМАНИЕ: llama-server не найден, Super mode будет недоступен"
fi
```

Не блокирует сборку — если llama-server не установлен, DMG собирается без него, Super показывает `runtimeMissing`.

## Тесты

### SuperAssetsManagerTests
- `test_check_withBothAssets_returnsInstalled`
- `test_check_withoutModel_returnsModelMissing`
- `test_check_withoutBinary_returnsRuntimeMissing`
- `test_check_withUnreadableModel_returnsError`
- `test_resolvedPaths_populatedWhenInstalled`
- `test_resolvedPaths_nilWhenNotInstalled`
- `test_externalEndpoint_bypassesAssetCheck`
- `test_modelDiscovery_usesExactFilename`

### AppState/ColdStartUITests
- `test_superMode_coldStart_withInstalledAssets_startsRuntime`
- `test_superMode_coldStart_withMissingModel_disablesRuntime`
- `test_standardMode_ignoresAssetsState`

### PipelineEngineTests
- Существующие тесты не меняются — PipelineEngine не знает про ассеты

## Файлы

| Файл | Действие |
|------|----------|
| `Govorun/Services/SuperAssetsManager.swift` | NEW |
| `GovorunTests/SuperAssetsManagerTests.swift` | NEW |
| `Govorun/App/AppState.swift` | MODIFY — superAssetsState, refreshSuperAssetsReadiness, wiring |
| `Govorun/Views/SettingsView.swift` | MODIFY — assetsState в ProductModeCard |
| `Govorun/Services/LLMRuntimeManager.swift` | MODIFY — убрать discovery, принимать resolved paths |
| `GovorunTests/ColdStartUITests.swift` | MODIFY — тесты assets + runtime |
| `scripts/build-unsigned-dmg.sh` | MODIFY — копировать llama-server в bundle |

## Не в scope

- Скачивание модели (следующий PR)
- First-run setup wizard
- Автоматический retry при ошибке ассетов
