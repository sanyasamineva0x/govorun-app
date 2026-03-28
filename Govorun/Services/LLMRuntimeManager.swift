import Foundation
import OSLog

// MARK: - Состояние локального LLM runtime

enum LLMRuntimeState: Equatable {
    case disabled
    case notStarted
    case starting
    case ready
    case error(String)
}

// MARK: - Ошибки

enum LLMRuntimeError: Error, Equatable, LocalizedError {
    case invalidBaseURL
    case unsupportedLocalEndpoint(String)
    case executableNotFound(String)
    case modelNotFound(String)
    case launchFailed(String)
    case processExited(Int32)
    case startupTimedOut
    case healthcheckFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Некорректный URL локального LLM runtime"
        case .unsupportedLocalEndpoint(let message):
            message
        case .executableNotFound:
            "Не найден llama-server для локального LLM runtime"
        case .modelNotFound:
            "Не найдена модель GigaChat для локального LLM runtime"
        case .launchFailed(let message):
            message
        case .processExited(let code):
            "LLM runtime завершился с кодом \(code)"
        case .startupTimedOut:
            "Локальный LLM runtime не успел подняться"
        case .healthcheckFailed(let message):
            message
        }
    }
}

// MARK: - Конфиг локального runtime

struct LocalLLMRuntimeConfiguration: Equatable {
    static let defaultRuntimeBinaryName = "llama-server"
    static let defaultStartupTimeout: TimeInterval = 20.0
    static let defaultHealthcheckInterval: TimeInterval = 0.5
    static let defaultContextSize = 4_096
    static let defaultGPULayers = -1

    let baseURLString: String
    let modelAlias: String
    let modelPath: String
    let runtimeBinaryPath: String
    let startupTimeout: TimeInterval
    let healthcheckInterval: TimeInterval
    let contextSize: Int
    let gpuLayers: Int

    init(
        baseURLString: String = LocalLLMConfiguration.defaultBaseURLString,
        modelAlias: String = LocalLLMConfiguration.defaultModel,
        modelPath: String = "",
        runtimeBinaryPath: String = "",
        startupTimeout: TimeInterval = LocalLLMRuntimeConfiguration.defaultStartupTimeout,
        healthcheckInterval: TimeInterval = LocalLLMRuntimeConfiguration.defaultHealthcheckInterval,
        contextSize: Int = LocalLLMRuntimeConfiguration.defaultContextSize,
        gpuLayers: Int = LocalLLMRuntimeConfiguration.defaultGPULayers
    ) {
        self.baseURLString = baseURLString
        self.modelAlias = modelAlias
        self.modelPath = modelPath
        self.runtimeBinaryPath = runtimeBinaryPath
        self.startupTimeout = max(1, startupTimeout)
        self.healthcheckInterval = max(0.1, healthcheckInterval)
        self.contextSize = max(256, contextSize)
        self.gpuLayers = gpuLayers
    }

