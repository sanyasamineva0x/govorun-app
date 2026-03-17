import Foundation
import SwiftData

@Model
final class HistoryItem {
    var sessionId: UUID
    var rawTranscript: String
    var normalizedText: String
    var textMode: String
    var appName: String?
    var normalizationPath: String
    var sttLatencyMs: Int
    var normalizationLatencyMs: Int
    var insertionLatencyMs: Int
    var totalLatencyMs: Int
    var wordCount: Int
    var insertionStrategy: String?
    var audioFileName: String?
    var createdAt: Date

    init(
        sessionId: UUID,
        rawTranscript: String,
        normalizedText: String,
        textMode: String,
        appName: String? = nil,
        normalizationPath: String,
        sttLatencyMs: Int = 0,
        normalizationLatencyMs: Int = 0,
        insertionLatencyMs: Int = 0,
        totalLatencyMs: Int = 0,
        wordCount: Int = 0,
        insertionStrategy: String? = nil,
        audioFileName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.rawTranscript = rawTranscript
        self.normalizedText = normalizedText
        self.textMode = textMode
        self.appName = appName
        self.normalizationPath = normalizationPath
        self.sttLatencyMs = sttLatencyMs
        self.normalizationLatencyMs = normalizationLatencyMs
        self.insertionLatencyMs = insertionLatencyMs
        self.totalLatencyMs = totalLatencyMs
        self.wordCount = wordCount
        self.insertionStrategy = insertionStrategy
        self.audioFileName = audioFileName
        self.createdAt = createdAt
    }
}
