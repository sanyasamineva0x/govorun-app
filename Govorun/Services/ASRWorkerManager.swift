import Foundation

// MARK: - WorkerState

enum WorkerState: Equatable, Sendable {
    case notStarted
    case settingUp
    case downloadingModel(progress: Int)
    case loadingModel
    case ready
    case error(String)
}

// MARK: - WorkerError

enum WorkerError: Error, Equatable, LocalizedError {
    case notRunning
    case loadingModel
    case timeout
    case oom
    case fileNotFound(String)
    case internalError(String)
    case connectionRefused
    case invalidResponse(String)
    case maxRetriesExceeded
    case pythonNotFound
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: "Распознавание недоступно"
        case .loadingModel: "Загружаю модель…"
        case .timeout: "Попробуйте ещё раз"
        case .oom: "Мало памяти — закройте приложения"
        case .fileNotFound: "Ошибка распознавания"
        case .internalError: "Ошибка распознавания"
        case .connectionRefused: "Распознавание недоступно"
        case .invalidResponse: "Ошибка распознавания"
        case .maxRetriesExceeded: "Перезапустите Говорун"
        case .pythonNotFound: "Внутренняя ошибка. Переустановите Говоруна"
        case .setupFailed: "Не смог подготовиться…"
        }
    }
}

// MARK: - Protocol

protocol ASRWorkerManaging: AnyObject {
    var state: WorkerState { get }
    var socketPath: String { get }
    var isReady: Bool { get }
    func start() async throws
    func stop()
}

// MARK: - ASRWorkerManager

final class ASRWorkerManager: ASRWorkerManaging, @unchecked Sendable {

    let socketPath: String
    let venvPath: String
    let maxRestartAttempts: Int

    /// Callback при изменении состояния (вызывается с любого потока)
    var onStateChanged: (@Sendable (WorkerState) -> Void)?

    private let workerDirectory: String
    private let lock = NSLock()
    private var _state: WorkerState = .notStarted
    private var _process: Process?
    private var _setupProcess: Process?
    private var _restartCount: Int = 0
    private var _isStoppedManually: Bool = false
    private var _isStarting: Bool = false
    private var _launchWorkerOverride: (() -> Void)?
    private var _launchAttemptId: UUID = UUID()

    let versionUserDefaultsKey = "govorun.worker.installedVersion"

    // MARK: - Init

    init(
        workerDirectory: String? = nil,
        socketPath: String? = nil,
        venvPath: String? = nil,
        maxRestartAttempts: Int = 3
    ) {
        if let dir = workerDirectory {
            self.workerDirectory = dir
        } else if let resourcePath = Bundle.main.resourcePath {
            // Внутри app bundle: Contents/Resources/worker/
            self.workerDirectory = (resourcePath as NSString)
                .appendingPathComponent("worker")
        } else {
            // Fallback: рядом с .app
            let bundlePath = Bundle.main.bundlePath
            self.workerDirectory = (bundlePath as NSString)
                .deletingLastPathComponent
                .appending("/worker")
        }
        self.socketPath = socketPath
            ?? NSString("~/.govorun/worker.sock").expandingTildeInPath
        self.venvPath = venvPath
            ?? NSString("~/.govorun/venv").expandingTildeInPath
        self.maxRestartAttempts = maxRestartAttempts
    }

    // MARK: - Public API

    var state: WorkerState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    var isReady: Bool { state == .ready }

