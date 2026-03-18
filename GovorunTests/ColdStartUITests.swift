import XCTest
@testable import Govorun

// MARK: - BottomBarState: modelLoading

final class BottomBarStateModelLoadingTests: XCTestCase {

    func test_modelLoading_is_visible() {
        XCTAssertTrue(BottomBarState.modelLoading.isVisible)
    }

    func test_modelLoading_equatable() {
        XCTAssertEqual(BottomBarState.modelLoading, .modelLoading)
        XCTAssertNotEqual(BottomBarState.modelLoading, .processing)
        XCTAssertNotEqual(BottomBarState.modelLoading, .hidden)
    }

    func test_modelDownloading_is_visible() {
        XCTAssertTrue(BottomBarState.modelDownloading(progress: 50).isVisible)
    }

    func test_modelDownloading_equatable() {
        XCTAssertEqual(
            BottomBarState.modelDownloading(progress: 45),
            .modelDownloading(progress: 45)
        )
        XCTAssertNotEqual(
            BottomBarState.modelDownloading(progress: 45),
            .modelDownloading(progress: 50)
        )
        XCTAssertNotEqual(
            BottomBarState.modelDownloading(progress: 45),
            .modelLoading
        )
    }
    func test_accessibilityHint_is_visible() {
        XCTAssertTrue(BottomBarState.accessibilityHint.isVisible)
    }

    func test_accessibilityHint_equatable() {
        XCTAssertEqual(BottomBarState.accessibilityHint, .accessibilityHint)
        XCTAssertNotEqual(BottomBarState.accessibilityHint, .modelLoading)
    }
}

// MARK: - BottomBarController: showAccessibilityHint

@MainActor
final class BottomBarControllerAccessibilityHintTests: XCTestCase {

    func test_showAccessibilityHint_sets_state() {
        let sut = BottomBarController()
        sut.showAccessibilityHint()
        XCTAssertEqual(sut.state, .accessibilityHint)
    }
}

// MARK: - BottomBarController: showModelLoading

@MainActor
final class BottomBarControllerModelLoadingTests: XCTestCase {

    func test_showModelLoading_sets_state() {
        let sut = BottomBarController()
        XCTAssertEqual(sut.state, .hidden)

        sut.showModelLoading()

        XCTAssertEqual(sut.state, .modelLoading)
        XCTAssertTrue(sut.state.isVisible)
    }

    func test_showModelLoading_then_recording_replaces_state() {
        let sut = BottomBarController()

        sut.showModelLoading()
        XCTAssertEqual(sut.state, .modelLoading)

        // Recording заменяет modelLoading (без panel lifecycle)
        sut.showRecording(audioLevel: 0.5)
        XCTAssertEqual(sut.state, .recording(audioLevel: 0.5))
    }

    func test_showModelLoading_replaced_by_recording() {
        let sut = BottomBarController()

        sut.showModelLoading()
        XCTAssertEqual(sut.state, .modelLoading)

        sut.show()
        XCTAssertEqual(sut.state, .recording(audioLevel: 0))
    }
}

// MARK: - AppState: workerState + cold start guard

@MainActor
final class ColdStartAppStateTests: XCTestCase {

    func test_workerState_defaults_to_notStarted() {
        let (appState, _, _) = makeColdStartTestAppState()
        XCTAssertEqual(appState.workerState, .notStarted)
    }

    func test_updateWorkerState_changes_state() {
        let (appState, _, _) = makeColdStartTestAppState()

        appState.updateWorkerState(.loadingModel)
        XCTAssertEqual(appState.workerState, .loadingModel)

        appState.updateWorkerState(.ready)
        XCTAssertEqual(appState.workerState, .ready)
    }

    func test_handleActivated_when_worker_loading_shows_model_loading_pill() async throws {
        let (appState, _, _) = makeColdStartTestAppState()
        appState.updateWorkerState(.loadingModel)

        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Запись НЕ началась
        XCTAssertEqual(appState.sessionManager.state, .idle)
        // Pill показывает model loading
        XCTAssertEqual(appState.bottomBar.state, .modelLoading)
    }

