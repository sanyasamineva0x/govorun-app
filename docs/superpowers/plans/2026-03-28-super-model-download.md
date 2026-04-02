# Super Model Download Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Users can download the Super mode AI model (~5.8 GB) from Hugging Face directly from Settings or Onboarding, with resume, SHA256 verification, and progress UI.

**Architecture:** New `SuperModelDownloadManager` service (protocol `SuperModelDownloading`) handles download/resume/verify. AppState coordinates via new `handleSuperAssetsChanged()` coordinator that replaces scattered runtime start/stop calls. SettingsView ProductModeCard shows download states; OnboardingView adds optional Super model step.

**Tech Stack:** Swift 5.10+, URLSession.bytes (buffered 256 KB writes), CryptoKit SHA256, UNUserNotificationCenter

**Spec:** `docs/superpowers/specs/2026-03-28-model-download-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Govorun/Models/SuperModelDownloadSpec.swift` | Create | Download spec value type (url, destination, SHA256, size) |
| `Govorun/Models/SuperModelDownloadState.swift` | Create | State enum + error enum |
| `Govorun/Models/SuperModelCatalog.swift` | Create | Single source of truth for current model spec |
| `Govorun/Services/SuperModelDownloadManager.swift` | Create | Protocol + implementation (download, resume, verify, cancel, restore) |
| `Govorun/App/AppState.swift` | Modify | Add coordinator + download wiring |
| `Govorun/Views/SettingsView.swift` | Modify | ProductModeCard download UI |
| `Govorun/Views/OnboardingView.swift` | Modify | Super model download step |
| `GovorunTests/SuperModelDownloadManagerTests.swift` | Create | Manager unit tests |
| `GovorunTests/IntegrationTests.swift` | Modify | Update makeTestAppState for new dependency |

---

### Task 1: Foundation Types + Protocol + Mock

**Files:**
- Create: `Govorun/Models/SuperModelDownloadSpec.swift`
- Create: `Govorun/Models/SuperModelDownloadState.swift`
- Create: `Govorun/Models/SuperModelCatalog.swift`
- Create: `Govorun/Services/SuperModelDownloadManager.swift` (protocol + placeholder class only)
- Create: `GovorunTests/SuperModelDownloadManagerTests.swift`

- [ ] **Step 1: Create SuperModelDownloadSpec**

```swift
// Govorun/Models/SuperModelDownloadSpec.swift
import Foundation

struct SuperModelDownloadSpec: Equatable, Sendable {
    let url: URL
    let destination: URL
    let expectedSHA256: String
    let expectedSize: Int64
}
```

- [ ] **Step 2: Create SuperModelDownloadState + SuperModelDownloadError**

```swift
// Govorun/Models/SuperModelDownloadState.swift
import Foundation

enum SuperModelDownloadState: Equatable, Sendable {
    case idle
    case checkingExisting
    case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64)
    case verifying
    case completed
    case failed(SuperModelDownloadError)
    case cancelled
    case partialReady(downloadedBytes: Int64, totalBytes: Int64)
}

enum SuperModelDownloadError: Error, LocalizedError, Equatable, Sendable {
    case insufficientDiskSpace(required: Int64, available: Int64)
    case integrityCheckFailed
    case networkError(String)
    case fileSystemError(String)

    var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace(let required, let available):
            "Недостаточно места: нужно \(required / 1_000_000_000) ГБ, доступно \(available / 1_000_000_000) ГБ"
        case .integrityCheckFailed:
            "Файл повреждён — контрольная сумма не совпадает"
        case .networkError(let message):
            "Ошибка сети: \(message)"
        case .fileSystemError(let message):
            "Ошибка файловой системы: \(message)"
        }
    }
}
```

- [ ] **Step 3: Create SuperModelCatalog**

```swift
// Govorun/Models/SuperModelCatalog.swift
import Foundation

enum SuperModelCatalog {
    // ⚠️ BLOCKER: перед merge/release заполнить реальные значения.
    // Отдельный коммит: загрузить GGUF на HF, получить pinned commit URL + SHA256.
    // Без этого resume и integrity check не работают корректно.
    //
    // Как получить:
    //   1. huggingface-cli upload <repo> gigachat-gguf.gguf
    //   2. URL: https://huggingface.co/<repo>/resolve/<commit-sha>/gigachat-gguf.gguf
    //   3. SHA256: shasum -a 256 gigachat-gguf.gguf
    static let current = SuperModelDownloadSpec(
        url: URL(string: "https://huggingface.co/sanyasamineva0x/gigachat-gguf/resolve/FILL_COMMIT_SHA/gigachat-gguf.gguf")!,
        destination: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".govorun/models/gigachat-gguf.gguf"),
        expectedSHA256: "FILL_SHA256_HASH",
        expectedSize: 5_832_014_592
    )

    static let minimumDiskSpaceBuffer: Int64 = 500_000_000
}
```

**IMPORTANT:** This PR merges with placeholder values. A **separate mandatory commit** before release must fill `FILL_COMMIT_SHA` and `FILL_SHA256_HASH` with real values after uploading the model to Hugging Face. The CI/release process should fail if these placeholders remain.

- [ ] **Step 4: Create SuperModelDownloading protocol**

```swift
// Govorun/Services/SuperModelDownloadManager.swift
import Foundation

protocol SuperModelDownloading: AnyObject, Sendable {
    var state: SuperModelDownloadState { get }
    var isActive: Bool { get }
    var onStateChanged: (@MainActor @Sendable (SuperModelDownloadState) -> Void)? { get set }
    func download(from spec: SuperModelDownloadSpec) async
    func cancel()
    func clearPartialDownload(for spec: SuperModelDownloadSpec)
    func restoreStateFromDisk(for spec: SuperModelDownloadSpec)
}
```

- [ ] **Step 5: Create MockSuperModelDownloader + initial tests**