    /// Переопределение запуска worker для тестов (потокобезопасно)
    var launchWorkerOverride: (() -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _launchWorkerOverride
        }
        set {
            lock.lock()
            _launchWorkerOverride = newValue
            lock.unlock()
        }
    }

    var restartCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _restartCount
    }

    /// Текущий ID попытки запуска (для валидации таймаутов/callbacks)
    var launchAttemptId: UUID {
        lock.lock()
        defer { lock.unlock() }
        return _launchAttemptId
    }

    func start() async throws {
        // Guard: только один start() одновременно
        lock.lock()
        guard !_isStarting else {
            lock.unlock()
            return
        }
        _isStarting = true
        let existingProcess = _process
        lock.unlock()

        defer {
            lock.lock()
            _isStarting = false
            lock.unlock()
        }

        if let existingProcess, existingProcess.isRunning {
            stop()
        }

        resetForStart()

        // 1. Прочитать VERSION
        guard let version = readWorkerVersion() else {
            let msg = "VERSION не найден в \(workerDirectory)"
            setState(.error(msg))
            throw WorkerError.setupFailed(msg)
        }

        // 2. Если версия изменилась — запустить setup.sh
        let savedVersion = UserDefaults.standard.string(forKey: versionUserDefaultsKey)
        if needsSetup(currentVersion: version, savedVersion: savedVersion) {
            setState(.settingUp)
            try await runSetup()
            UserDefaults.standard.set(version, forKey: versionUserDefaultsKey)
        }

        // 3. Запустить worker
        try await launchWorker()
    }

    func stop() {
        lock.lock()
        _isStoppedManually = true
        _launchAttemptId = UUID() // инвалидировать все таймауты/callbacks текущей попытки
        let process = _process
        _process = nil
        let setupProcess = _setupProcess
        _setupProcess = nil
        lock.unlock()

        if let setupProcess, setupProcess.isRunning {
            setupProcess.terminate()
        }
        if let process, process.isRunning {
            process.terminate()
        }

        try? FileManager.default.removeItem(atPath: socketPath)
    }

    // MARK: - Testable helpers

    /// Прочитать VERSION файл из workerDirectory
    func readWorkerVersion() -> String? {
        let path = (workerDirectory as NSString).appendingPathComponent("VERSION")
        guard let data = FileManager.default.contents(atPath: path),
              let version = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else {
            return nil
        }
        return version
    }

    /// Нужна ли переустановка venv
    /// Проверяет и версию, и реальное наличие venv на диске.
    /// UserDefaults может пережить uninstall/reinstall — venv при этом исчезает.
    func needsSetup(currentVersion: String, savedVersion: String?) -> Bool {
        if savedVersion != currentVersion {
            return true
        }
        // Версия совпала, но venv мог быть удалён (reinstall, ручная очистка)
        let venvPython = (venvPath as NSString).appendingPathComponent("bin/python3")
        return !FileManager.default.isExecutableFile(atPath: venvPython)
    }

    /// Установить состояние (internal для тестов)
    func setState(_ newState: WorkerState) {
        lock.lock()
        _state = newState
        lock.unlock()
        onStateChanged?(newState)
    }

    /// Сбросить счётчики для нового запуска
    func resetForStart() {
        lock.lock()
        _isStoppedManually = false
        _restartCount = 0
        _launchAttemptId = UUID()
        lock.unlock()
    }

    /// Пометить как остановленный вручную (для тестов)
    func markStoppedManually() {
        lock.lock()
        _isStoppedManually = true
        lock.unlock()
    }

    /// Парсинг строки из stdout worker
    func handleStdoutLine(_ line: String, onReady: (() -> Void)? = nil) {
        if line.hasPrefix("DOWNLOADING") {
            // "DOWNLOADING 45%" → .downloadingModel(progress: 45)
            let parts = line.split(separator: " ")
            if parts.count >= 2,
               let pct = Int(parts[1].replacingOccurrences(of: "%", with: "")) {
                setState(.downloadingModel(progress: min(pct, 100)))
            }
        } else if line.hasPrefix("LOADING") {
            setState(.loadingModel)
        } else if line == "READY" {
            setState(.ready)
            onReady?()
        }
        // LOADED — промежуточный, не меняем состояние
    }

    /// Обработка завершения процесса (crash или штатное)
    func handleTermination(exitCode: Int32) {
        lock.lock()
        let wasManual = _isStoppedManually
        let count = _restartCount
        let attemptId = _launchAttemptId
        lock.unlock()

        guard !wasManual else { return }

        if count < maxRestartAttempts {
            lock.lock()
            _restartCount += 1
            let override = _launchWorkerOverride
            lock.unlock()

            if let override {
                print("[Worker] Упал (exit \(exitCode)), перезапуск \(count + 1)/\(maxRestartAttempts)")
                override()
            } else {
                Task { [weak self] in
                    guard let self else { return }
                    guard self.launchAttemptId == attemptId else {
                        print("[Worker] Перезапуск пропущен: attempt инвалидирован")
                        return
                    }
                    print("[Worker] Упал (exit \(exitCode)), перезапуск \(count + 1)/\(maxRestartAttempts)")
                    do {
                        try await self.launchWorker()
                    } catch {
                        self.setState(.error("Перезапуск не удался: \(error.localizedDescription)"))
                    }
                }
            }
        } else {
            setState(.error("Worker упал \(maxRestartAttempts) раз подряд"))
        }
    }

    // MARK: - Private

    private func runSetup() async throws {
        let setupPath = (workerDirectory as NSString).appendingPathComponent("setup.sh")

        guard FileManager.default.isReadableFile(atPath: setupPath) else {
            throw WorkerError.setupFailed("setup.sh не найден: \(setupPath)")
        }

        let pythonForSetup = findPythonPath() ?? "python3"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [setupPath, pythonForSetup]
        process.currentDirectoryURL = URL(fileURLWithPath: workerDirectory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Сохраняем setup process для отмены через stop()
        lock.lock()
        _setupProcess = process
        lock.unlock()

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            var resumed = false
            let resumeLock = NSLock()

            func resumeOnce(with result: Result<Void, Error>) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            // Дренировать pipe асинхронно — предотвращает deadlock при шумном pip install.
            // Pipe buffer macOS = 64KB, pip может написать больше → write блокируется →
            // процесс висит → terminationHandler не вызывается → deadlock.
            final class OutputBuffer: @unchecked Sendable {
                private let lock = NSLock()
                private var data = Data()
                func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
                func string() -> String { lock.lock(); defer { lock.unlock() }; return String(data: data, encoding: .utf8) ?? "" }
            }
            let outputBuffer = OutputBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                outputBuffer.append(data)
            }

            process.terminationHandler = { [weak self] proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                guard let self else {
                    resumeOnce(with: .failure(WorkerError.setupFailed("Manager deallocated")))
                    return
                }
                // Очистить ссылку на setup process
                self.lock.lock()
                if self._setupProcess === proc { self._setupProcess = nil }
                self.lock.unlock()

                if proc.terminationStatus == 0 {
                    resumeOnce(with: .success(()))
                } else if proc.terminationStatus == 15 /* SIGTERM */ {
                    resumeOnce(with: .failure(WorkerError.setupFailed("Setup отменён")))
                } else {
                    resumeOnce(with: .failure(WorkerError.setupFailed(
                        "setup.sh завершился с кодом \(proc.terminationStatus): \(outputBuffer.string())"
                    )))
                }
            }

            do {
                try process.run()
            } catch {
                if let self {
                    self.lock.lock()
                    self._setupProcess = nil
                    self.lock.unlock()
                }
                pipe.fileHandleForReading.readabilityHandler = nil
                resumeOnce(with: .failure(WorkerError.setupFailed(
                    "Не удалось запустить setup.sh: \(error.localizedDescription)"
                )))
            }
        }
    }

    /// Найти Python по приоритету: embedded → venv → системный
    func findPythonPath() -> String? {
        // 1. Embedded Python.framework в app bundle
        if let frameworksPath = Bundle.main.privateFrameworksPath {
            let embeddedPython = (frameworksPath as NSString)
                .appendingPathComponent("Python.framework/Versions/3.13/bin/python3")
            if FileManager.default.isExecutableFile(atPath: embeddedPython) {
                return embeddedPython
            }
        }

        // 2. Persistent venv
        let govorunVenvPython = (venvPath as NSString).appendingPathComponent("bin/python3")
        if FileManager.default.isExecutableFile(atPath: govorunVenvPython) {
            return govorunVenvPython
        }

        // 3. Bundle-local venv
        let bundleVenvPython = (workerDirectory as NSString).appendingPathComponent(".venv/bin/python3")
        if FileManager.default.isExecutableFile(atPath: bundleVenvPython) {
            return bundleVenvPython
        }

        // 4. Системный Python
        for path in [
            "/usr/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3"
        ] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func launchWorker() async throws {
        // Удалить старый socket
        try? FileManager.default.removeItem(atPath: socketPath)

        // Создать директорию для socket (700)
        let socketDir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: socketDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let serverPath = (workerDirectory as NSString).appendingPathComponent("server.py")

        guard let pythonPath = findPythonPath() else {
            let msg = "python3 не найден"
            setState(.error(msg))
            throw WorkerError.pythonNotFound
        }

        guard FileManager.default.isReadableFile(atPath: serverPath) else {
            let msg = "server.py не найден: \(serverPath)"
            setState(.error(msg))
            throw WorkerError.setupFailed(msg)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [serverPath]
        process.currentDirectoryURL = URL(fileURLWithPath: workerDirectory)

        // venv Python уже знает свои site-packages.
        // PYTHONPATH нужен только если worker запускается НЕ из venv (embedded/системный Python).
        let isInsideVenv = pythonPath.contains("/venv/bin/") || pythonPath.contains("/.venv/bin/")
        if !isInsideVenv {
            var env = ProcessInfo.processInfo.environment
            let venvLib = (venvPath as NSString).appendingPathComponent("lib")
            do {
                let versions = try FileManager.default.contentsOfDirectory(atPath: venvLib)
                if let pyDir = versions.filter({ $0.hasPrefix("python") }).sorted().last {
                    let sitePackages = (venvLib as NSString).appendingPathComponent("\(pyDir)/site-packages")
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: sitePackages, isDirectory: &isDir), isDir.boolValue {
                        env["PYTHONPATH"] = sitePackages
                    } else {
                        print("[Govorun] WARNING: site-packages не найден: \(sitePackages)")
                    }
                } else {
                    print("[Govorun] WARNING: python* директория не найдена в \(venvLib)")
                }
            } catch {
                print("[Govorun] WARNING: не удалось прочитать \(venvLib): \(error.localizedDescription)")
            }
            process.environment = env
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        lock.lock()
        _process = process
        lock.unlock()

        // Обработчик завершения — автоперезапуск
        process.terminationHandler = { [weak self] proc in
            self?.handleTermination(exitCode: proc.terminationStatus)
        }

        // Запомнить attemptId для валидации таймаутов
        lock.lock()
        let attemptId = _launchAttemptId
        lock.unlock()

        // Ожидание READY из stdout
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(throwing: WorkerError.notRunning)
                return
            }

            var resumed = false
            let resumeLock = NSLock()

            func resumeOnce(with result: Result<Void, Error>) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            // Adaptive timeout: перезапускается при каждом отчёте прогресса.
            // Детектирует зависания (нет активности N секунд), а не медленность.
            let timeoutLock = NSLock()
            var currentTimeoutWork: DispatchWorkItem?

            func scheduleTimeout(_ seconds: TimeInterval) {
                timeoutLock.lock()
                currentTimeoutWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    // Валидация: таймаут принадлежит текущей попытке запуска
                    guard self.launchAttemptId == attemptId else { return }
                    // Пометить как остановленный — предотвратить zombie restart в handleTermination
                    self.markStoppedManually()
                    self.setState(.error("Таймаут загрузки модели"))
                    resumeOnce(with: .failure(WorkerError.timeout))
                }
                currentTimeoutWork = work
                timeoutLock.unlock()
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: work)
            }

            func cancelTimeout() {
                timeoutLock.lock()
                currentTimeoutWork?.cancel()
                currentTimeoutWork = nil
                timeoutLock.unlock()
            }

            // Парсинг stdout
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let output = String(data: data, encoding: .utf8) else { return }

                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }

                    // Перезапуск таймаута при активности worker'а
                    if trimmed.hasPrefix("DOWNLOADING") {
                        scheduleTimeout(120) // скачивание: 120с без прогресса = зависание
                    } else if trimmed.hasPrefix("LOADING") || trimmed.hasPrefix("LOADED") {
                        scheduleTimeout(120) // загрузка модели в память
                    }

                    self?.handleStdoutLine(trimmed) {
                        cancelTimeout()
                        resumeOnce(with: .success(()))
                    }
                }
            }

            // Логирование stderr
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let output = String(data: data, encoding: .utf8) else { return }
                print("[Worker stderr] \(output)", terminator: "")
            }

            do {
                try process.run()
                self.setState(.loadingModel)
            } catch {
                cancelTimeout()
                let msg = "Не удалось запустить worker: \(error.localizedDescription)"
                self.setState(.error(msg))
                resumeOnce(with: .failure(WorkerError.setupFailed(msg)))
                return
            }

            // Начальный таймаут — 30с покрывает случай когда модель уже в кэше
            scheduleTimeout(30)
        }
    }
}
