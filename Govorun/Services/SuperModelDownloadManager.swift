import CryptoKit
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

// MARK: - Sidecar metadata

struct PartialDownloadMeta: Codable, Equatable {
    let url: String
    let expectedSHA256: String
    let expectedSize: Int64
    let etag: String?
    let downloadedBytes: Int64
}

// MARK: - Implementation

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

        guard meta.expectedSHA256 == spec.expectedSHA256,
              meta.url == spec.url.absoluteString
        else {
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
        setState(.idle)
    }

    // MARK: - SHA256

    static func sha256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1_024 * 1_024
        if #available(macOS 10.15.4, *) {
            // read(upToCount:) returns nil at EOF on this OS version
            while let chunk = try? handle.read(upToCount: chunkSize) {
                guard !chunk.isEmpty else { break }
                hasher.update(data: chunk)
            }
        } else {
            while true {
                let chunk = handle.readData(ofLength: chunkSize)
                guard !chunk.isEmpty else { break }
                hasher.update(data: chunk)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Disk space

    private func availableDiskSpace(at url: URL) -> Int64? {
        let dir = url.deletingLastPathComponent()
        let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return Int64(capacity)
    }

    // MARK: - Download

    func download(from spec: SuperModelDownloadSpec) async {
        guard !isActive else { return }

        setState(.checkingExisting)
        if FileManager.default.fileExists(atPath: spec.destination.path) {
            if let hash = Self.sha256(ofFileAt: spec.destination),
               hash == spec.expectedSHA256
            {
                setState(.completed)
                return
            }
        }

        let partialSize = (try? FileManager.default.attributesOfItem(atPath: partialURL(for: spec).path))?[.size] as? Int64 ?? 0
        let remaining = spec.expectedSize.subtractingReportingOverflow(partialSize).partialValue
        let (neededBytes, overflow) = remaining.addingReportingOverflow(SuperModelCatalog.minimumDiskSpaceBuffer)
        let neededBytesSafe = overflow ? Int64.max : neededBytes
        if let available = availableDiskSpace(at: spec.destination), available < neededBytesSafe {
            setState(.failed(.insufficientDiskSpace(required: neededBytesSafe, available: available)))
            return
        }

        let dir = spec.destination.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        setState(.failed(.networkError("download not implemented yet")))
    }

    // MARK: - Cancel (stub — Task 4)

    func cancel() {
        // будет реализовано в Task 4
    }
}