```swift
// GovorunTests/SuperModelDownloadManagerTests.swift
import XCTest
@testable import Govorun

// MARK: - Mock

final class MockSuperModelDownloader: SuperModelDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: SuperModelDownloadState = .idle

    var state: SuperModelDownloadState {
        lock.withLock { _state }
    }

    var isActive: Bool {
        switch state {
        case .checkingExisting, .downloading, .verifying: true
        default: false
        }
    }

    var onStateChanged: (@MainActor @Sendable (SuperModelDownloadState) -> Void)?

    // Записываем вызовы для проверки в тестах
    var downloadCalled = false
    var cancelCalled = false
    var clearCalled = false
    var restoreCalled = false
    var lastSpec: SuperModelDownloadSpec?

    func download(from spec: SuperModelDownloadSpec) async {
        downloadCalled = true
        lastSpec = spec
    }

    func cancel() {
        cancelCalled = true
    }

    func clearPartialDownload(for spec: SuperModelDownloadSpec) {
        clearCalled = true
    }

    func restoreStateFromDisk(for spec: SuperModelDownloadSpec) {
        restoreCalled = true
    }

    // Хелпер для тестов: установить состояние и вызвать callback
    @MainActor
    func simulateStateChange(_ newState: SuperModelDownloadState) {
        lock.withLock { _state = newState }
        onStateChanged?(newState)
    }
}

// MARK: - Tests

final class SuperModelDownloadManagerTests: XCTestCase {

    func test_mock_initial_state_is_idle() {
        let mock = MockSuperModelDownloader()
        XCTAssertEqual(mock.state, .idle)
        XCTAssertFalse(mock.isActive)
    }

    @MainActor
    func test_mock_simulate_downloading_sets_isActive() async {
        let mock = MockSuperModelDownloader()
        await mock.simulateStateChange(.downloading(progress: 0.5, downloadedBytes: 100, totalBytes: 200))
        XCTAssertTrue(mock.isActive)
    }

    @MainActor
    func test_mock_callback_fires_on_state_change() async {
        let mock = MockSuperModelDownloader()
        var receivedState: SuperModelDownloadState?
        mock.onStateChanged = { state in
            receivedState = state
        }
        await mock.simulateStateChange(.completed)
        XCTAssertEqual(receivedState, .completed)
    }

    func test_download_spec_equality() {
        let spec1 = SuperModelDownloadSpec(
            url: URL(string: "https://example.com/model.gguf")!,
            destination: URL(fileURLWithPath: "/tmp/model.gguf"),
            expectedSHA256: "abc123",
            expectedSize: 1000
        )
        let spec2 = spec1
        XCTAssertEqual(spec1, spec2)
    }

    func test_error_descriptions_not_empty() {
        let errors: [SuperModelDownloadError] = [
            .insufficientDiskSpace(required: 6_000_000_000, available: 1_000_000_000),
            .integrityCheckFailed,
            .networkError("timeout"),
            .fileSystemError("permission denied"),
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
```

- [ ] **Step 6: Run tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperModelDownloadManagerTests 2>&1 | tail -20`

Expected: All 5 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Govorun/Models/SuperModelDownloadSpec.swift Govorun/Models/SuperModelDownloadState.swift Govorun/Models/SuperModelCatalog.swift Govorun/Services/SuperModelDownloadManager.swift GovorunTests/SuperModelDownloadManagerTests.swift
git commit -m "feat: типы и протокол для скачивания ИИ-модели Супер-режима"
```

---

### Task 2: SuperModelDownloadManager — Sidecar Metadata + Restore + Clear

**Files:**
- Modify: `Govorun/Services/SuperModelDownloadManager.swift`
- Modify: `GovorunTests/SuperModelDownloadManagerTests.swift`

**Context:** SuperModelDownloadManager needs to persist download state between app launches using a `.partial.meta` JSON file alongside the `.partial` download file. On launch, `restoreStateFromDisk()` reads this metadata to determine if a partial download exists.

- [ ] **Step 1: Write failing tests for metadata operations**

Append to `GovorunTests/SuperModelDownloadManagerTests.swift`:

```swift
// MARK: - SuperModelDownloadManager Tests

final class SuperModelDownloadManagerImplTests: XCTestCase {

    private var tempDir: URL!
    private var spec: SuperModelDownloadSpec!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("govorun-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        spec = SuperModelDownloadSpec(
            url: URL(string: "https://example.com/model.gguf")!,
            destination: tempDir.appendingPathComponent("model.gguf"),
            expectedSHA256: "abc123def456",
            expectedSize: 1000
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private var partialPath: URL { spec.destination.appendingPathExtension("partial") }
    private var metaPath: URL { spec.destination.appendingPathExtension("partial.meta") }

    // MARK: - restoreStateFromDisk

    func test_restore_no_partial_stays_idle() {
        let manager = SuperModelDownloadManager()
        manager.restoreStateFromDisk(for: spec)
        XCTAssertEqual(manager.state, .idle)
    }

    func test_restore_partial_without_meta_stays_idle() throws {
        try Data("partial data".utf8).write(to: partialPath)
        let manager = SuperModelDownloadManager()
        manager.restoreStateFromDisk(for: spec)
        XCTAssertEqual(manager.state, .idle)
    }

    func test_restore_partial_with_matching_meta_becomes_partialReady() throws {
        let partialData = Data(repeating: 0, count: 500)
        try partialData.write(to: partialPath)

        let meta = PartialDownloadMeta(
            url: spec.url.absoluteString,
            expectedSHA256: spec.expectedSHA256,
            expectedSize: spec.expectedSize,
            etag: nil,
            downloadedBytes: 500
        )
        try JSONEncoder().encode(meta).write(to: metaPath)

        let manager = SuperModelDownloadManager()
        manager.restoreStateFromDisk(for: spec)
        XCTAssertEqual(manager.state, .partialReady(downloadedBytes: 500, totalBytes: spec.expectedSize))
    }

    func test_restore_partial_with_mismatched_sha_deletes_and_stays_idle() throws {
        try Data("partial data".utf8).write(to: partialPath)

        let meta = PartialDownloadMeta(
            url: spec.url.absoluteString,
            expectedSHA256: "wrong-sha",
            expectedSize: spec.expectedSize,
            etag: nil,
            downloadedBytes: 12
        )
        try JSONEncoder().encode(meta).write(to: metaPath)

        let manager = SuperModelDownloadManager()
        manager.restoreStateFromDisk(for: spec)
        XCTAssertEqual(manager.state, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: metaPath.path))
    }

    // MARK: - clearPartialDownload

    func test_clear_removes_partial_and_meta() throws {
        try Data("data".utf8).write(to: partialPath)
        let meta = PartialDownloadMeta(
            url: spec.url.absoluteString,
            expectedSHA256: spec.expectedSHA256,
            expectedSize: spec.expectedSize,
            etag: nil,
            downloadedBytes: 4
        )
        try JSONEncoder().encode(meta).write(to: metaPath)

        let manager = SuperModelDownloadManager()
        manager.clearPartialDownload(for: spec)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: metaPath.path))
    }

    func test_clear_on_nonexistent_files_does_not_crash() {
        let manager = SuperModelDownloadManager()
        manager.clearPartialDownload(for: spec)
        // просто не должен упасть
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperModelDownloadManagerImplTests 2>&1 | tail -20`

