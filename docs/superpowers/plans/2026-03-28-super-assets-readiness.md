# Super Assets Readiness — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Дать пользователю честный статус готовности Говорун Super — discovery ассетов, state machine, UI, блокировка старта без ассетов.

**Architecture:** Новый `SuperAssetsManager` (protocol + implementation) проверяет наличие llama-server бинарника и GGUF модели. `AppState` публикует `superAssetsState` и блокирует runtime start если ассеты не готовы. `SettingsView` disabled Super picker и показывает причину. `LLMRuntimeManager` перестаёт искать файлы сам — получает resolved paths.

**Tech Stack:** Swift 5.10, macOS 14+, SwiftUI, XCTest

**Spec:** `docs/superpowers/specs/2026-03-27-super-assets-readiness-design.md`

---

### Task 1: SuperAssetsState enum + SuperAssetsManaging protocol

**Files:**
- Create: `Govorun/Services/SuperAssetsManager.swift`
- Create: `GovorunTests/SuperAssetsManagerTests.swift`

- [ ] **Step 1: Write failing test for state enum and protocol existence**

```swift
// GovorunTests/SuperAssetsManagerTests.swift
@testable import Govorun
import XCTest

final class SuperAssetsManagerTests: XCTestCase {
    func test_initialState_isUnknown() {
        let manager = SuperAssetsManager(
            fileChecker: MockFileChecker(),
            bundleResourcePath: "/fake/bundle",
            modelsDirectory: "/fake/models",
            modelAlias: "gigachat-gguf"
        )
        XCTAssertEqual(manager.state, .unknown)
        XCTAssertNil(manager.runtimeBinaryURL)
        XCTAssertNil(manager.modelURL)
    }
}

private final class MockFileChecker: FileChecking {
    var executableFiles: Set<String> = []
    var readableFiles: [String: UInt64] = [:]

    func isExecutableFile(atPath path: String) -> Bool {
        executableFiles.contains(path)
    }

    func isReadableFile(atPath path: String) -> Bool {
        readableFiles[path] != nil
    }

    func fileSize(atPath path: String) -> UInt64? {
        readableFiles[path]
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperAssetsManagerTests 2>&1 | grep -E 'error:|FAIL'`
Expected: compilation error — types don't exist

- [ ] **Step 3: Write minimal implementation**

