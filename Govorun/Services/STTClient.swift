import Foundation

// MARK: - Протокол STT для DI

protocol STTClient: Sendable {
    func recognize(audioData: Data, hints: [String]) async throws -> STTResult
}

// MARK: - Результат распознавания

struct STTResult: Equatable {
    let text: String
    let normalizedText: String
    let confidence: Float

    init(text: String, normalizedText: String = "", confidence: Float = 0) {
        self.text = text
        self.normalizedText = normalizedText.isEmpty ? text : normalizedText
        self.confidence = confidence
    }
}

// MARK: - Ошибки STT

enum STTError: Error, Equatable {
    case noAudioData
    case connectionFailed(String)
    case recognitionFailed(String)
    case noResult

    static func == (lhs: STTError, rhs: STTError) -> Bool {
        switch (lhs, rhs) {
        case (.noAudioData, .noAudioData),
             (.noResult, .noResult):
            true
        case (.connectionFailed(let a), .connectionFailed(let b)),
             (.recognitionFailed(let a), .recognitionFailed(let b)):
            a == b
        default:
            false
        }
    }
}