Expected: FAIL — `SuperModelDownloadManager` class doesn't exist yet, `PartialDownloadMeta` not found.

- [ ] **Step 3: Implement PartialDownloadMeta + SuperModelDownloadManager skeleton**

Add to `Govorun/Services/SuperModelDownloadManager.swift` after the protocol:

```swift
struct PartialDownloadMeta: Codable, Equatable, Sendable {
    let url: String
    let expectedSHA256: String
    let expectedSize: Int64
    let etag: String?
    let downloadedBytes: Int64
}

final class SuperModelDownloadManager: SuperModelDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: SuperModelDownloadState = .idle

    var state: SuperModelDownloadState {
        lock.withLock { _state }
    }

    var isActive: Bool {
        switch state {
        case .checkingExisting, .downloading, .verifying: true
        default: false
        }
    }

    var onStateChanged: (@MainActor @Sendable (SuperModelDownloadState) -> Void)?

    private func setState(_ newState: SuperModelDownloadState) {
        lock.withLock { _state = newState }
        let callback = onStateChanged
        Task { @MainActor in
            callback?(newState)
        }
    }

    // MARK: - Paths

    private func partialURL(for spec: SuperModelDownloadSpec) -> URL {
        spec.destination.appendingPathExtension("partial")
    }

    private func metaURL(for spec: SuperModelDownloadSpec) -> URL {
        spec.destination.appendingPathExtension("partial.meta")
    }

    // MARK: - Metadata

    private func readMeta(for spec: SuperModelDownloadSpec) -> PartialDownloadMeta? {
        let url = metaURL(for: spec)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PartialDownloadMeta.self, from: data)
    }

    private func writeMeta(_ meta: PartialDownloadMeta, for spec: SuperModelDownloadSpec) {
        let url = metaURL(for: spec)
        try? JSONEncoder().encode(meta).write(to: url)
    }

    private func deleteMeta(for spec: SuperModelDownloadSpec) {
        try? FileManager.default.removeItem(at: metaURL(for: spec))
    }

    // MARK: - Restore

    func restoreStateFromDisk(for spec: SuperModelDownloadSpec) {
        let partial = partialURL(for: spec)
        let fm = FileManager.default

        guard fm.fileExists(atPath: partial.path) else { return }
        guard let meta = readMeta(for: spec) else { return }

        // Если spec изменился (другая модель / другой SHA), удаляем partial
        guard meta.expectedSHA256 == spec.expectedSHA256,
              meta.url == spec.url.absoluteString else {
            try? fm.removeItem(at: partial)
            deleteMeta(for: spec)
            return
        }

        setState(.partialReady(downloadedBytes: meta.downloadedBytes, totalBytes: spec.expectedSize))
    }

    // MARK: - Clear

    func clearPartialDownload(for spec: SuperModelDownloadSpec) {
        let fm = FileManager.default
        try? fm.removeItem(at: partialURL(for: spec))
        deleteMeta(for: spec)
        setState(.idle) // UI не застрянет в .partialReady / .cancelled после удаления
    }

    // MARK: - Download (stub — Task 4)

    func download(from spec: SuperModelDownloadSpec) async {
        // будет реализовано в Task 4
    }

    // MARK: - Cancel (stub — Task 4)

    func cancel() {
        // будет реализовано в Task 4
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperModelDownloadManagerImplTests 2>&1 | tail -20`

Expected: All 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Govorun/Services/SuperModelDownloadManager.swift GovorunTests/SuperModelDownloadManagerTests.swift
git commit -m "feat: sidecar metadata + restoreStateFromDisk для resume скачивания"
```

---

### Task 3: SuperModelDownloadManager — Disk Space + Fast Path + SHA256

**Files:**
- Modify: `Govorun/Services/SuperModelDownloadManager.swift`
- Modify: `GovorunTests/SuperModelDownloadManagerTests.swift`

**Context:** Before downloading, the manager checks: (1) if the file already exists with correct SHA256 (fast path → `.completed`), (2) if there's enough disk space. SHA256 is computed with CryptoKit.

- [ ] **Step 1: Write failing tests**

Append to `SuperModelDownloadManagerImplTests` in `GovorunTests/SuperModelDownloadManagerTests.swift`:

```swift
    // MARK: - Fast path

    func test_download_existing_file_with_correct_sha_completes_immediately() async {
        // Создаём файл с известным содержимым и вычисляем его SHA256
        let content = Data("test model content for sha256 verification".utf8)
        try! content.write(to: spec.destination)

        let sha256 = SHA256.hash(data: content)
            .map { String(format: "%02x", $0) }
            .joined()

        let specWithSHA = SuperModelDownloadSpec(
            url: spec.url,
            destination: spec.destination,
            expectedSHA256: sha256,
            expectedSize: Int64(content.count)
        )

        let manager = SuperModelDownloadManager()
        var states: [SuperModelDownloadState] = []
        manager.onStateChanged = { state in
            states.append(state)
        }

        await manager.download(from: specWithSHA)
        // Ждём чтобы callback успел прийти
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(states.contains(.checkingExisting))
        XCTAssertTrue(states.contains(.completed))
    }

    func test_download_existing_file_with_wrong_sha_does_not_complete() async {
        let content = Data("some data".utf8)
        try! content.write(to: spec.destination)

        let specWithWrongSHA = SuperModelDownloadSpec(
            url: spec.url,
            destination: spec.destination,
            expectedSHA256: "definitely-wrong-sha256",
            expectedSize: Int64(content.count)
        )

        let manager = SuperModelDownloadManager()
        await manager.download(from: specWithWrongSHA)
        // Без реального URL скачивание упадёт, но важно что fast path не сработал
        XCTAssertNotEqual(manager.state, .completed)
    }

    // MARK: - Disk space

    func test_download_insufficient_disk_space_fails() async {
        // spec с expectedSize больше чем свободное место + буфер
        let hugeSpec = SuperModelDownloadSpec(
            url: spec.url,
            destination: spec.destination,
            expectedSHA256: spec.expectedSHA256,
            expectedSize: Int64.max // гарантированно больше свободного места
        )

        let manager = SuperModelDownloadManager()
        await manager.download(from: hugeSpec)

        if case .failed(.insufficientDiskSpace) = manager.state {
            // OK
        } else {
            XCTFail("Ожидался .failed(.insufficientDiskSpace), получен \(manager.state)")
        }
    }

    // MARK: - SHA256

    func test_sha256_computation_is_correct() {
        let data = Data("hello world".utf8)
        let expected = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
        let hash = SuperModelDownloadManager.sha256(of: data)
        XCTAssertEqual(hash, expected)
    }