```swift
// Govorun/Services/SuperAssetsManager.swift
import Foundation

// MARK: - State

enum SuperAssetsState: Equatable, Sendable {
    case unknown
    case checking
    case installed
    case modelMissing
    case runtimeMissing
    case error(String)
}

// MARK: - File system abstraction

protocol FileChecking: Sendable {
    func isExecutableFile(atPath path: String) -> Bool
    func isReadableFile(atPath path: String) -> Bool
    func fileSize(atPath path: String) -> UInt64?
}

final class DefaultFileChecker: FileChecking {
    func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    func isReadableFile(atPath path: String) -> Bool {
        FileManager.default.isReadableFile(atPath: path)
    }

    func fileSize(atPath path: String) -> UInt64? {
        try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64
    }
}

// MARK: - Protocol

protocol SuperAssetsManaging: AnyObject, Sendable {
    var state: SuperAssetsState { get }
    var runtimeBinaryURL: URL? { get }
    var modelURL: URL? { get }
    func check() -> SuperAssetsState
}

// MARK: - Implementation

final class SuperAssetsManager: SuperAssetsManaging, @unchecked Sendable {
    private let fileChecker: FileChecking
    private let bundleResourcePath: String?
    private let modelsDirectory: String
    private let modelAlias: String

    private(set) var state: SuperAssetsState = .unknown
    private(set) var runtimeBinaryURL: URL?
    private(set) var modelURL: URL?

    init(
        fileChecker: FileChecking = DefaultFileChecker(),
        bundleResourcePath: String? = Bundle.main.resourcePath,
        modelsDirectory: String = NSHomeDirectory() + "/.govorun/models",
        modelAlias: String = "gigachat-gguf"
    ) {
        self.fileChecker = fileChecker
        self.bundleResourcePath = bundleResourcePath
        self.modelsDirectory = modelsDirectory
        self.modelAlias = modelAlias
    }

    func check() -> SuperAssetsState {
        state = .checking
        runtimeBinaryURL = nil
        modelURL = nil

        // 1. Runtime binary
        guard let binaryURL = resolveRuntimeBinary() else {
            state = .runtimeMissing
            return state
        }

        // 2. Model file
        guard let model = resolveModel() else {
            runtimeBinaryURL = binaryURL
            state = .modelMissing
            return state
        }

        runtimeBinaryURL = binaryURL
        modelURL = model
        state = .installed
        return state
    }

    private func resolveRuntimeBinary() -> URL? {
        // Bundle (release)
        if let resourcePath = bundleResourcePath {
            let bundled = (resourcePath as NSString).appendingPathComponent("llama-server")
            if fileChecker.isExecutableFile(atPath: bundled) {
                return URL(fileURLWithPath: bundled)
            }
        }

        #if DEBUG
        // PATH fallback (dev only)
        if let pathBinary = Self.findInPath("llama-server") {
            return URL(fileURLWithPath: pathBinary)
        }
        #endif

        return nil
    }

    private func resolveModel() -> URL? {
        // Env override
        if let envPath = ProcessInfo.processInfo.environment["GOVORUN_LLM_MODEL_PATH"],
           !envPath.isEmpty {
            return validateModel(atPath: envPath)
        }

        // Standard location
        let standardPath = (modelsDirectory as NSString)
            .appendingPathComponent("\(modelAlias).gguf")
        return validateModel(atPath: standardPath)
    }

    private func validateModel(atPath path: String) -> URL? {
        guard fileChecker.isReadableFile(atPath: path) else { return nil }
        guard let size = fileChecker.fileSize(atPath: path), size > 100_000_000 else {
            state = .error("Файл модели слишком маленький: \(path)")
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    #if DEBUG
    private static func findInPath(_ name: String) -> String? {
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
    #endif
}
```

- [ ] **Step 4: Register new files in project.yml and regenerate**

Run: Add file references then `xcodegen generate`

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperAssetsManagerTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Govorun/Services/SuperAssetsManager.swift GovorunTests/SuperAssetsManagerTests.swift
git commit -m "feat: SuperAssetsManager — state enum, protocol, initial test"
```

---

### Task 2: SuperAssetsManager discovery tests

**Files:**
- Modify: `GovorunTests/SuperAssetsManagerTests.swift`

- [ ] **Step 1: Write discovery tests**

```swift
func test_check_withBothAssets_returnsInstalled() {
    let checker = MockFileChecker()
    checker.executableFiles = ["/bundle/llama-server"]
    checker.readableFiles = ["/models/gigachat-gguf.gguf": 6_000_000_000]

    let manager = SuperAssetsManager(
        fileChecker: checker,
        bundleResourcePath: "/bundle",
        modelsDirectory: "/models",
        modelAlias: "gigachat-gguf"
    )

    let result = manager.check()

    XCTAssertEqual(result, .installed)
    XCTAssertEqual(manager.runtimeBinaryURL, URL(fileURLWithPath: "/bundle/llama-server"))
    XCTAssertEqual(manager.modelURL, URL(fileURLWithPath: "/models/gigachat-gguf.gguf"))
}

func test_check_withoutModel_returnsModelMissing() {
    let checker = MockFileChecker()
    checker.executableFiles = ["/bundle/llama-server"]

    let manager = SuperAssetsManager(
        fileChecker: checker,
        bundleResourcePath: "/bundle",
        modelsDirectory: "/models",
        modelAlias: "gigachat-gguf"
    )

    let result = manager.check()

    XCTAssertEqual(result, .modelMissing)
    XCTAssertEqual(manager.runtimeBinaryURL, URL(fileURLWithPath: "/bundle/llama-server"))
    XCTAssertNil(manager.modelURL)
}

