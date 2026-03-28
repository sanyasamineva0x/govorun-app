import Foundation
import OSLog

// MARK: - State

enum SuperAssetsState: Equatable {
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

final class DefaultFileChecker: FileChecking, Sendable {
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
    func check(baseURLString: String, modelAlias: String) async -> SuperAssetsState
}

// MARK: - Implementation

final class SuperAssetsManager: SuperAssetsManaging, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.govorun.app", category: "SuperAssetsManager")

    private let fileChecker: FileChecking
    private let bundleHelpersPath: String?
    private let modelsDirectory: String
    private let lock = NSLock()

    private var _state: SuperAssetsState = .unknown
    private var _runtimeBinaryURL: URL?
    private var _modelURL: URL?

    var state: SuperAssetsState {
        lock.lock(); defer { lock.unlock() }; return _state
    }

    var runtimeBinaryURL: URL? {
        lock.lock(); defer { lock.unlock() }; return _runtimeBinaryURL
    }

    var modelURL: URL? {
        lock.lock(); defer { lock.unlock() }; return _modelURL
    }

    init(
        fileChecker: FileChecking = DefaultFileChecker(),
        bundleHelpersPath: String? = Bundle.main.bundlePath + "/Contents/Helpers",
        modelsDirectory: String = NSHomeDirectory() + "/.govorun/models"
    ) {
        self.fileChecker = fileChecker
        self.bundleHelpersPath = bundleHelpersPath
        self.modelsDirectory = modelsDirectory
    }

    func check(baseURLString: String, modelAlias: String) async -> SuperAssetsState {
        Self.logger.info("check: baseURL=\(baseURLString, privacy: .public) modelAlias=\(modelAlias, privacy: .public)")

        lock.lock()
        _state = .checking
        _runtimeBinaryURL = nil
        _modelURL = nil
        lock.unlock()

        // Валидация URL — некорректный непустой URL → ошибка вместо молчаливого fallback
        if URL(string: baseURLString)?.host == nil, !baseURLString.isEmpty {
            Self.logger.error("check: некорректный URL — \(baseURLString, privacy: .public)")
            lock.lock()
            _state = .error("Некорректный URL: \(baseURLString)")
            lock.unlock()
            return state
        }

        if Self.isExternalEndpoint(baseURLString) {
            Self.logger.info("check: external endpoint, assets не требуются")
            lock.lock()
            _state = .installed
            lock.unlock()
            return .installed
        }

        guard let binaryURL = resolveRuntimeBinary() else {
            Self.logger.warning("check: runtime binary не найден → .runtimeMissing")
            lock.lock()
            _state = .runtimeMissing
            lock.unlock()
            return .runtimeMissing
        }

        guard let model = resolveModel(modelAlias: modelAlias) else {
            lock.lock()
            _runtimeBinaryURL = binaryURL
            let current = _state
            if case .error = current {
                lock.unlock()
                Self.logger.error("check: завершён с ошибкой — \(String(describing: current), privacy: .public)")
                return current
            }
            _state = .modelMissing
            lock.unlock()
            Self.logger.warning("check: модель не найдена → .modelMissing")
            return .modelMissing
        }

        lock.lock()
        _runtimeBinaryURL = binaryURL
        _modelURL = model
        _state = .installed
        lock.unlock()
        Self.logger.info("check: все ассеты на месте → .installed")
        return .installed
    }

    private static func isExternalEndpoint(_ baseURLString: String) -> Bool {
        guard let url = URL(string: baseURLString),
              let host = url.host else { return false }
        let normalized = host.lowercased()
        return !(normalized == "localhost"
            || normalized == "::1"
            || normalized == "[::1]"
            || normalized.hasPrefix("127.")
            || normalized == "0.0.0.0")
    }

    private func resolveRuntimeBinary() -> URL? {
        if let helpersPath = bundleHelpersPath {
            let bundled = (helpersPath as NSString).appendingPathComponent("llama-server")
            Self.logger.debug("resolveRuntimeBinary: проверяю bundle helpers — \(bundled, privacy: .public)")
            if fileChecker.isExecutableFile(atPath: bundled) {
                return URL(fileURLWithPath: bundled)
            }
        }

        Self.logger.debug("resolveRuntimeBinary: ищу llama-server в PATH")
        if let pathBinary = findInPath("llama-server") {
            Self.logger.debug("resolveRuntimeBinary: найден в PATH — \(pathBinary, privacy: .public)")
            return URL(fileURLWithPath: pathBinary)
        }

        return nil
    }

    private func resolveModel(modelAlias: String) -> URL? {
        if let envPath = ProcessInfo.processInfo.environment["GOVORUN_LLM_MODEL_PATH"],
           !envPath.isEmpty
        {
            Self.logger.debug("resolveModel: проверяю env GOVORUN_LLM_MODEL_PATH — \(envPath, privacy: .public)")
            return validateModel(atPath: envPath)
        }

        let standardPath = (modelsDirectory as NSString)
            .appendingPathComponent("\(modelAlias).gguf")
        Self.logger.debug("resolveModel: проверяю стандартный путь — \(standardPath, privacy: .public)")
        return validateModel(atPath: standardPath)
    }

    private func validateModel(atPath path: String) -> URL? {
        guard fileChecker.isReadableFile(atPath: path) else { return nil }
        let size = fileChecker.fileSize(atPath: path)
        guard let size else {
            Self.logger.error("validateModel: не удалось получить размер файла — \(path, privacy: .public)")
            lock.lock()
            _state = .error("Не удалось проверить размер файла: \(path)")
            lock.unlock()
            return nil
        }
        guard size > 100_000_000 else {
            Self.logger.error("validateModel: файл слишком маленький (\(size) байт) — \(path, privacy: .public)")
            lock.lock()
            _state = .error("Файл модели слишком маленький: \(path)")
            lock.unlock()
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func findInPath(_ name: String) -> String? {
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for dir in pathEnv.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if fileChecker.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
