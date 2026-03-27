import Foundation
import OSLog

// MARK: - Ошибки Pipeline

enum PipelineError: Error, Equatable {
    case sttFailed(String)
    case audioCaptureFailed(String)
    case cancelled

    static func == (lhs: PipelineError, rhs: PipelineError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled):
            true
        case (.sttFailed(let a), .sttFailed(let b)):
            a == b
        case (.audioCaptureFailed(let a), .audioCaptureFailed(let b)):
            a == b
        default:
            false
        }
    }
}

// MARK: - Результат Pipeline

struct PipelineResult {
    let sessionId: UUID
    let rawTranscript: String
    let normalizedText: String
    let textMode: TextMode
    let normalizationPath: NormalizationPath
    let sttLatencyMs: Int
    let llmLatencyMs: Int
    var insertionLatencyMs: Int
    let totalLatencyMs: Int
    let matchedSnippetTrigger: String?
    let snippetFallbackUsed: Bool
    let snippetFallbackReason: SnippetFallbackReason?
    let gateFailureReason: NormalizationGateFailureReason?
    var insertionStrategy: InsertionStrategy?
    let audioDurationMs: Int
    var audioFileName: String?

    enum NormalizationPath: String {
        case trivial
        case snippet // standalone: content as-is, 0ms
        case snippetPlusLLM // embedded: placeholder → LLM → reinsertion
        case llm
        case llmRejected // LLM ответил, но gate отклонил → deterministicText fallback
        case llmFailed // LLM упал → deterministicText fallback
    }

    enum SnippetFallbackReason: String {
        case gateRejected = "gate_rejected"
        case reinsertionFailed = "reinsertion_failed"
        case llmFailed = "llm_failed"

        var analyticsValue: String {
            rawValue
        }
    }

    init(
        sessionId: UUID,
        rawTranscript: String,
        normalizedText: String,
        textMode: TextMode,
        normalizationPath: NormalizationPath,
        sttLatencyMs: Int,
        llmLatencyMs: Int,
        insertionLatencyMs: Int,
        totalLatencyMs: Int,
        matchedSnippetTrigger: String? = nil,
        snippetFallbackUsed: Bool = false,
        snippetFallbackReason: SnippetFallbackReason? = nil,
        gateFailureReason: NormalizationGateFailureReason? = nil,
        insertionStrategy: InsertionStrategy? = nil,
        audioDurationMs: Int = 0,
        audioFileName: String? = nil
    ) {
        self.sessionId = sessionId
        self.rawTranscript = rawTranscript
        self.normalizedText = normalizedText
        self.textMode = textMode
        self.normalizationPath = normalizationPath
        self.sttLatencyMs = sttLatencyMs
        self.llmLatencyMs = llmLatencyMs
        self.insertionLatencyMs = insertionLatencyMs
        self.totalLatencyMs = totalLatencyMs
        self.matchedSnippetTrigger = matchedSnippetTrigger
        self.snippetFallbackUsed = snippetFallbackUsed
        self.snippetFallbackReason = snippetFallbackReason
        self.gateFailureReason = gateFailureReason
        self.insertionStrategy = insertionStrategy
        self.audioDurationMs = audioDurationMs
        self.audioFileName = audioFileName
    }
}

// MARK: - Snippet Match Result

enum SnippetMatchKind: Equatable {
    case standalone // весь транскрипт = триггер
    case embedded // триггер внутри фразы
}

struct SnippetMatch {
    let trigger: String
    let content: String
    let kind: SnippetMatchKind
}

// MARK: - Snippet Reinserter

enum SnippetReinserter {
    static func reinsert(llmOutput: String, content: String) -> String? {
        let token = SnippetPlaceholder.token
        let occurrences = llmOutput.components(separatedBy: token).count - 1

        guard occurrences == 1 else { return nil }

        guard let range = llmOutput.range(of: token) else { return nil }

        if range.lowerBound != llmOutput.startIndex {
            let charBefore = llmOutput[llmOutput.index(before: range.lowerBound)]
            if !charBefore.isWhitespace, !charBefore.isPunctuation {
                return nil
            }
        }

        if range.upperBound != llmOutput.endIndex {
            let charAfter = llmOutput[range.upperBound]
            if !charAfter.isWhitespace, !charAfter.isPunctuation {
                return nil
            }
        }

        return llmOutput.replacingOccurrences(of: token, with: content)
    }

