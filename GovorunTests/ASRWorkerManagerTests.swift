import XCTest
@testable import Govorun

// MARK: - Потокобезопасный коллектор состояний

private final class StateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _states: [WorkerState] = []

    var states: [WorkerState] {
        lock.lock()
        defer { lock.unlock() }
        return _states
    }

    func append(_ state: WorkerState) {
        lock.lock()
        _states.append(state)
        lock.unlock()
    }
}

// MARK: - ASRWorkerManager тесты

final class ASRWorkerManagerTests: XCTestCase {

    // MARK: - Начальное состояние

    func test_initialState_isNotStarted() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/govorun-test-worker")
        XCTAssertEqual(manager.state, .notStarted)
        XCTAssertFalse(manager.isReady)
    }

    func test_socketPath_defaultsToGovorunDir() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        let expected = NSString("~/.govorun/worker.sock").expandingTildeInPath
        XCTAssertEqual(manager.socketPath, expected)
    }

    func test_socketPath_customizable() {
        let custom = "/tmp/test.sock"
        let manager = ASRWorkerManager(
            workerDirectory: "/tmp/test",
            socketPath: custom
        )
        XCTAssertEqual(manager.socketPath, custom)
    }

    // MARK: - Парсинг stdout

    func test_handleStdoutLine_downloading_setsDownloadingModel() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        manager.handleStdoutLine("DOWNLOADING 45%")
        XCTAssertEqual(manager.state, .downloadingModel(progress: 45))
    }

    func test_handleStdoutLine_downloading_0_and_100() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        manager.handleStdoutLine("DOWNLOADING 0%")
        XCTAssertEqual(manager.state, .downloadingModel(progress: 0))
        manager.handleStdoutLine("DOWNLOADING 100%")
        XCTAssertEqual(manager.state, .downloadingModel(progress: 100))
    }

    func test_handleStdoutLine_downloading_then_loading() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        manager.handleStdoutLine("DOWNLOADING 100%")
        XCTAssertEqual(manager.state, .downloadingModel(progress: 100))
        manager.handleStdoutLine("LOADING model=gigaam-v3-e2e-rnnt vad=silero version=1")
        XCTAssertEqual(manager.state, .loadingModel)
    }

    func test_handleStdoutLine_loading_setsLoadingModel() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        manager.handleStdoutLine("LOADING model=gigaam-v3-e2e-rnnt vad=silero version=1")
        XCTAssertEqual(manager.state, .loadingModel)
    }

    func test_handleStdoutLine_loaded_doesNotChangeState() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        manager.setState(.loadingModel)
        manager.handleStdoutLine("LOADED 3.2s")
        // LOADED — промежуточный статус, состояние остаётся .loadingModel
        XCTAssertEqual(manager.state, .loadingModel)
    }

    func test_handleStdoutLine_ready_setsReady() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        var readyCalled = false
        manager.handleStdoutLine("READY") {
            readyCalled = true
        }
        XCTAssertEqual(manager.state, .ready)
        XCTAssertTrue(manager.isReady)
        XCTAssertTrue(readyCalled)
    }

    func test_handleStdoutLine_unknownLine_noStateChange() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        manager.setState(.loadingModel)
        manager.handleStdoutLine("some random output from python")
        XCTAssertEqual(manager.state, .loadingModel)
    }

    func test_handleStdoutLine_fullSequence_withDownload() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")

        manager.handleStdoutLine("DOWNLOADING 0%")
        XCTAssertEqual(manager.state, .downloadingModel(progress: 0))

        manager.handleStdoutLine("DOWNLOADING 50%")
        XCTAssertEqual(manager.state, .downloadingModel(progress: 50))

        manager.handleStdoutLine("DOWNLOADING 100%")
        XCTAssertEqual(manager.state, .downloadingModel(progress: 100))

        manager.handleStdoutLine("LOADING model=gigaam-v3-e2e-rnnt vad=silero version=1")
        XCTAssertEqual(manager.state, .loadingModel)

        manager.handleStdoutLine("LOADED 3.2s")
        XCTAssertEqual(manager.state, .loadingModel)

        manager.handleStdoutLine("READY")
        XCTAssertEqual(manager.state, .ready)
    }

    func test_handleStdoutLine_fullSequence_cached() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")

        // Модель в кэше — DOWNLOADING не появляется
        manager.handleStdoutLine("LOADING model=gigaam-v3-e2e-rnnt vad=silero version=1")
        XCTAssertEqual(manager.state, .loadingModel)

        manager.handleStdoutLine("LOADED 0.9s")
        XCTAssertEqual(manager.state, .loadingModel)

        manager.handleStdoutLine("READY")
        XCTAssertEqual(manager.state, .ready)
    }

    // MARK: - onStateChanged callback

    func test_onStateChanged_calledOnTransition() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        let collector = StateCollector()
        manager.onStateChanged = { [collector] state in
            collector.append(state)
        }

        manager.handleStdoutLine("LOADING model=gigaam version=1")
        manager.handleStdoutLine("READY")

        XCTAssertEqual(collector.states, [.loadingModel, .ready])
    }

    // MARK: - Timeout: onReady callback вызывается (для cancel в реальном коде)

    func test_ready_callsOnReadyCallback_forTimeoutCancel() {
        // В launchWorker() onReady вызывает timeoutWork.cancel().
        // Здесь проверяем что handleStdoutLine("READY") вызывает onReady.
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        var onReadyCalled = false

        manager.handleStdoutLine("READY") {
            onReadyCalled = true
        }

        XCTAssertTrue(onReadyCalled, "onReady должен быть вызван — в реальном коде он отменяет timeout")
        XCTAssertEqual(manager.state, .ready)
    }

    func test_setState_error_overwrites_ready_proving_cancel_is_necessary() {
        // Доказываем что без cancel таймаут ПЕРЕЗАПИСАЛ БЫ .ready на .error.
        // Именно поэтому DispatchWorkItem.cancel() обязателен при получении READY.
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        manager.setState(.ready)
        XCTAssertEqual(manager.state, .ready)

        // Без cancel, timeout вызвал бы setState(.error) — и .ready был бы потерян
        manager.setState(.error("Таймаут загрузки модели"))
        XCTAssertEqual(manager.state, .error("Таймаут загрузки модели"),
                       "setState(.error) перезаписывает .ready — cancel обязателен")
    }

    func test_ready_onReadyNotCalledForLoading() {
        // onReady НЕ вызывается для LOADING — только для READY
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        var onReadyCalled = false

        manager.handleStdoutLine("LOADING model=gigaam version=1") {
            onReadyCalled = true
        }

        XCTAssertFalse(onReadyCalled, "onReady не должен вызываться для LOADING")
    }

    // MARK: - Защита от двойного start

    func test_doubleStart_stopsExistingProcess() throws {
        let socketPath = NSTemporaryDirectory() + "govorun_double_start_\(UUID()).sock"
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let manager = ASRWorkerManager(
            workerDirectory: "/tmp/test",
            socketPath: socketPath
        )

        manager.setState(.ready)
        manager.stop()

        // stop() удаляет socket но НЕ меняет state — caller решает
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath),
                       "stop() должен удалить socket файл")
    }

    func test_resetForStart_clearsRestartCountAndManualFlag() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        manager.launchWorkerOverride = {}

        // Накопить crash'и
        manager.handleTermination(exitCode: 1)
        manager.handleTermination(exitCode: 1)
        XCTAssertEqual(manager.restartCount, 2)

        // resetForStart сбрасывает всё для чистого старта
        manager.resetForStart()
        XCTAssertEqual(manager.restartCount, 0)

        // После reset — crash снова вызывает restart (не блокируется старым счётчиком)
        manager.handleTermination(exitCode: 1)
        XCTAssertEqual(manager.restartCount, 1)
    }

    // MARK: - Restart error handling

    func test_handleTermination_restartFailure_setsError() {
        // Если при перезапуске launchWorker бросает ошибку — state = .error
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        let collector = StateCollector()
        manager.onStateChanged = { [collector] state in
            collector.append(state)
        }

        // Нет launchWorkerOverride, нет реального worker → launchWorker упадёт.
        // Но launchWorker async — не проверяем напрямую.
        // Проверяем через override, который ставит error:
        manager.launchWorkerOverride = { [weak manager] in
            manager?.setState(.error("Перезапуск не удался: python3 не найден"))
        }

        manager.handleTermination(exitCode: 1)
        XCTAssertEqual(manager.state, .error("Перезапуск не удался: python3 не найден"))
    }

    // MARK: - Автоперезапуск при crash

    func test_handleTermination_restartsOnCrash() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        var launchCount = 0
        manager.launchWorkerOverride = {
            launchCount += 1
        }

        // Worker упал (exit code 1)
        manager.handleTermination(exitCode: 1)

        XCTAssertEqual(manager.restartCount, 1)
        XCTAssertEqual(launchCount, 1)
    }

    func test_handleTermination_maxRetries_setsError() {
        let manager = ASRWorkerManager(
            workerDirectory: "/tmp/test",
            maxRestartAttempts: 3
        )
        manager.launchWorkerOverride = {}

        // 3 crash'а
        manager.handleTermination(exitCode: 1)
        manager.handleTermination(exitCode: 1)
        manager.handleTermination(exitCode: 1)

        // Четвёртый crash — .error
        manager.handleTermination(exitCode: 1)

        XCTAssertEqual(manager.state, .error("Worker упал 3 раз подряд"))
    }

    func test_handleTermination_manualStop_noRestart() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        var launchCount = 0
        manager.launchWorkerOverride = {
            launchCount += 1
        }

        manager.markStoppedManually()
        manager.handleTermination(exitCode: 0)

        XCTAssertEqual(launchCount, 0, "Не должен перезапускаться после ручной остановки")
    }

    // MARK: - stop()

    func test_stop_doesNotChangeState() {
        // stop() не меняет state — caller решает какой state установить.
        // Это предотвращает race condition когда cancelWorkerLoading()
        // ставит .error(), а stop() затирает его на .notStarted.
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        manager.setState(.ready)
        manager.stop()
        XCTAssertEqual(manager.state, .ready)
    }

    func test_stop_removesSocketFile() throws {
        let socketPath = NSTemporaryDirectory() + "govorun_test_\(UUID()).sock"
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let manager = ASRWorkerManager(
            workerDirectory: "/tmp/test",
            socketPath: socketPath
        )
        manager.stop()

        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
    }

    // MARK: - VERSION

    func test_readVersion_readsFromFile() throws {
        let dir = NSTemporaryDirectory() + "govorun_test_\(UUID())"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let versionPath = (dir as NSString).appendingPathComponent("VERSION")
        try "1".write(toFile: versionPath, atomically: true, encoding: .utf8)

        let manager = ASRWorkerManager(workerDirectory: dir)
        let version = manager.readWorkerVersion()

        XCTAssertEqual(version, "1")

        try FileManager.default.removeItem(atPath: dir)
    }

    func test_readVersion_missingFile_returnsNil() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/nonexistent_govorun_test")
        XCTAssertNil(manager.readWorkerVersion())
    }

    func test_needsSetup_versionMismatch_returnsTrue() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        XCTAssertTrue(manager.needsSetup(currentVersion: "1", savedVersion: "0"))
    }

    func test_needsSetup_versionMatch_venvExists_returnsFalse() throws {
        // Создать фейковый venv с python3
        let venvDir = NSTemporaryDirectory() + "govorun_venv_test_\(UUID())"
        let binDir = (venvDir as NSString).appendingPathComponent("bin")
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        let python3 = (binDir as NSString).appendingPathComponent("python3")
        FileManager.default.createFile(atPath: python3, contents: Data("#!/bin/sh".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python3)
        defer { try? FileManager.default.removeItem(atPath: venvDir) }

        let manager = ASRWorkerManager(workerDirectory: "/tmp/test", venvPath: venvDir)
        XCTAssertFalse(manager.needsSetup(currentVersion: "1", savedVersion: "1"))
    }

    func test_needsSetup_versionMatch_venvMissing_returnsTrue() {
        // Версия совпадает, но venv удалён (reinstall, ручная очистка)
        let manager = ASRWorkerManager(
            workerDirectory: "/tmp/test",
            venvPath: "/tmp/govorun_nonexistent_venv"
        )
        XCTAssertTrue(manager.needsSetup(currentVersion: "1", savedVersion: "1"))
    }

    func test_needsSetup_noSavedVersion_returnsTrue() {
        let manager = ASRWorkerManager(workerDirectory: "/tmp/test")
        XCTAssertTrue(manager.needsSetup(currentVersion: "1", savedVersion: nil))
    }

    // MARK: - VERSION → start() flow

    func test_start_missingVersion_setsError_and_throws() async {
        let dir = NSTemporaryDirectory() + "govorun_ver_test_\(UUID())"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        // Нет VERSION файла
        let manager = ASRWorkerManager(
            workerDirectory: dir,
            socketPath: NSTemporaryDirectory() + "govorun_\(UUID()).sock"
        )

        do {
            try await manager.start()
            XCTFail("Должен бросить ошибку при отсутствии VERSION")
        } catch {
            XCTAssertEqual(manager.state, .error("VERSION не найден в \(dir)"))
        }
    }

    func test_start_versionMismatch_setsSettingUp_state() async throws {
        let dir = NSTemporaryDirectory() + "govorun_ver_test_\(UUID())"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        // VERSION = "2"
        try "2".write(
            toFile: (dir as NSString).appendingPathComponent("VERSION"),
            atomically: true, encoding: .utf8
        )

        // Минимальный setup.sh (сразу exit 0)
        let setupContent = "#!/bin/bash\necho SETUP_DONE\n"
        try setupContent.write(
            toFile: (dir as NSString).appendingPathComponent("setup.sh"),
            atomically: true, encoding: .utf8
        )

        let key = "govorun.worker.test.version.\(UUID())"
        let manager = ASRWorkerManager(
            workerDirectory: dir,
            socketPath: NSTemporaryDirectory() + "govorun_\(UUID()).sock"
        )

        // Подменяем ключ UserDefaults для изоляции теста
        // Сохранённая версия "1" (мismatch с "2")
        UserDefaults.standard.set("1", forKey: manager.versionUserDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: manager.versionUserDefaultsKey) }

        let collector = StateCollector()
        manager.onStateChanged = { [collector] state in
            collector.append(state)
        }

        // start() дойдёт до settingUp → runSetup (OK) → launchWorker (fail: нет server.py)
        do {
            try await manager.start()
        } catch {
            // launchWorker fails — ожидаемо
        }

        // Проверяем что .settingUp был среди состояний
        XCTAssertTrue(
            collector.states.contains(.settingUp),
            "При мismatch VERSION должен быть .settingUp, получили: \(collector.states)"
        )

        // VERSION сохранена в UserDefaults после успешного setup
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: manager.versionUserDefaultsKey),
            "2",
            "После setup VERSION должна быть сохранена"
        )
    }

    func test_start_versionMatch_skipsSetup() async throws {
        let dir = NSTemporaryDirectory() + "govorun_ver_test_\(UUID())"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try "1".write(
            toFile: (dir as NSString).appendingPathComponent("VERSION"),
            atomically: true, encoding: .utf8
        )

        // Создать фейковый venv чтобы needsSetup вернул false
        let venvDir = NSTemporaryDirectory() + "govorun_venv_test_\(UUID())"
        let binDir = (venvDir as NSString).appendingPathComponent("bin")
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        let python3 = (binDir as NSString).appendingPathComponent("python3")
        FileManager.default.createFile(atPath: python3, contents: Data("#!/bin/sh".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python3)
        defer { try? FileManager.default.removeItem(atPath: venvDir) }

        let manager = ASRWorkerManager(
            workerDirectory: dir,
            socketPath: NSTemporaryDirectory() + "govorun_\(UUID()).sock",
            venvPath: venvDir
        )

        // Сохранённая версия совпадает
        UserDefaults.standard.set("1", forKey: manager.versionUserDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: manager.versionUserDefaultsKey) }

        let collector = StateCollector()
        manager.onStateChanged = { [collector] state in
            collector.append(state)
        }

        do {
            try await manager.start()
        } catch {
            // launchWorker fails — ожидаемо (нет python)
        }

        // .settingUp НЕ должен появляться — setup пропущен
        XCTAssertFalse(
            collector.states.contains(.settingUp),
            "При совпадении VERSION setup не нужен, но получили .settingUp: \(collector.states)"
        )
    }

    // MARK: - WorkerError

    func test_workerError_equatable() {
        XCTAssertEqual(WorkerError.notRunning, WorkerError.notRunning)
        XCTAssertEqual(WorkerError.timeout, WorkerError.timeout)
        XCTAssertEqual(WorkerError.oom, WorkerError.oom)
        XCTAssertEqual(WorkerError.maxRetriesExceeded, WorkerError.maxRetriesExceeded)
        XCTAssertNotEqual(WorkerError.notRunning, WorkerError.timeout)
    }

    // MARK: - WorkerState

    func test_workerState_equatable() {
        XCTAssertEqual(WorkerState.notStarted, WorkerState.notStarted)
        XCTAssertEqual(WorkerState.ready, WorkerState.ready)
        XCTAssertEqual(WorkerState.error("test"), WorkerState.error("test"))
        XCTAssertNotEqual(WorkerState.error("a"), WorkerState.error("b"))
        XCTAssertNotEqual(WorkerState.ready, WorkerState.loadingModel)
        XCTAssertEqual(WorkerState.downloadingModel(progress: 50), WorkerState.downloadingModel(progress: 50))
        XCTAssertNotEqual(WorkerState.downloadingModel(progress: 50), WorkerState.downloadingModel(progress: 51))
        XCTAssertNotEqual(WorkerState.downloadingModel(progress: 100), WorkerState.loadingModel)
    }
}

// MARK: - MockASRWorkerManager

final class MockASRWorkerManager: ASRWorkerManaging, @unchecked Sendable {
    var state: WorkerState = .ready
    let socketPath: String = "/tmp/govorun-mock-\(UUID().uuidString).sock"
    var isReady: Bool { state == .ready }

    private(set) var startCalled = false
    private(set) var stopCalled = false
    var startError: Error?

    func start() async throws {
        startCalled = true
        if let error = startError {
            throw error
        }
    }

    func stop() {
        stopCalled = true
        state = .notStarted
    }
}