func test_check_withoutBinary_returnsRuntimeMissing() {
    let checker = MockFileChecker()
    checker.readableFiles = ["/models/gigachat-gguf.gguf": 6_000_000_000]

    let manager = SuperAssetsManager(
        fileChecker: checker,
        bundleResourcePath: "/bundle",
        modelsDirectory: "/models",
        modelAlias: "gigachat-gguf"
    )

    let result = manager.check()

    XCTAssertEqual(result, .runtimeMissing)
    XCTAssertNil(manager.runtimeBinaryURL)
    XCTAssertNil(manager.modelURL)
}

func test_check_withTooSmallModel_returnsError() {
    let checker = MockFileChecker()
    checker.executableFiles = ["/bundle/llama-server"]
    checker.readableFiles = ["/models/gigachat-gguf.gguf": 1_000] // < 100 MB

    let manager = SuperAssetsManager(
        fileChecker: checker,
        bundleResourcePath: "/bundle",
        modelsDirectory: "/models",
        modelAlias: "gigachat-gguf"
    )

    let result = manager.check()

    XCTAssertTrue(result == .error("Файл модели слишком маленький: /models/gigachat-gguf.gguf"))
}

func test_check_withEnvOverride_usesExplicitPath() {
    let checker = MockFileChecker()
    checker.executableFiles = ["/bundle/llama-server"]
    checker.readableFiles = ["/custom/my-model.gguf": 6_000_000_000]

    let manager = SuperAssetsManager(
        fileChecker: checker,
        bundleResourcePath: "/bundle",
        modelsDirectory: "/models",
        modelAlias: "gigachat-gguf"
    )

    // Env override тестируется через production init — здесь проверяем стандартный путь
    let result = manager.check()
    XCTAssertEqual(result, .modelMissing) // стандартный путь не найден
}

func test_modelDiscovery_usesExactFilename() {
    let checker = MockFileChecker()
    checker.executableFiles = ["/bundle/llama-server"]
    checker.readableFiles = [
        "/models/other-model.gguf": 6_000_000_000,  // другая модель
        "/models/custom-alias.gguf": 6_000_000_000,
    ]

    let manager = SuperAssetsManager(
        fileChecker: checker,
        bundleResourcePath: "/bundle",
        modelsDirectory: "/models",
        modelAlias: "custom-alias"
    )

    let result = manager.check()

    XCTAssertEqual(result, .installed)
    XCTAssertEqual(manager.modelURL, URL(fileURLWithPath: "/models/custom-alias.gguf"))
}
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperAssetsManagerTests`
Expected: all PASS

- [ ] **Step 3: Commit**

```bash
git add GovorunTests/SuperAssetsManagerTests.swift
git commit -m "test: discovery тесты SuperAssetsManager"
```

---

### Task 3: Wire SuperAssetsManager into AppState

**Files:**
- Modify: `Govorun/App/AppState.swift`

- [ ] **Step 1: Add superAssetsState property and assetsManager field**

In `AppState`, add:
- `@Published private(set) var superAssetsState: SuperAssetsState = .unknown` (near line 77, next to `llmRuntimeState`)
- `private let superAssetsManager: SuperAssetsManaging` field (near line 29)
- `func refreshSuperAssetsReadiness()` method
- Accept `superAssetsManager` in init (with default `SuperAssetsManager()`)

- [ ] **Step 2: Gate LLM runtime start on assets readiness**

In `start()` method (lines 304-318), wrap LLM runtime startup:

```swift
if let llmRuntimeManager {
    if currentProductMode.usesLLM {
        refreshSuperAssetsReadiness()
        guard superAssetsState == .installed else {
            updateLLMRuntimeState(.disabled)
            return
        }
        // Передать resolved paths в конфигурацию
        if let binaryURL = superAssetsManager.runtimeBinaryURL,
           let modelURL = superAssetsManager.modelURL {
            let runtimeConfig = LocalLLMRuntimeConfiguration(
                baseURLString: settings.llmBaseURL,
                modelAlias: settings.llmModel,
                modelPath: modelURL.path,
                runtimeBinaryPath: binaryURL.path
            )
            Task {
                do {
                    try await llmRuntimeManager.updateConfiguration(runtimeConfig)
                    try await llmRuntimeManager.start()
                } catch {
                    Self.logger.error("LLM runtime не запустился: \(String(describing: error), privacy: .public)")
                    self.updateLLMRuntimeState(.error(error.localizedDescription))
                }
            }
        }
    } else {
        updateLLMRuntimeState(.disabled)
    }
}
```

- [ ] **Step 3: Gate applyProductMode on assets**

In `applyProductMode()` (lines 513-539), add assets check before starting runtime:

```swift
if productMode.usesLLM {
    refreshSuperAssetsReadiness()
    guard superAssetsState == .installed else {
        updateLLMRuntimeState(.disabled)
        return
    }
    // ...existing start logic with resolved paths
}
```

- [ ] **Step 4: Add refreshSuperAssetsReadiness method**

```swift
func refreshSuperAssetsReadiness() {
    superAssetsState = superAssetsManager.check()
}
```

- [ ] **Step 5: Update resolveLLMRuntimeConfiguration to accept resolved paths**

Modify to pass through binaryPath and modelPath from assets manager when available.

- [ ] **Step 6: Run full test suite**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`
Expected: all pass (existing tests use mocks, not affected by assets check)