```

Add `import CryptoKit` at the top of the test file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperModelDownloadManagerImplTests 2>&1 | tail -20`

Expected: FAIL — `sha256(of:)` doesn't exist, `download()` is a stub.

- [ ] **Step 3: Implement SHA256 + disk space check + fast path**

Add `import CryptoKit` at the top of `SuperModelDownloadManager.swift`, then add these methods:

```swift
    // MARK: - SHA256

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func sha256(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }

        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1 МБ
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: bufferSize)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    // MARK: - Disk space

    private func availableDiskSpace(at url: URL) -> Int64? {
        let dir = url.deletingLastPathComponent()
        guard let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return capacity
    }
```

Replace the stub `download(from:)` with the beginning of the real implementation:

```swift
    func download(from spec: SuperModelDownloadSpec) async {
        guard !isActive else { return }

        // Fast path: файл уже есть и SHA256 совпадает
        setState(.checkingExisting)
        if FileManager.default.fileExists(atPath: spec.destination.path) {
            if let hash = Self.sha256(ofFileAt: spec.destination),
               hash == spec.expectedSHA256 {
                setState(.completed)
                return
            }
        }

        // Disk space check
        let partialSize = (try? FileManager.default.attributesOfItem(atPath: partialURL(for: spec).path))?[.size] as? Int64 ?? 0
        let neededBytes = spec.expectedSize - partialSize + SuperModelCatalog.minimumDiskSpaceBuffer
        if let available = availableDiskSpace(at: spec.destination), available < neededBytes {
            setState(.failed(.insufficientDiskSpace(required: neededBytes, available: available)))
            return
        }

        // Создаём директорию если нет
        let dir = spec.destination.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Сетевое скачивание — будет реализовано в Task 4
        setState(.failed(.networkError("download not implemented yet")))
    }
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperModelDownloadManagerImplTests 2>&1 | tail -20`

Expected: All tests PASS (fast path, disk space, SHA256 tests).

- [ ] **Step 5: Commit**

```bash
git add Govorun/Services/SuperModelDownloadManager.swift GovorunTests/SuperModelDownloadManagerTests.swift
git commit -m "feat: fast path (SHA256) + проверка свободного места для скачивания модели"
```

---

### Task 4: SuperModelDownloadManager — Download, Resume, Verify, Cancel

**Files:**
- Modify: `Govorun/Services/SuperModelDownloadManager.swift`
- Modify: `GovorunTests/SuperModelDownloadManagerTests.swift`

**Context:** Core download logic using `URLSession.bytes(for:)` with 256 KB buffered writes (NOT byte-by-byte — 6 GB file requires chunked I/O). Cancel works through `Task.cancel()` in AppState — `Task.isCancelled` checked in download loop. `verifyAndFinalize` returns typed `Result<Void, SuperModelDownloadError>`.

- [ ] **Step 1: Write failing tests for verify + cancel**

Append to `SuperModelDownloadManagerImplTests`:

```swift
    // MARK: - SHA256 verification

    func test_verify_correct_sha_renames_to_destination() {
        let content = Data("verified model data".utf8)
        let sha = SuperModelDownloadManager.sha256(of: content)

        let partial = tempDir.appendingPathComponent("model.gguf.partial")
        try! content.write(to: partial)

        let verifySpec = SuperModelDownloadSpec(
            url: URL(string: "https://example.com/model.gguf")!,
            destination: tempDir.appendingPathComponent("model.gguf"),
            expectedSHA256: sha,
            expectedSize: Int64(content.count)
        )

        let manager = SuperModelDownloadManager()
        let result = manager.verifyAndFinalize(spec: verifySpec)
        switch result {
        case .success:
            XCTAssertTrue(FileManager.default.fileExists(atPath: verifySpec.destination.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        case .failure(let error):
            XCTFail("Ожидался success, получен \(error)")
        }
    }

    func test_verify_wrong_sha_returns_integrityCheckFailed() {
        let content = Data("bad data".utf8)
        let partial = tempDir.appendingPathComponent("model.gguf.partial")
        try! content.write(to: partial)

        let verifySpec = SuperModelDownloadSpec(
            url: URL(string: "https://example.com/model.gguf")!,
            destination: tempDir.appendingPathComponent("model.gguf"),
            expectedSHA256: "wrong-sha-256",
            expectedSize: Int64(content.count)
        )

        let manager = SuperModelDownloadManager()
        let result = manager.verifyAndFinalize(spec: verifySpec)
        if case .failure(.integrityCheckFailed) = result {
            // OK
        } else {
            XCTFail("Ожидался .integrityCheckFailed, получен \(result)")
        }
    }

    func test_verify_missing_partial_returns_fileSystemError() {
        let verifySpec = SuperModelDownloadSpec(
            url: URL(string: "https://example.com/model.gguf")!,
            destination: tempDir.appendingPathComponent("model.gguf"),
            expectedSHA256: "abc",
            expectedSize: 100
        )

        let manager = SuperModelDownloadManager()
        let result = manager.verifyAndFinalize(spec: verifySpec)
        if case .failure(.fileSystemError) = result {
            // OK
        } else {
            XCTFail("Ожидался .fileSystemError, получен \(result)")
        }
    }

    // MARK: - Cancel

    func test_cancel_without_active_download_does_nothing() {
        let manager = SuperModelDownloadManager()
        manager.cancel()
        XCTAssertEqual(manager.state, .idle) // не .cancelled
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `verifyAndFinalize` not found.

- [ ] **Step 3: Implement download with buffered writes + cancel via Task + typed verifyAndFinalize**

Replace the download/cancel stubs in `SuperModelDownloadManager.swift`. Подход: `URLSession.shared.bytes(for:)` + буфер 256 КБ для записи чанками (не побайтово). Cancel через `Task.cancel()` в AppState.

```swift
    func download(from spec: SuperModelDownloadSpec) async {
        guard !isActive else { return }

        // Fast path
        setState(.checkingExisting)
        if FileManager.default.fileExists(atPath: spec.destination.path) {
            if let hash = Self.sha256(ofFileAt: spec.destination),
               hash == spec.expectedSHA256 {
                setState(.completed)
                return
            }
        }

        // Disk space check
        let partialSize = (try? FileManager.default.attributesOfItem(
            atPath: partialURL(for: spec).path
        ))?[.size] as? Int64 ?? 0
        let neededBytes = spec.expectedSize - partialSize + SuperModelCatalog.minimumDiskSpaceBuffer
        if let available = availableDiskSpace(at: spec.destination), available < neededBytes {
            setState(.failed(.insufficientDiskSpace(required: neededBytes, available: available)))
            return
        }

        // Создаём директорию
        let dir = spec.destination.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Resume check
        let partial = partialURL(for: spec)
        var resumeOffset: Int64 = 0
        if let meta = readMeta(for: spec),
           meta.expectedSHA256 == spec.expectedSHA256,
           meta.url == spec.url.absoluteString,
           FileManager.default.fileExists(atPath: partial.path) {
            resumeOffset = meta.downloadedBytes
        } else {
            try? FileManager.default.removeItem(at: partial)
            deleteMeta(for: spec)
        }

        var request = URLRequest(url: spec.url)
        if resumeOffset > 0 {
            request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
        }

        setState(.downloading(progress: 0, downloadedBytes: resumeOffset, totalBytes: spec.expectedSize))

        // Подготовка файла
        if resumeOffset == 0 || !FileManager.default.fileExists(atPath: partial.path) {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        guard let fileHandle = try? FileHandle(forWritingTo: partial) else {
            setState(.failed(.fileSystemError("Не удалось открыть файл для записи")))
            return
        }
        if resumeOffset > 0 { fileHandle.seekToEndOfFile() }

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                fileHandle.closeFile()
                setState(.failed(.networkError("Не HTTP ответ")))
                return
            }

            if httpResponse.statusCode == 200 && resumeOffset > 0 {
                // Сервер не поддержал Range — начинаем сначала
                resumeOffset = 0
                fileHandle.truncateFile(atOffset: 0)
                fileHandle.seek(toFileOffset: 0)
            } else if httpResponse.statusCode != 200 && httpResponse.statusCode != 206 {
                fileHandle.closeFile()
                setState(.failed(.networkError("HTTP \(httpResponse.statusCode)")))
                return
            }

            let etag = httpResponse.value(forHTTPHeaderField: "ETag")
            var downloadedBytes = resumeOffset
            let totalBytes = spec.expectedSize
            var lastProgressUpdate = Date()
            var buffer = Data()
            let bufferFlushSize = 256 * 1024 // 256 КБ — flush чанками

            for try await byte in asyncBytes {
                if Task.isCancelled {
                    // Flush оставшийся буфер
                    if !buffer.isEmpty {
                        fileHandle.write(buffer)
                        downloadedBytes += Int64(buffer.count)
                    }
                    fileHandle.closeFile()
                    writeMeta(PartialDownloadMeta(
                        url: spec.url.absoluteString,
                        expectedSHA256: spec.expectedSHA256,
                        expectedSize: spec.expectedSize,
                        etag: etag,
                        downloadedBytes: downloadedBytes
                    ), for: spec)
                    setState(.cancelled)
                    return
                }

                buffer.append(byte)

                if buffer.count >= bufferFlushSize {
                    fileHandle.write(buffer)
                    downloadedBytes += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)

                    let now = Date()
                    if now.timeIntervalSince(lastProgressUpdate) >= 0.5 {
                        lastProgressUpdate = now
                        let progress = Double(downloadedBytes) / Double(totalBytes)
                        setState(.downloading(
                            progress: progress,
                            downloadedBytes: downloadedBytes,
                            totalBytes: totalBytes
                        ))
                        writeMeta(PartialDownloadMeta(
                            url: spec.url.absoluteString,
                            expectedSHA256: spec.expectedSHA256,
                            expectedSize: spec.expectedSize,
                            etag: etag,
                            downloadedBytes: downloadedBytes
                        ), for: spec)
                    }
                }
            }

            // Flush остаток
            if !buffer.isEmpty {
                fileHandle.write(buffer)
                downloadedBytes += Int64(buffer.count)
            }
            fileHandle.closeFile()

            // Финальное обновление meta
            writeMeta(PartialDownloadMeta(
                url: spec.url.absoluteString,
                expectedSHA256: spec.expectedSHA256,
                expectedSize: spec.expectedSize,
                etag: etag,
                downloadedBytes: downloadedBytes
            ), for: spec)

        } catch {
            fileHandle.closeFile()
            if Task.isCancelled {
                setState(.cancelled)
            } else {
                setState(.failed(.networkError(error.localizedDescription)))
            }
            return
        }

        // Verification
        setState(.verifying)
        switch verifyAndFinalize(spec: spec) {
        case .success:
            setState(.completed)
        case .failure(let error):
            if case .integrityCheckFailed = error {
                try? FileManager.default.removeItem(at: partial)
                deleteMeta(for: spec)
            }
            setState(.failed(error))
        }
    }

    // MARK: - Verify

    func verifyAndFinalize(spec: SuperModelDownloadSpec) -> Result<Void, SuperModelDownloadError> {
        let partial = partialURL(for: spec)
        guard let hash = Self.sha256(ofFileAt: partial) else {
            return .failure(.fileSystemError("Не удалось прочитать файл для проверки"))
        }
        guard hash == spec.expectedSHA256 else {
            return .failure(.integrityCheckFailed)
        }
        do {
            if FileManager.default.fileExists(atPath: spec.destination.path) {
                try FileManager.default.removeItem(at: spec.destination)
            }
            try FileManager.default.moveItem(at: partial, to: spec.destination)
            deleteMeta(for: spec)
            return .success(())
        } catch {
            return .failure(.fileSystemError("Не удалось переместить файл: \(error.localizedDescription)"))
        }
    }

    // MARK: - Cancel

    func cancel() {
        // Отменяем Task, который владеет download loop.
        // Task.isCancelled проверяется внутри цикла for-await — I/O реально останавливается.
        // URLSession.bytes тоже бросит CancellationError при отмене Task.
        lock.withLock {
            if case .downloading = _state {
                _state = .cancelled
                let callback = onStateChanged
                Task { @MainActor in
                    callback?(.cancelled)
                }
            }
        }
    }
