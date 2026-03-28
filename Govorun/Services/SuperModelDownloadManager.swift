import CryptoKit
import Foundation
import os

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
    private static let logger = Logger(subsystem: "com.govorun", category: "SuperModelDownload")
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

    private var _onStateChanged: (@MainActor @Sendable (SuperModelDownloadState) -> Void)?

    var onStateChanged: (@MainActor @Sendable (SuperModelDownloadState) -> Void)? {
        get { lock.withLock { _onStateChanged } }
        set { lock.withLock { _onStateChanged = newValue } }
    }

    private func setState(_ newState: SuperModelDownloadState) {
        let callback: (@MainActor @Sendable (SuperModelDownloadState) -> Void)? = lock.withLock {
            _state = newState
            return _onStateChanged
        }
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
        do {
            return try JSONDecoder().decode(PartialDownloadMeta.self, from: data)
        } catch {
            Self.logger.warning("Не удалось декодировать .partial.meta: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func writeMeta(_ meta: PartialDownloadMeta, for spec: SuperModelDownloadSpec) {
        let url = metaURL(for: spec)
        do {
            let data = try JSONEncoder().encode(meta)
            try data.write(to: url)
        } catch {
            Self.logger.error("writeMeta не удался: \(error.localizedDescription, privacy: .public)")
        }
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
            Self.logger.info("Удаляю устаревший partial: spec изменился")
            try? fm.removeItem(at: partial)
            deleteMeta(for: spec)
            return
        }

        setState(.partialReady(downloadedBytes: meta.downloadedBytes, totalBytes: spec.expectedSize))
    }

    // MARK: - Clear

    func clearPartialDownload(for spec: SuperModelDownloadSpec) {
        let fm = FileManager.default
        let partialPath = partialURL(for: spec)
        do {
            if fm.fileExists(atPath: partialPath.path) {
                try fm.removeItem(at: partialPath)
            }
            deleteMeta(for: spec)
            setState(.idle)
        } catch {
            Self.logger.error("Не удалось удалить partial файл: \(error.localizedDescription, privacy: .public)")
            setState(.failed(.fileSystemError("Не удалось удалить файл: \(error.localizedDescription)")))
        }
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
        var readError = false
        if #available(macOS 10.15.4, *) {
            while true {
                let chunk: Data?
                do {
                    chunk = try handle.read(upToCount: chunkSize)
                } catch {
                    readError = true
                    break
                }
                guard let data = chunk, !data.isEmpty else { break }
                hasher.update(data: data)
            }
        } else {
            while autoreleasepool(invoking: {
                let data = handle.readData(ofLength: chunkSize)
                guard !data.isEmpty else { return false }
                hasher.update(data: data)
                return true
            }) {}
        }
        if readError { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Disk space

    private func availableDiskSpace(at url: URL) -> Int64? {
        var dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        while !fm.fileExists(atPath: dir.path), dir.path != "/" {
            dir = dir.deletingLastPathComponent()
        }
        guard let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage
        else {
            Self.logger.warning("Не удалось получить свободное место для \(dir.path, privacy: .public)")
            return nil
        }
        return capacity
    }

    // MARK: - Download

    func download(from spec: SuperModelDownloadSpec) async {
        guard !isActive else { return }

        // Fast path
        setState(.checkingExisting)
        if FileManager.default.fileExists(atPath: spec.destination.path) {
            if let hash = Self.sha256(ofFileAt: spec.destination),
               hash == spec.expectedSHA256
            {
                setState(.completed)
                return
            }
        }

        // Disk space check (with overflow protection)
        let partialSize = (try? FileManager.default.attributesOfItem(
            atPath: partialURL(for: spec).path
        ))?[.size] as? Int64 ?? 0
        let remaining = spec.expectedSize.subtractingReportingOverflow(partialSize).partialValue
        let (neededBytes, overflow) = remaining.addingReportingOverflow(SuperModelCatalog.minimumDiskSpaceBuffer)
        let neededBytesSafe = overflow ? Int64.max : neededBytes
        if let available = availableDiskSpace(at: spec.destination), available < neededBytesSafe {
            setState(.failed(.insufficientDiskSpace(required: neededBytesSafe, available: available)))
            return
        }

        // Create directory
        let dir = spec.destination.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            setState(.failed(.fileSystemError("Не удалось создать каталог: \(error.localizedDescription)")))
            return
        }

        // Resume check
        let partial = partialURL(for: spec)
        var resumeOffset: Int64 = 0
        if let meta = readMeta(for: spec),
           meta.expectedSHA256 == spec.expectedSHA256,
           meta.url == spec.url.absoluteString,
           FileManager.default.fileExists(atPath: partial.path)
        {
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

        // Prepare file
        if resumeOffset == 0 || !FileManager.default.fileExists(atPath: partial.path) {
            if !FileManager.default.createFile(atPath: partial.path, contents: nil) {
                setState(.failed(.fileSystemError("Не удалось создать файл для загрузки")))
                return
            }
        }
        guard let fileHandle = try? FileHandle(forWritingTo: partial) else {
            setState(.failed(.fileSystemError("Не удалось открыть файл для записи")))
            return
        }
        if resumeOffset > 0 { fileHandle.seekToEndOfFile() }

        var etag: String?
        var downloadedBytes = resumeOffset

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                fileHandle.closeFile()
                setState(.failed(.networkError("Не HTTP ответ")))
                return
            }

            if httpResponse.statusCode == 200, resumeOffset > 0 {
                resumeOffset = 0
                downloadedBytes = 0
                fileHandle.truncateFile(atOffset: 0)
                fileHandle.seek(toFileOffset: 0)
            } else if httpResponse.statusCode != 200, httpResponse.statusCode != 206 {
                fileHandle.closeFile()
                setState(.failed(.networkError("HTTP \(httpResponse.statusCode)")))
                return
            }

            etag = httpResponse.value(forHTTPHeaderField: "ETag")
            let totalBytes = spec.expectedSize
            var lastProgressUpdate = Date()
            var buffer = Data()
            let bufferFlushSize = 256 * 1_024

            for try await byte in asyncBytes {
                if Task.isCancelled {
                    if !buffer.isEmpty {
                        fileHandle.write(buffer)
                        downloadedBytes += Int64(buffer.count)
                    }
                    fileHandle.closeFile()
                    writeMeta(.from(spec: spec, etag: etag, downloadedBytes: downloadedBytes), for: spec)
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
                        let progress = Double(downloadedBytes)/Double(totalBytes)
                        setState(.downloading(
                            progress: progress, downloadedBytes: downloadedBytes, totalBytes: totalBytes
                        ))
                        writeMeta(.from(spec: spec, etag: etag, downloadedBytes: downloadedBytes), for: spec)
                    }
                }
            }

            if !buffer.isEmpty {
                fileHandle.write(buffer)
                downloadedBytes += Int64(buffer.count)
            }
            fileHandle.closeFile()

            writeMeta(.from(spec: spec, etag: etag, downloadedBytes: downloadedBytes), for: spec)

        } catch {
            fileHandle.closeFile()
            writeMeta(.from(spec: spec, etag: etag, downloadedBytes: downloadedBytes), for: spec)
            if Task.isCancelled {
                setState(.cancelled)
            } else {
                setState(.failed(.networkError(error.localizedDescription)))
            }
            return
        }

        // Verification
        setState(.verifying)
        let verifyResult = verifyAndFinalize(spec: spec)
        if Task.isCancelled {
            setState(.cancelled)
            return
        }
        switch verifyResult {
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
        let callback: (@MainActor @Sendable (SuperModelDownloadState) -> Void)? = lock.withLock {
            guard case .downloading = _state else { return nil }
            _state = .cancelled
            return _onStateChanged
        }
        Task { @MainActor in
            callback?(.cancelled)
        }
    }
}

// MARK: - PartialDownloadMeta factory

extension PartialDownloadMeta {
    static func from(spec: SuperModelDownloadSpec, etag: String?, downloadedBytes: Int64) -> PartialDownloadMeta {
        PartialDownloadMeta(
            url: spec.url.absoluteString,
            expectedSHA256: spec.expectedSHA256,
            expectedSize: spec.expectedSize,
            etag: etag,
            downloadedBytes: downloadedBytes
        )
    }
}