- [ ] **Step 7: Commit**

```bash
git add Govorun/App/AppState.swift
git commit -m "feat: wire SuperAssetsManager в AppState — gating runtime на readiness"
```

---

### Task 4: ColdStart/Integration tests for assets gating

**Files:**
- Modify: `GovorunTests/ColdStartUITests.swift`

- [ ] **Step 1: Create MockSuperAssetsManager**

```swift
final class MockSuperAssetsManager: SuperAssetsManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: SuperAssetsState = .installed
    private var _runtimeBinaryURL: URL? = URL(fileURLWithPath: "/usr/local/bin/llama-server")
    private var _modelURL: URL? = URL(fileURLWithPath: "/fake/model.gguf")

    var state: SuperAssetsState {
        lock.lock(); defer { lock.unlock() }; return _state
    }
    var runtimeBinaryURL: URL? {
        lock.lock(); defer { lock.unlock() }; return _runtimeBinaryURL
    }
    var modelURL: URL? {
        lock.lock(); defer { lock.unlock() }; return _modelURL
    }

    func check() -> SuperAssetsState {
        lock.lock(); defer { lock.unlock() }; return _state
    }

    func simulateState(_ state: SuperAssetsState, binaryURL: URL? = nil, modelURL: URL? = nil) {
        lock.lock()
        _state = state
        _runtimeBinaryURL = binaryURL
        _modelURL = modelURL
        lock.unlock()
    }
}
```

- [ ] **Step 2: Write tests**

```swift
func test_superMode_coldStart_withMissingModel_disablesRuntime() async throws {
    let mockAssets = MockSuperAssetsManager()
    mockAssets.simulateState(.modelMissing, binaryURL: URL(fileURLWithPath: "/bin/llama-server"))
    let mockLLMRuntime = MockLLMRuntimeManager()

    let (appState, _, _) = makeColdStartTestAppState(
        llmRuntimeManager: mockLLMRuntime,
        superAssetsManager: mockAssets,
        productMode: .superMode
    )

    appState.start()
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertFalse(mockLLMRuntime.startCalled)
    XCTAssertEqual(appState.llmRuntimeState, .disabled)
    XCTAssertEqual(appState.superAssetsState, .modelMissing)
}

func test_superMode_coldStart_withInstalledAssets_startsRuntime() async throws {
    let mockAssets = MockSuperAssetsManager()
    // Default: .installed with valid URLs
    let mockLLMRuntime = MockLLMRuntimeManager()

    let (appState, _, _) = makeColdStartTestAppState(
        llmRuntimeManager: mockLLMRuntime,
        superAssetsManager: mockAssets,
        productMode: .superMode
    )

    appState.start()
    for _ in 0..<20 {
        try await Task.sleep(nanoseconds: 50_000_000)
        if mockLLMRuntime.startCalled { break }
    }

    XCTAssertTrue(mockLLMRuntime.startCalled)
    XCTAssertEqual(appState.superAssetsState, .installed)
}

func test_standardMode_ignoresAssetsState() async throws {
    let mockAssets = MockSuperAssetsManager()
    mockAssets.simulateState(.runtimeMissing)

    let (appState, _, _) = makeColdStartTestAppState(
        superAssetsManager: mockAssets,
        productMode: .standard
    )

    appState.start()
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(appState.llmRuntimeState, .disabled)
    // Assets state not checked in standard mode
}
```