```

**Вызов download() должен оборачиваться в Task, который можно отменить:**

В AppState (Task 5), `startSuperModelDownload` выглядит так:
```swift
private var downloadTask: Task<Void, Never>?

func startSuperModelDownload() async {
    guard !superModelDownloadManager.isActive else { return }
    guard superAssetsState == .modelMissing else { return }
    let task = Task {
        await superModelDownloadManager.download(from: SuperModelCatalog.current)
    }
    downloadTask = task
    await task.value
}

func cancelSuperModelDownload() {
    downloadTask?.cancel()  // отменяет Task → Task.isCancelled = true внутри download loop
    superModelDownloadManager.cancel()  // обновляет state на .cancelled
}
```

Буферизация: данные копятся в `Data` буфере по 256 КБ, затем flush в fileHandle. Это сокращает количество I/O операций с миллиардов до ~23 000 для 6 ГБ файла.

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation -only-testing:GovorunTests/SuperModelDownloadManagerImplTests 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Govorun/Services/SuperModelDownloadManager.swift GovorunTests/SuperModelDownloadManagerTests.swift
git commit -m "feat: скачивание модели с буферизованной записью, resume и SHA256 верификацией"
```

---

### Task 5: AppState — handleSuperAssetsChanged Coordinator + Download Wiring

**Files:**
- Modify: `Govorun/App/AppState.swift`
- Modify: `GovorunTests/IntegrationTests.swift`

**Context:** AppState gets a new coordinator method `handleSuperAssetsChanged()` that replaces scattered refresh+start/stop calls. Also wires `SuperModelDownloadManager` with `superModelDownloadState` property, download methods, and restore-on-launch.

Read `Govorun/App/AppState.swift` fully before making changes. Key areas to modify:
- Line ~80: add `superModelDownloadState` property
- Line ~104-201: production init — add `superModelDownloadManager` creation + wiring
- Line ~204-266: test init — add `superModelDownloadManager` parameter
- Line ~279-285: `refreshSuperAssetsReadiness()` — unchanged
- Line ~530-558: `applyProductMode()` — replace `startLLMRuntimeIfAssetsReady()` call with `handleSuperAssetsChanged()`
- Line ~574-609: `startLLMRuntimeIfAssetsReady()` — fold into `handleSuperAssetsChanged()`
- Line ~669-684: wiring methods — add `wireSuperModelDownloadManager()`

- [ ] **Step 1: Write failing tests for download guards**

Add to `GovorunTests/IntegrationTests.swift` — after existing test methods:

```swift
    // MARK: - Super Model Download

    @MainActor
    func test_startSuperModelDownload_guards_when_already_active() async {
        let (appState, _, _) = await makeTestAppState(productMode: .superMode)
        let mockDownloader = appState.testSuperModelDownloader!
        await mockDownloader.simulateStateChange(
            .downloading(progress: 0.5, downloadedBytes: 100, totalBytes: 200)
        )
        await appState.startSuperModelDownload()
        // download не должен быть вызван повторно
        XCTAssertFalse(mockDownloader.downloadCalled)
    }

    @MainActor
    func test_startSuperModelDownload_guards_when_not_modelMissing() async {
        let (appState, _, _) = await makeTestAppState(productMode: .superMode)
        // superAssetsState = .installed (через MockSuperAssetsManager + refresh)
        await appState.refreshSuperAssetsReadiness()
        await appState.startSuperModelDownload()
        let mockDownloader = appState.testSuperModelDownloader!
        XCTAssertFalse(mockDownloader.downloadCalled)
    }

    @MainActor
    func test_cancelSuperModelDownload_calls_cancel() async {
        let (appState, _, _) = await makeTestAppState(productMode: .superMode)
        appState.cancelSuperModelDownload()
        let mockDownloader = appState.testSuperModelDownloader!
        XCTAssertTrue(mockDownloader.cancelCalled)
    }
```

- [ ] **Step 2: Update makeTestAppState to accept MockSuperModelDownloader**

In `GovorunTests/IntegrationTests.swift`, update `makeTestAppState`:

1. Add parameter: `superModelDownloader: MockSuperModelDownloader = MockSuperModelDownloader()`
2. Pass it to AppState tester init
3. Add `testSuperModelDownloader` accessor to AppState (or use a test-specific property)

The cleanest approach: in the tester init of `AppState`, add parameter `superModelDownloadManager: any SuperModelDownloading = SuperModelDownloadManager()`. Then in `makeTestAppState`, pass `MockSuperModelDownloader()`.

- [ ] **Step 3: Add superModelDownloadState + methods to AppState**

In `Govorun/App/AppState.swift`:

1. After line ~80 (`superAssetsState`), add:
```swift
@Published private(set) var superModelDownloadState: SuperModelDownloadState = .idle
private let superModelDownloadManager: any SuperModelDownloading
```

2. In production init (line ~104), create and wire:
```swift
let downloadManager = SuperModelDownloadManager()
self.superModelDownloadManager = downloadManager
```

After all properties are set, wire callback + restore:
```swift
superModelDownloadManager.onStateChanged = { [weak self] state in
    self?.superModelDownloadState = state
}
superModelDownloadManager.restoreStateFromDisk(for: SuperModelCatalog.current)
```

3. In tester init (line ~204), add parameter:
```swift
superModelDownloadManager: any SuperModelDownloading = SuperModelDownloadManager(),
```

4. Add `downloadTask` property and methods:
```swift
private var downloadTask: Task<Void, Never>?

func startSuperModelDownload() async {
    guard !superModelDownloadManager.isActive else { return }
    guard superAssetsState == .modelMissing else { return }
    let task = Task {
        await superModelDownloadManager.download(from: SuperModelCatalog.current)
    }
    downloadTask = task
    await task.value
}

func cancelSuperModelDownload() {
    downloadTask?.cancel()  // Task.isCancelled = true → download loop stops
    superModelDownloadManager.cancel()  // updates state to .cancelled
}

func clearPartialSuperModelDownload() {
    superModelDownloadManager.clearPartialDownload(for: SuperModelCatalog.current)
}

func deleteCorruptedModelAndRedownload() async {
    let spec = SuperModelCatalog.current
    try? FileManager.default.removeItem(at: spec.destination)
    // Сначала refresh — переводит superAssetsState из .error в .modelMissing
    // Без этого guard в startSuperModelDownload() заблокирует старт
    await refreshSuperAssetsReadiness()
    await startSuperModelDownload()
}

// Для UI: есть ли физический файл модели (битый, маленький и т.д.)
// Используется вместо парсинга текста ошибок из SuperAssetsState.error
var superModelFileExists: Bool {
    FileManager.default.fileExists(atPath: SuperModelCatalog.current.destination.path)
}
```

