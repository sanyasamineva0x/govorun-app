import Foundation

enum SuperModelDownloadState: Equatable {
    case idle
    case checkingExisting
    case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64)
    case verifying
    case completed
    case failed(SuperModelDownloadError)
    case cancelled
    case partialReady(downloadedBytes: Int64, totalBytes: Int64)
}

enum SuperModelDownloadError: Error, LocalizedError, Equatable {
    case insufficientDiskSpace(required: Int64, available: Int64)
    case integrityCheckFailed
    case networkError(String)
    case fileSystemError(String)

    var errorDescription: String? {
        switch self {
        case .insufficientDiskSpace(let required, let available):
            let requiredGB = String(format: "%.1f", Double(required)/1_000_000_000)
            let availableGB = String(format: "%.1f", Double(available)/1_000_000_000)
            return "Недостаточно места: нужно \(requiredGB) ГБ, доступно \(availableGB) ГБ"
        case .integrityCheckFailed:
            return "Файл повреждён — контрольная сумма не совпадает"
        case .networkError(let message):
            return "Ошибка сети: \(message)"
        case .fileSystemError(let message):
            return "Ошибка файловой системы: \(message)"
        }
    }
}