    var normalizedBaseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = trimmed.replacingOccurrences(
            of: "/+$",
            with: "",
            options: .regularExpression
        )
        guard let url = URL(string: sanitized), url.scheme != nil, url.host != nil else {
            return nil
        }
        return url
    }

    var normalizedModelAlias: String {
        modelAlias.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedModelPath: String? {
        let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedRuntimeBinaryPath: String? {
        let trimmed = runtimeBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func resolved(
        baseURLString: String = LocalLLMConfiguration.defaultBaseURLString,
        modelAlias: String = LocalLLMConfiguration.defaultModel,
        modelPath: String = "",
        runtimeBinaryPath: String = "",
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LocalLLMRuntimeConfiguration {
        LocalLLMRuntimeConfiguration(
            baseURLString: stringOverride(
                key: "GOVORUN_LLM_BASE_URL",
                fallback: baseURLString,
                environment: environment
            ),
            modelAlias: stringOverride(
                key: "GOVORUN_LLM_MODEL",
                fallback: modelAlias,
                environment: environment
            ),
            modelPath: stringOverride(
                key: "GOVORUN_LLM_MODEL_PATH",
                fallback: modelPath,
                environment: environment
            ),
            runtimeBinaryPath: stringOverride(
                key: "GOVORUN_LLM_RUNTIME_BIN",
                fallback: runtimeBinaryPath,
                environment: environment
            ),
            startupTimeout: doubleOverride(
                key: "GOVORUN_LLM_STARTUP_TIMEOUT",
                fallback: defaultStartupTimeout,
                environment: environment
            ),
            healthcheckInterval: doubleOverride(
                key: "GOVORUN_LLM_HEALTHCHECK_INTERVAL",
                fallback: defaultHealthcheckInterval,
                environment: environment
            ),
            contextSize: intOverride(
                key: "GOVORUN_LLM_CTX_SIZE",
                fallback: defaultContextSize,
                environment: environment
            ),
            gpuLayers: signedIntOverride(
                key: "GOVORUN_LLM_GPU_LAYERS",
                fallback: defaultGPULayers,
                environment: environment
            )
        )
    }

    private static func stringOverride(
        key: String,
        fallback: String,
        environment: [String: String]
    ) -> String {
        let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

    private static func doubleOverride(
        key: String,
        fallback: TimeInterval,
        environment: [String: String]
    ) -> TimeInterval {
        guard let raw = environment[key],
              let value = TimeInterval(raw),
              value > 0
        else {
            return fallback
        }
        return value
    }

    private static func intOverride(
        key: String,
        fallback: Int,
        environment: [String: String]
    ) -> Int {
        guard let raw = environment[key],
              let value = Int(raw),
              value > 0
        else {
            return fallback
        }
        return value
    }

    private static func signedIntOverride(
        key: String,
        fallback: Int,
        environment: [String: String]
    ) -> Int {
        guard let raw = environment[key], let value = Int(raw) else {
            return fallback
        }
        return value
    }
}

// MARK: - Протокол

protocol LLMRuntimeManaging: AnyObject, Sendable {
    var state: LLMRuntimeState { get }
    var isReady: Bool { get }
    var onStateChanged: (@Sendable (LLMRuntimeState) -> Void)? { get set }

    func start() async throws
    func stop()
    func updateConfiguration(_ configuration: LocalLLMRuntimeConfiguration) async throws
}

// MARK: - Параметры запуска

struct LLMRuntimeLaunchRequest: Equatable {
    let executablePath: String
    let arguments: [String]
}

protocol LLMRuntimeProcessControlling: AnyObject, Sendable {
    var isRunning: Bool { get }
    func terminate()
}

private final class FoundationLLMRuntimeProcess: LLMRuntimeProcessControlling, @unchecked Sendable {
    private let process: Process
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe

    init(process: Process, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        process.terminate()
    }
}

// MARK: - Менеджер runtime

final class LLMRuntimeManager: LLMRuntimeManaging, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.govorun.app", category: "LLMRuntimeManager")

    typealias ProcessLauncher = @Sendable (LLMRuntimeLaunchRequest, @escaping @Sendable (Int32) -> Void) throws -> any LLMRuntimeProcessControlling
    typealias HealthcheckProbe = @Sendable (LocalLLMRuntimeConfiguration) async throws -> Void
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    var onStateChanged: (@Sendable (LLMRuntimeState) -> Void)? {
        get { withLock { _onStateChanged } }
        set { withLock { _onStateChanged = newValue } }
    }

    private let lock = NSLock()
    private let launchProcess: ProcessLauncher
    private let probeBackend: HealthcheckProbe
    private let sleep: Sleeper

    private var _state: LLMRuntimeState = .notStarted
    private var _configuration: LocalLLMRuntimeConfiguration
    private var _process: (any LLMRuntimeProcessControlling)?
    private var _isStarting = false
    private var _shouldBeRunning = false
    private var _lastExitCode: Int32?
    private var _onStateChanged: (@Sendable (LLMRuntimeState) -> Void)?
    private var _pendingRestart = false

    init(
        configuration: LocalLLMRuntimeConfiguration = .resolved(),
        launchProcess: @escaping ProcessLauncher = LLMRuntimeManager.liveProcessLauncher,
        probeBackend: @escaping HealthcheckProbe = LLMRuntimeManager.liveHealthcheckProbe,
        sleep: @escaping Sleeper = LLMRuntimeManager.liveSleep
    ) {
        _configuration = configuration
        self.launchProcess = launchProcess
        self.probeBackend = probeBackend
        self.sleep = sleep
    }

    var state: LLMRuntimeState {
        withLock { _state }
    }

    var isReady: Bool {
        state == .ready
    }

    func start() async throws {
        guard beginStart() else { return }
        defer { handleStartFinished() }

        let configuration = currentConfiguration()
        let startMode = try resolveStartMode(for: configuration)

        switch startMode {
        case .disabled:
            terminateCurrentProcess()
            setState(.disabled)
            return
        case .launch(let request):
            if try await reuseExistingProcessIfHealthy(configuration: configuration) {
                return
            }

            setState(.starting)
            let process = try launchProcess(request) { [weak self] status in
                self?.handleProcessExit(status)
            }
            storeProcess(process)

            do {
                try await waitUntilReady(configuration: configuration, process: process)
                clearLastExitCode()
                setState(.ready)
            } catch {
                terminateSpecificProcess(process)
                let message = error.localizedDescription
                setState(.error(message))
                throw error
            }
        }
    }

    func stop() {
        markStoppedManually()
        terminateCurrentProcess()

        let nextState: LLMRuntimeState = switch evaluateEndpoint(currentConfiguration()) {
        case .externalEndpoint:
            .disabled
        case .invalid(let message):
            .error(message)
        case .managed:
            .notStarted
        }

        setState(nextState)
    }

    func updateConfiguration(_ configuration: LocalLLMRuntimeConfiguration) async throws {
        let shouldRestart = replaceConfiguration(configuration)
        terminateCurrentProcess()

        switch evaluateEndpoint(configuration) {
        case .externalEndpoint:
            setState(.disabled)
        case .invalid(let message):
            setState(.error(message))
            throw LLMRuntimeError.unsupportedLocalEndpoint(message)
        case .managed:
            if shouldRestart {
                try await start()
            } else {
                setState(.notStarted)
            }
        }
    }

    // MARK: - Внутренние помощники

    private enum StartMode {
        case disabled
        case launch(LLMRuntimeLaunchRequest)
    }

    private enum EndpointEvaluation {
        case managed(URL)
        case externalEndpoint
        case invalid(String)
    }

    private func resolveStartMode(for configuration: LocalLLMRuntimeConfiguration) throws -> StartMode {
        switch evaluateEndpoint(configuration) {
        case .externalEndpoint:
            return .disabled
        case .invalid(let message):
            throw LLMRuntimeError.unsupportedLocalEndpoint(message)
        case .managed(let baseURL):
            guard let modelPath = try resolveModelPath(configuration) else {
                Self.logger.info("Модель GGUF не найдена — LLM runtime отключён")
                return .disabled
            }

            guard let executablePath = resolveRuntimeBinary(configuration) else {
                throw LLMRuntimeError.executableNotFound(
                    configuration.normalizedRuntimeBinaryPath ?? LocalLLMRuntimeConfiguration.defaultRuntimeBinaryName
                )
            }

            guard let host = baseURL.host else {
                throw LLMRuntimeError.invalidBaseURL
            }

            let port = baseURL.port ?? 8_080
            return .launch(
                LLMRuntimeLaunchRequest(
                    executablePath: executablePath,
                    arguments: [
                        "--host", host,
                        "--port", "\(port)",
                        "--model", modelPath,
                        "--alias", configuration.normalizedModelAlias,
                        "--ctx-size", "\(configuration.contextSize)",
                        "--n-gpu-layers", "\(configuration.gpuLayers)",
                    ]
                )
            )
        }
    }

    private func evaluateEndpoint(_ configuration: LocalLLMRuntimeConfiguration) -> EndpointEvaluation {
        guard let baseURL = configuration.normalizedBaseURL else {
            return .invalid("Некорректный URL локального LLM runtime")
        }

        guard let host = baseURL.host else {
            return .invalid("Некорректный URL локального LLM runtime")
        }

        guard Self.isLocalHost(host) else {
            return .externalEndpoint
        }

        let normalizedPath = baseURL.path.isEmpty ? "/" : baseURL.path
        guard normalizedPath == "/v1" else {
            return .invalid("Для managed LLM runtime base URL должен заканчиваться на /v1")
        }

        return .managed(baseURL)
    }

    private func reuseExistingProcessIfHealthy(configuration: LocalLLMRuntimeConfiguration) async throws -> Bool {
        guard let existingProcess = currentProcess(), existingProcess.isRunning else {
            return false
        }

        do {
            try await probeBackend(configuration)
            setState(.ready)
            return true
        } catch {
            Self.logger.debug("Существующий LLM runtime не прошёл healthcheck, перезапуск: \(String(describing: error), privacy: .public)")
            terminateSpecificProcess(existingProcess)
            clearLastExitCode()
            return false
        }
    }

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

    private func waitUntilReady(
        configuration: LocalLLMRuntimeConfiguration,
        process: any LLMRuntimeProcessControlling
    ) async throws {
        let deadline = Date().addingTimeInterval(configuration.startupTimeout)
        var lastError: Error?

        while Date() < deadline {
            guard process.isRunning else {
                if let lastExitCode = lastExitCode() {
                    throw LLMRuntimeError.processExited(lastExitCode)
                }
                throw LLMRuntimeError.launchFailed("LLM runtime завершился до readiness probe")
            }

            do {
                try await probeBackend(configuration)
                return
            } catch {
                lastError = error
            }

            try await sleep(configuration.healthcheckInterval)
        }

        if let lastError {
            Self.logger.error("LLM runtime healthcheck timed out: \(String(describing: lastError), privacy: .public)")
        }
        throw LLMRuntimeError.startupTimedOut
    }

    private func handleProcessExit(_ status: Int32) {
        let shouldReport = registerProcessExit(status)
        if shouldReport {
            Self.logger.error("LLM runtime process exited unexpectedly: status=\(status)")
            setState(.error("LLM runtime завершился с кодом \(status)"))
        } else {
            Self.logger.debug("LLM runtime process exited (expected): status=\(status)")
        }
    }

    private func currentConfiguration() -> LocalLLMRuntimeConfiguration {
        withLock { _configuration }
    }

    private func currentProcess() -> (any LLMRuntimeProcessControlling)? {
        withLock { _process }
    }

    private func lastExitCode() -> Int32? {
        withLock { _lastExitCode }
    }

    private func clearLastExitCode() {
        withLock { _lastExitCode = nil }
    }

    private func beginStart() -> Bool {
        withLock {
            _shouldBeRunning = true
            guard !_isStarting else {
                _pendingRestart = true
                Self.logger.debug("start() пропущен — уже запускается, перезапуск отложен")
                return false
            }
            _isStarting = true
            return true
        }
    }

    private func handleStartFinished() {
        let needsRestart = withLock {
            _isStarting = false
            let pending = _pendingRestart
            _pendingRestart = false
            return pending
        }

        if needsRestart {
            Task { [weak self] in
                do {
                    try await self?.start()
                } catch {
                    Self.logger.error("Deferred restart failed: \(String(describing: error), privacy: .public)")
                    self?.setState(.error(error.localizedDescription))
                }
            }
        }
    }

    private func markStoppedManually() {
        withLock {
            _shouldBeRunning = false
            _lastExitCode = nil
        }
    }

    private func replaceConfiguration(_ configuration: LocalLLMRuntimeConfiguration) -> Bool {
        withLock {
            let shouldRestart = _shouldBeRunning
            _configuration = configuration
            _lastExitCode = nil
            return shouldRestart
        }
    }

    private func storeProcess(_ process: any LLMRuntimeProcessControlling) {
        withLock {
            _process = process
            _lastExitCode = nil
        }
    }

    private func terminateCurrentProcess() {
        let process = withLock { () -> (any LLMRuntimeProcessControlling)? in
            let process = _process
            _process = nil
            return process
        }
        process?.terminate()
    }

    private func terminateSpecificProcess(_ process: any LLMRuntimeProcessControlling) {
        let shouldTerminate = withLock { () -> Bool in
            guard let current = _process, current === process else { return false }
            _process = nil
            return true
        }

        if shouldTerminate {
            process.terminate()
        }
    }

    private func registerProcessExit(_ status: Int32) -> Bool {
        withLock {
            _lastExitCode = status
            _process = nil
            return _shouldBeRunning && !_isStarting
        }
    }

    private func setState(_ newState: LLMRuntimeState) {
        let callback = withLock {
            _state = newState
            return _onStateChanged
        }
        callback?(newState)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "localhost"
            || normalized == "::1"
            || normalized == "[::1]"
            || normalized.hasPrefix("127.")
    }

    private static func resolveExecutable(_ candidate: String) -> String? {
        if candidate.contains("/") {
            return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
        }

        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let fullPath = (String(directory) as NSString).appendingPathComponent(candidate)
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    private static let liveSleep: Sleeper = { interval in
        let nanoseconds = UInt64(interval * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private static let liveHealthcheckProbe: HealthcheckProbe = { configuration in
        guard let baseURL = configuration.normalizedBaseURL else {
            throw LLMRuntimeError.invalidBaseURL
        }

        var request = URLRequest(url: baseURL.appending(path: "models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMRuntimeError.healthcheckFailed("Локальный endpoint не вернул HTTP-ответ")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LLMRuntimeError.healthcheckFailed("Healthcheck вернул HTTP \(httpResponse.statusCode)")
        }

        let decoded: LLMRuntimeModelsResponse
        do {
            decoded = try JSONDecoder().decode(LLMRuntimeModelsResponse.self, from: data)
        } catch {
            throw LLMRuntimeError.healthcheckFailed("Healthcheck вернул невалидный JSON")
        }

        let ids = decoded.data.map(\.id)
        guard ids.contains(configuration.normalizedModelAlias) else {
            throw LLMRuntimeError.healthcheckFailed(
                "Healthcheck не видит модель \(configuration.normalizedModelAlias)"
            )
        }
    }

    private static let liveProcessLauncher: ProcessLauncher = { request, onTerminate in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.executablePath)
        process.arguments = request.arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let output = String(decoding: data, as: UTF8.self)
            LLMRuntimeManager.logger.debug("llama-server stdout: \(output, privacy: .public)")
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let output = String(decoding: data, as: UTF8.self)
            LLMRuntimeManager.logger.warning("llama-server stderr: \(output, privacy: .public)")
        }

        process.terminationHandler = { proc in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            onTerminate(proc.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw LLMRuntimeError.launchFailed(
                "Не удалось запустить llama-server: \(error.localizedDescription)"
            )
        }

        return FoundationLLMRuntimeProcess(
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )
    }
}

private struct LLMRuntimeModelsResponse: Decodable {
    let data: [LLMRuntimeModelDescriptor]
}

private struct LLMRuntimeModelDescriptor: Decodable {
    let id: String
}