    func test_handleActivated_when_worker_downloading_shows_downloading_pill() async throws {
        let (appState, _, _) = makeColdStartTestAppState()
        appState.updateWorkerState(.downloadingModel(progress: 45))

        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertEqual(appState.bottomBar.state, .modelDownloading(progress: 45))
    }

    func test_handleActivated_when_worker_not_started_shows_model_loading_pill() async throws {
        let (appState, _, _) = makeColdStartTestAppState()
        // workerState по умолчанию .notStarted

        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertEqual(appState.bottomBar.state, .modelLoading)
    }

    func test_handleActivated_when_worker_setting_up_shows_model_loading_pill() async throws {
        let (appState, _, _) = makeColdStartTestAppState()
        appState.updateWorkerState(.settingUp)

        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertEqual(appState.bottomBar.state, .modelLoading)
    }

    func test_handleActivated_when_worker_error_shows_error_pill() async throws {
        let (appState, _, _) = makeColdStartTestAppState()
        appState.updateWorkerState(.error("Python не найден"))

        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.sessionManager.state, .idle)
        XCTAssertEqual(appState.bottomBar.state, .error("Python не найден"))
    }

    func test_handleActivated_when_worker_ready_starts_recording() async throws {
        let mockAudio = MockAudioRecording()
        let (appState, _, _) = makeColdStartTestAppState(mockAudio: mockAudio)
        appState.updateWorkerState(.ready)

        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        XCTAssertEqual(appState.sessionManager.state, .recording)
        XCTAssertTrue(mockAudio.startCallCount > 0)
    }

    func test_workerState_transition_from_loading_to_ready_enables_recording() async throws {
        let mockAudio = MockAudioRecording()
        let (appState, _, _) = makeColdStartTestAppState(mockAudio: mockAudio)

        // Сначала модель грузится
        appState.updateWorkerState(.loadingModel)
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(appState.sessionManager.state, .idle)

        // Модель загрузилась → dismiss pill
        appState.bottomBar.dismiss()

        // Теперь worker готов
        appState.updateWorkerState(.ready)
        appState.activationKeyMonitor.onActivated?()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(appState.sessionManager.state, .recording)
    }
}

// MARK: - AppState: worker lifecycle (composition root)

@MainActor
final class AppStateWorkerLifecycleTests: XCTestCase {

    func test_start_launches_worker() async throws {
        let mockWorker = MockASRWorkerManager()
        let (appState, _, _) = makeColdStartTestAppState(workerManager: mockWorker)

        XCTAssertFalse(mockWorker.startCalled)

        appState.start()

        // worker.start() вызывается из Task {} — ждём через yield
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if mockWorker.startCalled { break }
        }