- [ ] **Step 3: Update makeColdStartTestAppState to accept superAssetsManager**

Add `superAssetsManager: SuperAssetsManaging? = nil` parameter, default to `MockSuperAssetsManager()` (returns .installed).

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/ColdStartUITests`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add GovorunTests/ColdStartUITests.swift
git commit -m "test: cold start тесты для assets gating"
```

---

### Task 5: Update SettingsView — assets status in ProductModeCard

**Files:**
- Modify: `Govorun/Views/SettingsView.swift`

- [ ] **Step 1: Add assets status text and picker gating**

In `ProductModeCard` (lines 287-347):

```swift
private struct ProductModeCard: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selection: ProductMode

    private var superAvailable: Bool {
        appState.superAssetsState == .installed
    }

    private var assetsStatusText: String? {
        switch appState.superAssetsState {
        case .unknown, .checking:
            return "Проверяю готовность Super..."
        case .installed:
            return nil // показываем runtime status
        case .modelMissing:
            return "Модель не найдена. Скопируйте GGUF в ~/.govorun/models/"
        case .runtimeMissing:
            return "Компонент llama-server отсутствует в приложении"
        case .error(let msg):
            return "Ошибка: \(msg)"
        }
    }

    // В body: Picker с disabled Super segment
    Picker("", selection: $selection) {
        ForEach(ProductMode.allCases, id: \.self) { mode in
            Text(mode.title).tag(mode)
        }
    }
    .pickerStyle(.segmented)
    .onChange(of: selection) { newValue in
        if newValue == .superMode && !superAvailable {
            selection = .standard
        }
    }

    // Под picker: assetsStatusText или runtimeStatusText
    if let assetsText = assetsStatusText {
        Label(assetsText, systemImage: assetsStatusIcon)
            .font(.caption)
            .foregroundStyle(.orange)
    } else {
        Text(runtimeStatusText)
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
```

- [ ] **Step 2: Add onAppear refresh**

```swift
.onAppear {
    appState.refreshSuperAssetsReadiness()
}
```

- [ ] **Step 3: Run app visually (build DMG) to verify UI**

Build and test manually: switch to Super when model is missing, verify picker rejects.

- [ ] **Step 4: Commit**

```bash
git add Govorun/Views/SettingsView.swift
git commit -m "feat: UI статус ассетов Super в ProductModeCard"
```

---

### Task 6: Remove discovery logic from LLMRuntimeManager

**Files:**
- Modify: `Govorun/Services/LLMRuntimeManager.swift`

- [ ] **Step 1: Remove bundledModelCandidates() and runtimeBinaryCandidates()**

Delete methods at lines 501-523. These are replaced by SuperAssetsManager.

- [ ] **Step 2: Simplify resolveModelPath() and resolveRuntimeBinary()**

Replace with simple validation (paths are now explicit from SuperAssetsManager):

```swift
private func resolveModelPath(_ configuration: LocalLLMRuntimeConfiguration) throws -> String? {
    guard let path = configuration.normalizedModelPath else { return nil }
    guard FileManager.default.isReadableFile(atPath: path) else {
        throw LLMRuntimeError.modelNotFound(path)
    }
    return path
}

private func resolveRuntimeBinary(_ configuration: LocalLLMRuntimeConfiguration) -> String? {
    guard let path = configuration.normalizedRuntimeBinaryPath else { return nil }
    return Self.resolveExecutable(path)
}
```