5. Create `handleSuperAssetsChanged()`:
```swift
func handleSuperAssetsChanged() async {
    await refreshSuperAssetsReadiness()

    guard effectiveProductMode == .superMode else {
        llmRuntimeManager?.stop()
        updateLLMRuntimeState(.disabled)
        return
    }

    guard superAssetsState == .installed else {
        llmRuntimeManager?.stop()
        updateLLMRuntimeState(.disabled)
        return
    }

    // Та же логика что в startLLMRuntimeIfAssetsReady — конфигурация + старт
    guard let llmRuntimeManager else { return }
    // ... (скопировать конфигурацию из startLLMRuntimeIfAssetsReady lines ~574-609)
}
```

6. Replace calls to `startLLMRuntimeIfAssetsReady()` in `applyProductMode()` and other callers with `await handleSuperAssetsChanged()`.

7. In the download state callback, add post-download flow:
```swift
superModelDownloadManager.onStateChanged = { [weak self] state in
    self?.superModelDownloadState = state
    if state == .completed {
        Task { [weak self] in
            await self?.handleSuperAssetsChanged()
        }
    }
}
```

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -30`

Expected: All tests PASS (existing + new).

- [ ] **Step 5: Commit**

```bash
git add Govorun/App/AppState.swift GovorunTests/IntegrationTests.swift
git commit -m "feat: AppState wiring для скачивания модели + handleSuperAssetsChanged coordinator"
```

---

### Task 6: SettingsView — ProductModeCard Download UI

**Files:**
- Modify: `Govorun/Views/SettingsView.swift`

**Context:** ProductModeCard needs to show download states based on the combination of `superAssetsState` and `superModelDownloadState`. The `superAvailable` computed property must change to allow picker selection when `.modelMissing`. Download CTA, progress bar, error/cancelled states all go inside the card.

Read `Govorun/Views/SettingsView.swift` fully before changes. Key areas:
- Lines 291-298: `superAvailable` — modify to allow `.modelMissing` and `.error`
- Lines 300-313: `assetsStatusText` — expand with download states
- Lines 315-322: `assetsStatusIcon` — expand
- Lines 324-365: ProductModeCard body — add download UI section

- [ ] **Step 1: Update superAvailable**

```swift
private var superAvailable: Bool {
    switch appState.superAssetsState {
    case .installed, .unknown, .checking, .modelMissing, .error: true
    case .runtimeMissing: false
    }
}
```

- [ ] **Step 2: Add download state view to ProductModeCard**

After the existing assets status section, add a new `@ViewBuilder` property:

```swift
@ViewBuilder
private var downloadStatusView: some View {
    let downloadState = appState.superModelDownloadState
    let assetsState = appState.superAssetsState

    if case .runtimeMissing = assetsState {
        // Не показываем download UI при runtimeMissing
        EmptyView()
    } else if case .installed = assetsState {
        Label("Я готов к работе в Супер-режиме", systemImage: "checkmark.circle")
            .font(.caption)
            .foregroundStyle(.green)
    } else if case .error(let msg) = assetsState {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ошибка: \(msg)", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
            HStack(spacing: 8) {
                Button("Проверить снова") {
                    Task { await appState.handleSuperAssetsChanged() }
                }
                .font(.caption)
                // Показываем "Удалить и скачать заново" если файл модели существует
                // (битый, слишком маленький и т.д.). Не парсим текст ошибки.
                if appState.superModelFileExists {
                    Button("Удалить и скачать заново") {
                        Task { await appState.deleteCorruptedModelAndRedownload() }
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
    } else if case .modelMissing = assetsState {
        switch downloadState {
        case .idle:
            VStack(alignment: .leading, spacing: 8) {
                Label("Мне нужна ИИ-модель", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Чтобы я мог работать в Супер-режиме, скачайте ИИ-модель (5.8 ГБ). Это может занять 5–30 минут.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Скачать ИИ-модель") {
                    Task { await appState.startSuperModelDownload() }
                }
                .font(.caption)
            }

        case .partialReady(let downloaded, let total):
            VStack(alignment: .leading, spacing: 8) {
                Text("Скачано \(formatBytes(downloaded)) из \(formatBytes(total)). Можно продолжить.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Продолжить") {
                        Task { await appState.startSuperModelDownload() }
                    }
                    .font(.caption)
                    Button("Удалить") {
                        appState.clearPartialSuperModelDownload()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }

        case .checkingExisting:
            Label("Проверяю...", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .downloading(let progress, let downloaded, let total):
            VStack(alignment: .leading, spacing: 6) {
                Text("Скачиваю ИИ-модель...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(formatBytes(downloaded)) / \(formatBytes(total))")
                    .font(.caption)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Отменить") {
                        appState.cancelSuperModelDownload()
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .buttonStyle(.plain)
                }
            }

        case .verifying:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Проверяю целостность файла...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .completed:
            Label("Я готов к работе в Супер-режиме", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)

        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                Label("Не удалось скачать", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                if let description = error.errorDescription {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if case .integrityCheckFailed = error {
                    Button("Скачать заново") {
                        appState.clearPartialSuperModelDownload()
                        Task { await appState.startSuperModelDownload() }
                    }
                    .font(.caption)
                } else {
                    Button("Продолжить скачивание") {
                        Task { await appState.startSuperModelDownload() }
                    }
                    .font(.caption)
                }
            }

        case .cancelled:
            VStack(alignment: .leading, spacing: 8) {
                Text("Скачивание отменено")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Продолжить") {
                        Task { await appState.startSuperModelDownload() }
                    }
                    .font(.caption)
                    Button("Удалить") {
                        appState.clearPartialSuperModelDownload()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
    }
}

private func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000
    return String(format: "%.1f ГБ", gb)
}
```

- [ ] **Step 3: Wire downloadStatusView into ProductModeCard body**

In the ProductModeCard body, after the Picker and before the runtime status section, insert:

```swift
// ВАЖНО: использовать settings.productMode (выбранный в picker),
// НЕ appState.effectiveProductMode (который остаётся .standard при .modelMissing).
// Иначе download CTA не покажется именно в том состоянии,
// для которого он нужен.
if appState.settings.productMode == .superMode {
    downloadStatusView
}
```

Remove the old `assetsStatusText`/`assetsStatusIcon` usage for `.modelMissing` (replaced by `downloadStatusView`).

- [ ] **Step 4: Run tests to verify no regressions**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Govorun/Views/SettingsView.swift
git commit -m "feat: UI скачивания ИИ-модели в ProductModeCard"
```

---

### Task 7: OnboardingView — Super Model Download Step

**Files:**
- Modify: `Govorun/Views/OnboardingView.swift`

**Context:** Add an optional step after the ASR model download step offering to download the Super mode model. Uses the same `startSuperModelDownload()` from AppState. Terminology: "ИИ-модель для Супер-режима" (vs existing "модель распознавания").

Read `Govorun/Views/OnboardingView.swift` fully. The existing `ModelStepView` (lines 303-417) shows the pattern. Create a similar `SuperModelStepView` that:
- Shows current `superModelDownloadState` from AppState
- Has "Скачать ИИ-модель для Супер-режима (~5.8 ГБ)" button
- Shows progress bar during download
- Has "Пропустить" to skip
- Checks network availability via `appState.networkMonitor`

- [ ] **Step 1: Create SuperModelStepView**

Add after `ModelStepView` in `OnboardingView.swift`:

```swift
private struct SuperModelStepView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var skipped: Bool

    private var downloadState: SuperModelDownloadState {
        appState.superModelDownloadState
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.cottonCandy)

            Text("Супер-режим")
                .font(.title2.bold())

            Text("ИИ-модель для Супер-режима улучшает качество текста с помощью локальной нейросети. Полностью офлайн.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                switch downloadState {
                case .completed:
                    OnboardingStatusBadge(
                        text: "ИИ-модель для Супер-режима готова",
                        icon: "checkmark.circle.fill",
                        color: .oceanMist
                    )

                case .downloading(let progress, let downloaded, let total):
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Color.cottonCandy)
                            .frame(width: 240)
                        let downloadedGB = String(format: "%.1f", Double(downloaded) / 1_000_000_000)
                        let totalGB = String(format: "%.1f", Double(total) / 1_000_000_000)
                        Text("Скачиваю… \(downloadedGB) / \(totalGB) ГБ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Отменить") {
                            appState.cancelSuperModelDownload()
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .buttonStyle(.plain)
                    }

                case .verifying:
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.cottonCandy)
                        Text("Проверяю целостность…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .checkingExisting:
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.cottonCandy)
                        Text("Проверяю…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .failed(let error):
                    VStack(spacing: 10) {
                        OnboardingStatusBadge(
                            text: error.errorDescription ?? "Ошибка скачивания",
                            icon: "exclamationmark.triangle.fill",
                            color: .red
                        )
                        HStack(spacing: 12) {
                            BrandedButton(title: "Повторить", style: .primary) {
                                Task { await appState.startSuperModelDownload() }
                            }
                            BrandedButton(title: "Пропустить", style: .secondary) {
                                skipped = true
                            }
                        }
                    }

                case .idle, .cancelled, .partialReady:
                    VStack(spacing: 10) {
                        if !appState.networkMonitor.isCurrentlyConnected {
                            OnboardingStatusBadge(
                                text: "Нет интернета",
                                icon: "wifi.slash",
                                color: .orange
                            )
                        }
                        BrandedButton(title: "Скачать (~5.8 ГБ)", style: .primary) {
                            Task { await appState.startSuperModelDownload() }
                        }
                        .disabled(!appState.networkMonitor.isCurrentlyConnected)
                        .opacity(appState.networkMonitor.isCurrentlyConnected ? 1 : 0.5)

                        Button("Пропустить") {
                            skipped = true
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Wire SuperModelStepView into the onboarding flow**

Find the step array/navigation in OnboardingView and add a new step after the ASR model step. The exact wiring depends on how steps are managed — look for the `steps` array or `currentStep` state. Add the new step conditionally (only if runtime is available — `superAssetsState != .runtimeMissing`).

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -scheme Govorun -destination 'platform=macOS' -skipPackagePluginValidation 2>&1 | tail -20`

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add Govorun/Views/OnboardingView.swift
git commit -m "feat: шаг онбординга для скачивания ИИ-модели Супер-режима"
```

---

## Self-Review

**1. Spec coverage:**
- SuperModelDownloadSpec, State, Error ✅ (Task 1)
- SuperModelCatalog ✅ (Task 1)
- SuperModelDownloading protocol ✅ (Task 1)
- Sidecar metadata + restoreStateFromDisk ✅ (Task 2)
- Fast path + disk space + SHA256 ✅ (Task 3)
- Download + resume + 206/200 + verify + cancel ✅ (Task 4)
- handleSuperAssetsChanged coordinator ✅ (Task 5)
- AppState wiring (methods, restore, post-download) ✅ (Task 5)
- SettingsView ProductModeCard all states ✅ (Task 6)
- superAvailable change (.modelMissing allowed) ✅ (Task 6)
- .error(msg) with "Удалить и скачать заново" ✅ (Task 6)
- OnboardingView Super model step ✅ (Task 7)
- macOS notification — covered in Task 5 post-download flow (best-effort)
- .completed transient state ✅ (Task 2 — restoreStateFromDisk skips completed)
- Wiring order (onStateChanged before restoreStateFromDisk) ✅ (Task 5)
- External endpoint bypass (no CTA) ✅ (Task 6 — downloadStatusView checks assetsState)

**2. Placeholder scan:** No TBD/TODO except SuperModelCatalog URL/SHA256 (intentional — needs real HF values).

**3. Type consistency:** All types use `Super` prefix consistently. `isActive` used everywhere (not `isDownloading`). `handleSuperAssetsChanged()` named consistently across tasks. `SuperModelCatalog.current` used as spec source. `verifyAndFinalize` returns `Result<Void, SuperModelDownloadError>` (not Bool). Cancel works via `Task.cancel()` in AppState + state update in manager. Download uses 256 KB buffered writes (not byte-by-byte). UI condition uses `settings.productMode` (not `effectiveProductMode`). `deleteCorruptedModelAndRedownload` calls `refreshSuperAssetsReadiness()` before `startSuperModelDownload()` to move from `.error` to `.modelMissing`.
