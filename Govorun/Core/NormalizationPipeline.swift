import Foundation

// MARK: - Детерминированная нормализация

enum DeterministicNormalizer {
    private static let fillerWords: Set<String> = [
        "эм", "ээ", "ммм", "ну", "типа", "вот", "короче", "блин", "так",
    ]

    private static let fillerPhrases: [String] = [
        "это самое", "как бы",
    ]

    private static let canonicalPhraseReplacements: [String: String] = [
        "jira server": "Jira Server",
        "project yml": "project.yml",
        "marketing version": "MARKETING_VERSION",
        "current project version": "CURRENT_PROJECT_VERSION",
        "sparkles обновление": "Sparkle-обновление",
        "sparkle обновление": "Sparkle-обновление",
    ]

    private static let canonicalWordReplacements: [String: String] = [
        "жира": "Jira",
        "жиру": "Jira",
        "жире": "Jira",
        "джира": "Jira",
        "джиру": "Jira",
        "джире": "Jira",
        "гира": "Jira",
        "слак": "Slack",
        "слэк": "Slack",
        "слаке": "Slack",
        "слэке": "Slack",
        "ноушн": "Notion",
        "ноушне": "Notion",
        "телеграм": "Telegram",
        "телеграме": "Telegram",
        "telegram": "Telegram",
        "гитхаб": "GitHub",
        "гитхабе": "GitHub",
        "github": "GitHub",
        "зум": "Zoom",
        "zoom": "Zoom",
        "sparkle": "Sparkle",
        "sparkles": "Sparkle",
        "pdf": "PDF",
        "csv": "CSV",
        "ios": "iOS",
        "ml": "ML",
        "qa": "QA",
    ]

    static func normalize(_ text: String, terminalPeriodEnabled: Bool = true) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        for phrase in fillerPhrases {
            result = result.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        var words = result.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        words = words.compactMap { word in
            let lower = word.lowercased()
            let stripped = lower.trimmingCharacters(in: .punctuationCharacters)
            if fillerWords.contains(stripped) { return nil }
            return word
        }

        guard !words.isEmpty else { return "" }

        result = words.joined(separator: " ")
        result = NumberNormalizer.normalize(result)

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        result = result.trimmingCharacters(in: .whitespaces)

        guard !result.isEmpty else { return "" }

        result = result.prefix(1).uppercased() + result.dropFirst()
        result = capitalizeAfterSentenceEnd(result)
        result = applyCanonicalLexicon(result)

        if terminalPeriodEnabled {
            if let last = result.last, !last.isPunctuation {
                result += "."
            }
        } else {
            result = stripTrailingPeriods(result)
        }

        return result
    }

    private static func capitalizeAfterSentenceEnd(_ text: String) -> String {
        var chars = Array(text)
        var index = 0
        while index < chars.count {
            if chars[index] == "." || chars[index] == "?" || chars[index] == "!" {
                var nextIndex = index + 1
                while nextIndex < chars.count, chars[nextIndex] == " " {
                    nextIndex += 1
                }
                if nextIndex < chars.count, chars[nextIndex].isLetter {
                    chars[nextIndex] = Character(chars[nextIndex].uppercased())
                }
                index = nextIndex
            } else {
                index += 1
            }
        }
        return String(chars)
    }

    static func stripTrailingPeriods(_ text: String) -> String {
        var result = text
        while result.hasSuffix(".") {
            result = String(result.dropLast())
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func applyCanonicalLexicon(_ text: String) -> String {
        var result = text

        for (source, replacement) in canonicalPhraseReplacements {
            let escaped = NSRegularExpression.escapedPattern(for: source)
            result = result.replacingOccurrences(
                of: "\\b\(escaped)\\b",
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        for (source, replacement) in canonicalWordReplacements {
            let escaped = NSRegularExpression.escapedPattern(for: source)
            result = result.replacingOccurrences(
                of: "\\b\(escaped)\\b",
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return result
    }
}

// MARK: - Базовая валидация LLM

enum LLMResponseGuard {
    enum Issue: Equatable {
        case empty
        case refusal
        case disproportionateLength
    }

    private static let refusalPrefixes = [
        "к сожалению",
        "извините",
        "я не могу",
        "я не в состоянии",
        "данный запрос",
        "не могу обработать",
        "в соответствии с правилами",
    ]

    static func firstIssue(_ response: String, rawTranscript: String) -> Issue? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }

        let lower = trimmed.lowercased()
        let rawLower = rawTranscript.lowercased()

        for prefix in refusalPrefixes {
            if lower.hasPrefix(prefix), !rawLower.hasPrefix(prefix) {
                return .refusal
            }
        }

        let inputWords = rawTranscript.split(whereSeparator: \.isWhitespace).count
        let outputWords = trimmed.split(whereSeparator: \.isWhitespace).count
        if inputWords > 0, outputWords > inputWords * 3, outputWords > 10 {
            return .disproportionateLength
        }

        return nil
    }

    static func isUsable(_ response: String, rawTranscript: String) -> Bool {
        firstIssue(response, rawTranscript: rawTranscript) == nil
    }
}

// MARK: - Полный пайплайн

enum NormalizationPipelinePath: String {
    case trivial
    case llm
    case llmRejected
    case llmFailed
}

struct NormalizationPipelinePreflight: Equatable {
    let deterministicText: String
    let shouldInvokeLLM: Bool
}

struct NormalizationPipelinePostflight: Equatable {
    let finalText: String
    let path: NormalizationPipelinePath
    let gateFailureReason: NormalizationGateFailureReason?
    let failureContext: String?
}

enum NormalizationPipeline {
    static func isTrivial(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count <= 1 else { return false }

        let correctionMarkers = [
            "точнее", "то есть", "подожди", "в смысле",
            "имею в виду", "или нет", "хотя нет", "а нет",
        ]
        let lowered = text.lowercased()
        let hasCorrection = correctionMarkers.contains { lowered.contains($0) }
        let hasNumbers = text.contains(where: \.isNumber)

        return !hasCorrection && !hasNumbers
    }

    static func preflight(
        transcript: String,
        terminalPeriodEnabled: Bool = true
    ) -> NormalizationPipelinePreflight {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .init(deterministicText: "", shouldInvokeLLM: false)
        }

        let deterministicText = DeterministicNormalizer.normalize(
            transcript,
            terminalPeriodEnabled: terminalPeriodEnabled
        )
        return .init(
            deterministicText: deterministicText,
            shouldInvokeLLM: !isTrivial(transcript)
        )
    }

    static func postflight(
        deterministicText: String,
        llmOutput: String,
        textMode: TextMode,
        terminalPeriodEnabled: Bool = true,
        ignoredOutputLiterals: Set<String> = []
    ) -> NormalizationPipelinePostflight {
        let gateResult = NormalizationGate.evaluate(
            input: deterministicText,
            output: llmOutput,
            contract: textMode.llmOutputContract,
            ignoredOutputLiterals: ignoredOutputLiterals
        )
        let finalText = terminalPeriodEnabled
            ? gateResult.output
            : DeterministicNormalizer.stripTrailingPeriods(gateResult.output)

        return .init(
            finalText: finalText,
            path: gateResult.accepted ? .llm : .llmRejected,
            gateFailureReason: gateResult.failureReason,
            failureContext: nil
        )
    }

    static func failedPostflight(
        deterministicText: String,
        failureContext: String? = nil
    ) -> NormalizationPipelinePostflight {
        .init(
            finalText: deterministicText,
            path: .llmFailed,
            gateFailureReason: nil,
            failureContext: failureContext
        )
    }
}
