@testable import Govorun
import XCTest

// MARK: - Мок STT клиент

final class MockSTTClient: STTClient, @unchecked Sendable {
    var recognizeResult: STTResult?
    var recognizeError: Error?
    private(set) var recognizeCalls: [(audioData: Data, hints: [String])] = []
    private let lock = NSLock()

    func recognize(audioData: Data, hints: [String]) async throws -> STTResult {
        lock.lock()
        recognizeCalls.append((audioData, hints))
        lock.unlock()

        if let error = recognizeError {
            throw error
        }
        guard let result = recognizeResult else {
            throw STTError.noResult
        }
        return result
    }
}

// MARK: - Мок LLM клиент

final class MockLLMClient: LLMClient, @unchecked Sendable {
    var normalizeResult: String?
    var normalizeError: Error?
    private(set) var normalizeCalls: [(text: String, mode: TextMode, hints: NormalizationHints)] = []
    private let lock = NSLock()

    func normalize(_ text: String, mode: TextMode, hints: NormalizationHints) async throws -> String {
        lock.lock()
        normalizeCalls.append((text, mode, hints))
        lock.unlock()

        if let error = normalizeError {
            throw error
        }
        return normalizeResult ?? text
    }
}