    static func mechanicalFallback(
        rawTranscript: String,
        trigger: String,
        content: String
    ) -> String {
        if let triggerRange = triggerRange(in: rawTranscript, trigger: trigger) {
            let prefix = rawTranscript[..<triggerRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = rawTranscript[triggerRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var result = ""
            if !prefix.isEmpty {
                result.append(String(prefix))
                result.append(" ")
            }

            result.append("\(trigger): \(content)")

            if !suffix.isEmpty {
                if suffix.first?.isPunctuation == true {
                    result.append(String(suffix))
                } else {
                    result.append(" ")
                    result.append(String(suffix))
                }
            }

            return result.prefix(1).uppercased() + result.dropFirst()
        }

        let capitalizedTrigger = trigger.prefix(1).uppercased() + trigger.dropFirst()
        return "\(capitalizedTrigger): \(content)"
    }

    private static func triggerRange(in text: String, trigger: String) -> Range<String.Index>? {
        if let directRange = text.range(of: trigger, options: [.caseInsensitive, .diacriticInsensitive]) {
            return directRange
        }

        let triggerTokens = SnippetEngine.tokenize(trigger)
        guard !triggerTokens.isEmpty else { return nil }

        let tokenPattern = try! NSRegularExpression(pattern: "\\S+")
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = tokenPattern.matches(in: text, options: [], range: nsRange)

        let textTokensWithRanges: [(token: String, range: Range<String.Index>)] = matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let rawToken = text[range]
            let normalizedToken = String(rawToken)
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            guard !normalizedToken.isEmpty else { return nil }
            return (normalizedToken, range)
        }

        let windowSize = triggerTokens.count
        guard textTokensWithRanges.count >= windowSize else { return nil }

        for i in 0...(textTokensWithRanges.count - windowSize) {
            let window = Array(textTokensWithRanges[i..<(i + windowSize)]).map(\.token)
            if window == triggerTokens {
                let start = textTokensWithRanges[i].range.lowerBound
                let end = textTokensWithRanges[i + windowSize - 1].range.upperBound
                return start..<end
            }
        }

        return nil
    }
}

// MARK: - Протокол Snippet Matching

protocol SnippetMatching: Sendable {
    func match(_ text: String) -> SnippetMatch?
}

// MARK: - PipelineEngine

final class PipelineEngine: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.govorun.app", category: "PipelineEngine")

    private let audioCapture: AudioRecording
    private let sttClient: STTClient
    private let snippetEngine: SnippetMatching?

    private let lock = NSLock()
    private var _isCancelled = false
    private var _isRecording = false
    private var _llmClient: LLMClient

    private var _textMode: TextMode = .universal
    private var _hints: NormalizationHints = .init()
    private var _terminalPeriodEnabled: Bool = true
    private var _saveAudioHistory: Bool = false
    private var _sessionId: UUID?

    var textMode: TextMode {
        get { lock.lock(); defer { lock.unlock() }; return _textMode }
        set { lock.lock(); defer { lock.unlock() }; _textMode = newValue }
    }

    var hints: NormalizationHints {
        get { lock.lock(); defer { lock.unlock() }; return _hints }
        set { lock.lock(); defer { lock.unlock() }; _hints = newValue }
    }

