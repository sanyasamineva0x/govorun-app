import Foundation

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

        guard let binaryURL = resolveRuntimeBinary() else {
            state = .runtimeMissing
            return state
        }

        guard let model = resolveModel() else {
            runtimeBinaryURL = binaryURL
            if case .error = state { return state }
            state = .modelMissing
            return state
        }

        runtimeBinaryURL = binaryURL
        modelURL = model
        state = .installed
        return state
    }

    private func resolveRuntimeBinary() -> URL? {
        if let resourcePath = bundleResourcePath {
            let bundled = (resourcePath as NSString).appendingPathComponent("llama-server")
            if fileChecker.isExecutableFile(atPath: bundled) {
                return URL(fileURLWithPath: bundled)
            }
        }

#if DEBUG
        if let pathBinary = Self.findInPath("llama-server") {
            return URL(fileURLWithPath: pathBinary)
        }
#endif

        return nil
    }

    private func resolveModel() -> URL? {
        if let envPath = ProcessInfo.processInfo.environment["GOVORUN_LLM_MODEL_PATH"],
           !envPath.isEmpty
        {
            return validateModel(atPath: envPath)
        }

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
