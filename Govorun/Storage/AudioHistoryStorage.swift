import Foundation

enum AudioHistoryStorage {
    private static let directoryName = "AudioHistory"

    static var directory: URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // macOS всегда возвращает Application Support, но на всякий случай fallback на tmp
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GovorunAudioHistory")
        }
        let bundleId = Bundle.main.bundleIdentifier ?? "com.govorun"
        return appSupport.appendingPathComponent(bundleId).appendingPathComponent(directoryName)
    }

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func fileURL(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Сохраняет PCM 16-bit 16kHz mono как WAV
    static func saveWAV(audioData: Data, sessionId: UUID) throws -> String {
        try ensureDirectory()

        let fileName = "\(sessionId.uuidString).wav"
        let url = fileURL(for: fileName)

        let wavData = wavFileData(pcmData: audioData, sampleRate: 16_000, channels: 1, bitsPerSample: 16)
        try wavData.write(to: url, options: .atomic)

        return fileName
    }

    static func deleteFile(named fileName: String) {
        let url = fileURL(for: fileName)
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAllFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - WAV

    private static func wavFileData(pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        LocalSTTClient.addWAVHeader(to: pcmData, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample)
    }
}

// MARK: - Data helpers

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func append(littleEndian value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