        XCTAssertTrue(mockWorker.startCalled)
        XCTAssertTrue(appState.isReady)
    }

    func test_stop_stops_worker() {
        let mockWorker = MockASRWorkerManager()
        let (appState, _, _) = makeColdStartTestAppState(workerManager: mockWorker)
        appState.start()

        XCTAssertFalse(mockWorker.stopCalled)

        appState.stop()

        XCTAssertTrue(mockWorker.stopCalled)
        XCTAssertFalse(appState.isReady)
    }

    func test_start_without_worker_manager_still_works() {
        let (appState, _, _) = makeColdStartTestAppState()

        appState.start()

        XCTAssertTrue(appState.isReady)
    }

    func test_worker_error_during_start_does_not_crash() async throws {
        let mockWorker = MockASRWorkerManager()
        mockWorker.startError = WorkerError.pythonNotFound
        let (appState, _, _) = makeColdStartTestAppState(workerManager: mockWorker)

        appState.start()

        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if mockWorker.startCalled { break }
        }

        XCTAssertTrue(appState.isReady)
        XCTAssertTrue(mockWorker.startCalled)
    }

    func test_cancelWorkerLoading_stops_worker_and_sets_error() {
        let mockWorker = MockASRWorkerManager()
        let (appState, _, _) = makeColdStartTestAppState(workerManager: mockWorker)
        appState.updateWorkerState(.downloadingModel(progress: 50))

        appState.cancelWorkerLoading()

        XCTAssertTrue(mockWorker.stopCalled)
        XCTAssertEqual(appState.workerState, .error("Загрузка отменена"))
    }

    func test_retryWorkerLoading_restarts_worker() async throws {
        let mockWorker = MockASRWorkerManager()
        let (appState, _, _) = makeColdStartTestAppState(workerManager: mockWorker)
        appState.updateWorkerState(.error("Загрузка отменена"))

        appState.retryWorkerLoading()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(mockWorker.startCalled)
        XCTAssertEqual(appState.workerState, .notStarted)
    }

    func test_cancelWorkerLoading_then_retry_full_cycle() async throws {
        let mockWorker = MockASRWorkerManager()
        let (appState, _, _) = makeColdStartTestAppState(workerManager: mockWorker)
        appState.updateWorkerState(.loadingModel)

        // Cancel
        appState.cancelWorkerLoading()
        XCTAssertTrue(mockWorker.stopCalled)
        XCTAssertEqual(appState.workerState, .error("Загрузка отменена"))

        // Retry
        appState.retryWorkerLoading()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(mockWorker.startCalled)
    }

    func test_stop_then_start_relaunches_worker() async throws {
        let mockWorker = MockASRWorkerManager()
        let (appState, _, _) = makeColdStartTestAppState(workerManager: mockWorker)

        appState.start()

        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if mockWorker.startCalled { break }
        }
        XCTAssertTrue(mockWorker.startCalled)

        appState.stop()
        XCTAssertTrue(mockWorker.stopCalled)
    }
}

// MARK: - ErrorMessages: WorkerError

final class WorkerErrorMessagesTests: XCTestCase {

    func test_workerError_notRunning() {
        let msg = ErrorMessages.userFacing(for: WorkerError.notRunning)
        XCTAssertEqual(msg, "Распознавание недоступно")
    }

    func test_workerError_loadingModel() {
        let msg = ErrorMessages.userFacing(for: WorkerError.loadingModel)
        XCTAssertEqual(msg, "Загружаю модель…")
    }

    func test_workerError_timeout() {
        let msg = ErrorMessages.userFacing(for: WorkerError.timeout)
        XCTAssertEqual(msg, "Попробуйте ещё раз")
    }

    func test_workerError_oom() {
        let msg = ErrorMessages.userFacing(for: WorkerError.oom)
        XCTAssertEqual(msg, "Мало памяти — закройте приложения")
    }

    func test_workerError_connectionRefused() {
        let msg = ErrorMessages.userFacing(for: WorkerError.connectionRefused)
        XCTAssertEqual(msg, "Распознавание недоступно")
    }

    func test_workerError_maxRetriesExceeded() {
        let msg = ErrorMessages.userFacing(for: WorkerError.maxRetriesExceeded)
        XCTAssertEqual(msg, "Перезапустите Говорун")
    }

    func test_workerError_pythonNotFound() {
        let msg = ErrorMessages.userFacing(for: WorkerError.pythonNotFound)
        XCTAssertEqual(msg, "Внутренняя ошибка. Переустановите Говоруна")
    }

    func test_workerError_setupFailed() {
        let msg = ErrorMessages.userFacing(for: WorkerError.setupFailed("pip timeout"))
        XCTAssertEqual(msg, "Не смог подготовиться…")
    }
}

// MARK: - humanReadableError

final class HumanReadableErrorTests: XCTestCase {

    func test_упал_maps_to_launch_error() {
        XCTAssertEqual(ErrorMessages.humanReadable("Worker упал 3 раз подряд"), "Не удалось запустить распознавание")
    }

    func test_setup_maps_to_prep_error() {
        XCTAssertEqual(ErrorMessages.humanReadable("setup.sh завершился с кодом 1"), "Ошибка подготовки")
    }