    var terminalPeriodEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _terminalPeriodEnabled }
        set { lock.lock(); defer { lock.unlock() }; _terminalPeriodEnabled = newValue }
    }

    var saveAudioHistory: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _saveAudioHistory }
        set { lock.lock(); defer { lock.unlock() }; _saveAudioHistory = newValue }
    }

    init(
        audioCapture: AudioRecording,
        sttClient: STTClient,
        llmClient: LLMClient,
        snippetEngine: SnippetMatching? = nil
    ) {
        self.audioCapture = audioCapture
        self.sttClient = sttClient
        _llmClient = llmClient
        self.snippetEngine = snippetEngine
    }

    func updateLLMClient(_ llmClient: LLMClient) {
        lock.lock()
        defer { lock.unlock() }
        _llmClient = llmClient
    }

    func startRecording(sessionId: UUID) throws {
        lock.lock()
        _sessionId = sessionId
        lock.unlock()

        prepareForRecording()
        try audioCapture.startRecording()
    }

    /// No-op: streaming убран, чанки не буферизуются.
    /// Метод сохранён для совместимости с AudioCaptureBridge в AppState.
    func handleAudioChunk(_ chunk: Data) {}

    func stopRecording() async throws -> PipelineResult {
        let stopTime = CFAbsoluteTimeGetCurrent()
        let sessionId = snapshotSessionId()

        // Snapshot под локом — защита от race condition при быстром двойном тапе ⌥
        let (currentTextMode, currentHints, currentLLMClient) = snapshotConfig()

        markRecordingStopped()
        let audioDurationMs = Int(audioCapture.duration * 1_000)
        let audioData = audioCapture.stopRecording()

        // Сохраняем аудио на диск для истории (если включено в настройках)
        let audioFileName: String? = if !audioData.isEmpty && saveAudioHistory {
            try? AudioHistoryStorage.saveWAV(audioData: audioData, sessionId: sessionId)
        } else {
            nil
        }

        func cleanupAudioOnFailure() {
            if let audioFileName {
                AudioHistoryStorage.deleteFile(named: audioFileName)
            }
        }

        // STT — batch (GigaAM не поддерживает streaming)
        let sttStart = CFAbsoluteTimeGetCurrent()
        let sttResult: STTResult
        do {
            sttResult = try await sttClient.recognize(audioData: audioData, hints: [])
        } catch {
            cleanupAudioOnFailure()
            throw PipelineError.sttFailed(error.localizedDescription)
        }
        let sttLatencyMs = Int((CFAbsoluteTimeGetCurrent() - sttStart) * 1_000)

        guard !currentIsCancelled() else {
            cleanupAudioOnFailure()
            throw PipelineError.cancelled
        }

        let rawTranscript = sttResult.text

        // Пост-замены из словаря (жира → Jira) — до нормализации и сниппетов
        let correctedTranscript = DictionaryStore.applyReplacements(
            to: rawTranscript,
            replacements: currentHints.personalDictionary
        )

        // Пустой транскрипт → пропускаем LLM
        guard !correctedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - stopTime) * 1_000)
            return PipelineResult(
                sessionId: sessionId,
                rawTranscript: rawTranscript,
                normalizedText: "",
                textMode: currentTextMode,
                normalizationPath: .trivial,
                sttLatencyMs: sttLatencyMs,
                llmLatencyMs: 0,
                insertionLatencyMs: 0,
                totalLatencyMs: totalMs,
                audioDurationMs: audioDurationMs,
                audioFileName: audioFileName
            )
        }

        // Единый deterministic baseline до LLM:
        // числа, валюты, время, даты и базовая очистка всегда проходят один и тот же путь.
        let deterministicText = makeDeterministicBaseline(
            from: correctedTranscript,
            terminalPeriodEnabled: terminalPeriodEnabled
        )

        // Snippet match (на исправленном тексте)
        if let snippetEngine, let snippetMatch = snippetEngine.match(correctedTranscript) {
            switch snippetMatch.kind {
            case .standalone:
                let totalMs = Int((CFAbsoluteTimeGetCurrent() - stopTime) * 1_000)
                return PipelineResult(
                    sessionId: sessionId,
                    rawTranscript: rawTranscript,
                    normalizedText: snippetMatch.content,
                    textMode: currentTextMode,
                    normalizationPath: .snippet,
                    sttLatencyMs: sttLatencyMs,
                    llmLatencyMs: 0,
                    insertionLatencyMs: 0,
                    totalLatencyMs: totalMs,
                    matchedSnippetTrigger: snippetMatch.trigger,
                    snippetFallbackUsed: false,
                    gateFailureReason: nil,
                    audioDurationMs: audioDurationMs,
                    audioFileName: audioFileName
                )

            case .embedded:
                let snippetCtx = SnippetContext(trigger: snippetMatch.trigger)
                let hintsWithSnippet = NormalizationHints(
                    personalDictionary: currentHints.personalDictionary,
                    appName: currentHints.appName,
                    textMode: currentHints.textMode,
                    currentDate: currentHints.currentDate,
                    snippetContext: snippetCtx
                )

                let llmStart = CFAbsoluteTimeGetCurrent()
                let finalText: String
                let llmLatencyMs: Int
                var fallbackUsed = false
                var snippetFallbackReason: PipelineResult.SnippetFallbackReason?
                var gateFailureReason: NormalizationGateFailureReason?

                do {
                    guard !currentIsCancelled() else {
                        cleanupAudioOnFailure()
                        throw PipelineError.cancelled
                    }
                    let llmOutput = try await currentLLMClient.normalize(
                        deterministicText, mode: currentTextMode, hints: hintsWithSnippet
                    )
                    guard !currentIsCancelled() else {
                        cleanupAudioOnFailure()
                        throw PipelineError.cancelled
                    }
                    llmLatencyMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1_000)

                    let gateResult = NormalizationGate.evaluate(
                        input: deterministicText,
                        output: llmOutput,
                        contract: currentTextMode.llmOutputContract,
                        ignoredOutputLiterals: Set([SnippetPlaceholder.token])
                    )

                    if !gateResult.accepted {
                        fallbackUsed = true
                        snippetFallbackReason = .gateRejected
                        gateFailureReason = gateResult.failureReason
                        let reasonDescription = gateFailureReason?.description ?? "unknown"
                        Self.logger.warning(
                            "NormalizationGate rejected embedded snippet output: \(reasonDescription, privacy: .public)"
                        )
                        finalText = SnippetReinserter.mechanicalFallback(
                            rawTranscript: deterministicText,
                            trigger: snippetMatch.trigger, content: snippetMatch.content
                        )
                    } else if let reinserted = SnippetReinserter.reinsert(
                        llmOutput: gateResult.output, content: snippetMatch.content
                    ) {
                        finalText = reinserted
                    } else {
                        fallbackUsed = true
                        snippetFallbackReason = .reinsertionFailed
                        Self.logger.warning("Snippet reinsertion failed after embedded LLM normalization")
                        finalText = SnippetReinserter.mechanicalFallback(
                            rawTranscript: deterministicText,
                            trigger: snippetMatch.trigger, content: snippetMatch.content
                        )
                    }
                } catch PipelineError.cancelled {
                    cleanupAudioOnFailure()
                    throw PipelineError.cancelled
                } catch {
                    fallbackUsed = true
                    snippetFallbackReason = .llmFailed
                    llmLatencyMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1_000)
                    Self.logger.error(
                        "LLM failed for embedded snippet: \(String(describing: error), privacy: .public)"
                    )
                    finalText = SnippetReinserter.mechanicalFallback(
                        rawTranscript: deterministicText,
                        trigger: snippetMatch.trigger, content: snippetMatch.content
                    )
                }

                let totalMs = Int((CFAbsoluteTimeGetCurrent() - stopTime) * 1_000)
                return PipelineResult(
                    sessionId: sessionId,
                    rawTranscript: rawTranscript,
                    normalizedText: finalText,
                    textMode: currentTextMode,
                    normalizationPath: .snippetPlusLLM,
                    sttLatencyMs: sttLatencyMs,
                    llmLatencyMs: llmLatencyMs,
                    insertionLatencyMs: 0,
                    totalLatencyMs: totalMs,
                    matchedSnippetTrigger: snippetMatch.trigger,
                    snippetFallbackUsed: fallbackUsed,
                    snippetFallbackReason: snippetFallbackReason,
                    gateFailureReason: gateFailureReason,
                    audioDurationMs: audioDurationMs,
                    audioFileName: audioFileName
                )
            }
        }

        // Trivial text → только DeterministicNormalizer, без LLM
        if isTrivial(correctedTranscript) {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - stopTime) * 1_000)
            return PipelineResult(
                sessionId: sessionId,
                rawTranscript: rawTranscript,
                normalizedText: deterministicText,
                textMode: currentTextMode,
                normalizationPath: .trivial,
                sttLatencyMs: sttLatencyMs,
                llmLatencyMs: 0,
                insertionLatencyMs: 0,
                totalLatencyMs: totalMs,
                audioDurationMs: audioDurationMs,
                audioFileName: audioFileName
            )
        }

        // LLM нормализация (на уже очищенном тексте)
        let llmStart = CFAbsoluteTimeGetCurrent()
        let normalizedText: String
        let llmLatencyMs: Int

        do {
            guard !currentIsCancelled() else {
                cleanupAudioOnFailure()
                throw PipelineError.cancelled
            }
            normalizedText = try await currentLLMClient.normalize(
                deterministicText,
                mode: currentTextMode,
                hints: currentHints
            )
            guard !currentIsCancelled() else {
                cleanupAudioOnFailure()
                throw PipelineError.cancelled
            }
            llmLatencyMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1_000)
        } catch PipelineError.cancelled {
            cleanupAudioOnFailure()
            throw PipelineError.cancelled
        } catch {
            // Graceful degradation: LLM упал → возвращаем deterministicText
            llmLatencyMs = Int((CFAbsoluteTimeGetCurrent() - llmStart) * 1_000)
            Self.logger.error("LLM failed: \(String(describing: error), privacy: .public)")
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - stopTime) * 1_000)
            return PipelineResult(
                sessionId: sessionId,
                rawTranscript: rawTranscript,
                normalizedText: deterministicText,
                textMode: currentTextMode,
                normalizationPath: .llmFailed,
                sttLatencyMs: sttLatencyMs,
                llmLatencyMs: llmLatencyMs,
                insertionLatencyMs: 0,
                totalLatencyMs: totalMs,
                audioDurationMs: audioDurationMs,
                audioFileName: audioFileName
            )
        }

        let gateResult = NormalizationGate.evaluate(
            input: deterministicText,
            output: normalizedText,
            contract: currentTextMode.llmOutputContract
        )
        if let failureReason = gateResult.failureReason {
            Self.logger.warning(
                "NormalizationGate rejected output: \(failureReason.description, privacy: .public)"
            )
        }

        // Terminal period policy — LLM часто возвращает текст с точкой
        let finalText = terminalPeriodEnabled
            ? gateResult.output
            : DeterministicNormalizer.stripTrailingPeriods(gateResult.output)

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - stopTime) * 1_000)
        return PipelineResult(
            sessionId: sessionId,
            rawTranscript: rawTranscript,
            normalizedText: finalText,
            textMode: currentTextMode,
            normalizationPath: gateResult.accepted ? .llm : .llmRejected,
            sttLatencyMs: sttLatencyMs,
            llmLatencyMs: llmLatencyMs,
            insertionLatencyMs: 0,
            totalLatencyMs: totalMs,
            gateFailureReason: gateResult.failureReason,
            audioDurationMs: audioDurationMs,
            audioFileName: audioFileName
        )
    }

    func cancel() {
        lock.lock()
        _isCancelled = true
        let wasRecording = _isRecording
        _isRecording = false
        lock.unlock()

        if wasRecording {
            _ = audioCapture.stopRecording()
        }
    }

    private func snapshotSessionId() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        return _sessionId ?? UUID()
    }

    private func snapshotConfig() -> (TextMode, NormalizationHints, LLMClient) {
        lock.lock()
        defer { lock.unlock() }
        return (_textMode, _hints, _llmClient)
    }

    private func prepareForRecording() {
        lock.lock()
        _isCancelled = false
        _isRecording = true
        lock.unlock()
    }

    private func markRecordingStopped() {
        lock.lock()
        defer { lock.unlock() }
        _isRecording = false
    }

    private func currentIsCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    private func makeDeterministicBaseline(
        from text: String,
        terminalPeriodEnabled: Bool
    ) -> String {
        DeterministicNormalizer.normalize(
            text,
            terminalPeriodEnabled: terminalPeriodEnabled
        )
    }
}
