import Foundation

// MARK: - DownloadState

enum ModelDownloadState: Equatable {
    case idle
    case notDownloaded
    case downloaded
    case error(String)
}

// MARK: - ModelManager

/// Управление моделью GigaAM-v3 e2e_rnnt (ONNX).
///
/// Модель скачивается Python worker'ом через onnx-asr (huggingface-hub).
/// ModelManager проверяет наличие файлов в кэше, считает размер, позволяет удалить.
///
/// Кэш: ~/.cache/huggingface/hub/models--istupakov--gigaam-v3-onnx/
@MainActor
final class ModelManager: ObservableObject {

    @Published private(set) var downloadState: ModelDownloadState = .idle
    @Published private(set) var modelSizeBytes: Int64 = 0

    private let modelCacheDir: String
    private let fileManager: FileManager

    /// Файлы, необходимые для работы GigaAM-v3 e2e_rnnt
    static let expectedFiles = [
        "v3_e2e_rnnt_encoder.onnx",
        "v3_e2e_rnnt_decoder.onnx",
        "v3_e2e_rnnt_joint.onnx",
    ]

    static var defaultModelCacheDir: String {
        NSString("~/.cache/huggingface/hub/models--istupakov--gigaam-v3-onnx")
            .expandingTildeInPath
    }

    init(
        modelCacheDir: String? = nil,
        fileManager: FileManager = .default
    ) {
        self.modelCacheDir = modelCacheDir ?? Self.defaultModelCacheDir
        self.fileManager = fileManager
    }

    // MARK: - Public API

    var isModelDownloaded: Bool {
        downloadState == .downloaded
    }

    /// Форматированный размер модели для UI
    var formattedSize: String {
        guard modelSizeBytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: modelSizeBytes, countStyle: .file)
    }

    /// Проверить наличие модели в кэше huggingface-hub
    func checkModelStatus() {
        guard fileManager.fileExists(atPath: modelCacheDir) else {
            downloadState = .notDownloaded
            modelSizeBytes = 0
            return
        }

        guard let snapshotPath = findLatestSnapshot() else {
            downloadState = .notDownloaded
            modelSizeBytes = 0
            return
        }

        var totalSize: Int64 = 0
        for file in Self.expectedFiles {
            let filePath = (snapshotPath as NSString).appendingPathComponent(file)
            guard let attrs = try? fileManager.attributesOfItem(atPath: filePath),
                  let size = attrs[.size] as? Int64,
                  size > 0 else {
                downloadState = .notDownloaded
                modelSizeBytes = 0
                return
            }
            totalSize += size
        }

        modelSizeBytes = totalSize
        downloadState = .downloaded
    }

    /// Удалить модель из кэша
    func deleteModel() throws {
        guard fileManager.fileExists(atPath: modelCacheDir) else { return }
        try fileManager.removeItem(atPath: modelCacheDir)
        downloadState = .notDownloaded
        modelSizeBytes = 0
    }

    // MARK: - Private

    /// Найти валидный snapshot (содержит все expectedFiles)
    private func findLatestSnapshot() -> String? {
        let snapshotsDir = (modelCacheDir as NSString).appendingPathComponent("snapshots")
        guard let entries = try? fileManager.contentsOfDirectory(atPath: snapshotsDir) else {
            return nil
        }
        for entry in entries where !entry.hasPrefix(".") {
            let path = (snapshotsDir as NSString).appendingPathComponent(entry)
            let allPresent = Self.expectedFiles.allSatisfy { file in
                let filePath = (path as NSString).appendingPathComponent(file)
                return fileManager.fileExists(atPath: filePath)
            }
            if allPresent { return path }
        }
        return nil
    }
}