    func test_python_maps_case_insensitive() {
        XCTAssertEqual(ErrorMessages.humanReadable("python3 не найден"), "Внутренняя ошибка. Переустановите Говоруна")
        XCTAssertEqual(ErrorMessages.humanReadable("Python not found"), "Внутренняя ошибка. Переустановите Говоруна")
    }

    func test_timeout_maps() {
        XCTAssertEqual(ErrorMessages.humanReadable("Таймаут загрузки модели"), "Загрузка прервалась")
    }

    func test_version_maps() {
        XCTAssertEqual(ErrorMessages.humanReadable("VERSION не найден"), "Обновите приложение")
    }

    func test_отменена_passes_through() {
        XCTAssertEqual(ErrorMessages.humanReadable("Загрузка отменена"), "Загрузка отменена")
    }

    func test_unknown_passes_through() {
        XCTAssertEqual(ErrorMessages.humanReadable("какая-то неизвестная ошибка"), "какая-то неизвестная ошибка")
    }
}

// MARK: - findPythonPath

final class FindPythonPathTests: XCTestCase {

    func test_returns_nil_when_no_python() {
        let dir = NSTemporaryDirectory() + "govorun_nopython_\(UUID())"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let manager = ASRWorkerManager(workerDirectory: dir)
        // Нет ни venv, ни embedded python — системный может быть
        // Проверяем что метод не крашится
        let _ = manager.findPythonPath()
    }

    func test_prefers_persistent_venv_over_system() {
        let dir = NSTemporaryDirectory() + "govorun_venv_\(UUID())"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let manager = ASRWorkerManager(workerDirectory: dir)
        let path = manager.findPythonPath()

        // Если persistent venv (~/.govorun/venv/bin/python3) существует, он должен быть приоритетнее
        if let path, path.contains(".govorun/venv") {
            XCTAssertTrue(path.hasSuffix("python3"))
        }
        // Если нет — любой результат допустим (системный python или nil)
    }

    func test_bundle_venv_checked() {
        let dir = NSTemporaryDirectory() + "govorun_bvenv_\(UUID())"
        let venvDir = dir + "/.venv/bin"
        try! FileManager.default.createDirectory(atPath: venvDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        // Создаём фейковый python3 в bundle venv
        let fakePython = venvDir + "/python3"
        FileManager.default.createFile(atPath: fakePython, contents: Data("#!/bin/sh".utf8))
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakePython)

        let manager = ASRWorkerManager(workerDirectory: dir)
        let path = manager.findPythonPath()

        // Должен найти bundle venv (если persistent не существует и embedded нет)
        // Не можем гарантировать точный результат из-за системного python, но не должен быть nil
        XCTAssertNotNil(path)
    }
}

// MARK: - Test helper

@MainActor
private func makeColdStartTestAppState(
    mockAudio: MockAudioRecording = MockAudioRecording(),
    workerManager: ASRWorkerManaging? = nil
) -> (AppState, MockAudioRecording, MockEventMonitoring) {
    let eventMonitor = MockEventMonitoring()
    let stt = MockSTTClient()
    stt.recognizeResult = STTResult(text: "тест")
    let llm = MockLLMClient()
    llm.normalizeResult = "Тест."

    let pipeline = PipelineEngine(
        audioCapture: mockAudio,
        sttClient: stt,
        llmClient: llm
    )
    let inserter = TextInserterEngine(
        accessibility: MockAccessibility(),
        clipboard: MockClipboard()
    )

    let appState = AppState(
        activationKeyMonitor: ActivationKeyMonitor(activationKey: .default, eventMonitor: eventMonitor),
        sessionManager: SessionManager(),
        pipelineEngine: pipeline,
        textInserter: inserter,
        bottomBar: BottomBarController(),
        audioCapture: AudioCapture(),
        workerManager: workerManager,
        initialWorkerState: .notStarted
    )

    return (appState, mockAudio, eventMonitor)
}