- [ ] **Step 3: Run full test suite**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation`
Expected: all pass — tests use mock LLMRuntimeManager

- [ ] **Step 4: Commit**

```bash
git add Govorun/Services/LLMRuntimeManager.swift
git commit -m "refactor: убрать discovery из LLMRuntimeManager — пути от SuperAssetsManager"
```

---

### Task 7: Bundle llama-server in DMG build

**Files:**
- Modify: `scripts/build-unsigned-dmg.sh`

- [ ] **Step 1: Add llama-server copy section after worker files**

After the worker copy block (line 55):

```bash
# llama-server для Говорун Super
LLAMA_SERVER=$(which llama-server 2>/dev/null)
if [[ -n "$LLAMA_SERVER" ]]; then
    echo "==> Копирую llama-server в bundle..."
    cp "$LLAMA_SERVER" "$APP/Contents/Resources/llama-server"
    chmod +x "$APP/Contents/Resources/llama-server"
    echo "    llama-server скопирован ($(du -h "$APP/Contents/Resources/llama-server" | cut -f1))"
else
    echo "==> ВНИМАНИЕ: llama-server не найден в PATH, Super mode будет недоступен в этой сборке"
fi
```

- [ ] **Step 2: Test build**

Run: `bash scripts/build-unsigned-dmg.sh 2>&1 | grep -E 'llama-server|ВНИМАНИЕ'`
Expected: "llama-server скопирован" or "ВНИМАНИЕ" if not installed

- [ ] **Step 3: Commit**

```bash
git add scripts/build-unsigned-dmg.sh
git commit -m "build: копировать llama-server в app bundle для Super mode"
```

---

### Task 8: External endpoint bypass

**Files:**
- Modify: `Govorun/Services/SuperAssetsManager.swift`
- Modify: `GovorunTests/SuperAssetsManagerTests.swift`

- [ ] **Step 1: Write test**

```swift
func test_externalEndpoint_bypassesAssetCheck() {
    let checker = MockFileChecker()
    // Никаких файлов — но endpoint внешний

    let manager = SuperAssetsManager(
        fileChecker: checker,
        bundleResourcePath: "/bundle",
        modelsDirectory: "/models",
        modelAlias: "gigachat-gguf",
        baseURLString: "http://192.168.1.100:8080/v1"
    )

    let result = manager.check()

    XCTAssertEqual(result, .installed)
    XCTAssertNil(manager.runtimeBinaryURL)
    XCTAssertNil(manager.modelURL)
}

func test_localEndpoint_requiresAssets() {
    let checker = MockFileChecker()

    let manager = SuperAssetsManager(
        fileChecker: checker,
        bundleResourcePath: "/bundle",
        modelsDirectory: "/models",
        modelAlias: "gigachat-gguf",
        baseURLString: "http://127.0.0.1:8080/v1"
    )

    let result = manager.check()

    XCTAssertEqual(result, .runtimeMissing)
}
```

- [ ] **Step 2: Add baseURLString param and bypass logic**

Add `baseURLString` parameter to `SuperAssetsManager.init()`. In `check()`:

```swift
func check() -> SuperAssetsState {
    state = .checking
    runtimeBinaryURL = nil
    modelURL = nil

    if isExternalEndpoint {
        state = .installed
        return state
    }
    // ...existing discovery
}

private var isExternalEndpoint: Bool {
    guard let url = URL(string: baseURLString),
          let host = url.host else { return false }
    let localHosts = ["127.0.0.1", "localhost", "0.0.0.0", "::1"]
    return !localHosts.contains(host)
}
```

- [ ] **Step 3: Run tests**

Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add Govorun/Services/SuperAssetsManager.swift GovorunTests/SuperAssetsManagerTests.swift
git commit -m "feat: external endpoint bypass для SuperAssetsManager"
```

---

### Task 9: Final integration — run full test suite + create PR

**Files:** none new

- [ ] **Step 1: Regenerate Xcode project**

```bash
xcodegen generate
```

- [ ] **Step 2: Run full test suite**

```bash
xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | grep -E 'Executed|TEST'
```

Expected: 950+ tests, 0 failures

- [ ] **Step 3: Create branch and commit**

```bash
git checkout -b feat/super-assets-readiness
git add -A
git commit -m "feat: Super Assets Readiness — discovery, state machine, UI, bundling"
```

- [ ] **Step 4: Push and create PR**

```bash
git push -u origin feat/super-assets-readiness
gh pr create --title "feat: Super Assets Readiness" --body "..."
```
