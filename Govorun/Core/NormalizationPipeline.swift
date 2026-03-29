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

    private static let structuredDigitWords: [String: String] = [
        "zero": "0",
        "one": "1",
        "two": "2",
        "three": "3",
        "four": "4",
        "five": "5",
        "six": "6",
        "seven": "7",
        "eight": "8",
        "nine": "9",
        "ноль": "0",
        "нуль": "0",
        "один": "1",
        "одна": "1",
        "два": "2",
        "две": "2",
        "три": "3",
        "четыре": "4",
        "пять": "5",
        "шесть": "6",
        "семь": "7",
        "восемь": "8",
        "девять": "9",
    ]

    private static let paperFormatDigits: [String: String] = [
        "0": "0",
        "1": "1",
        "2": "2",
        "3": "3",
        "4": "4",
        "5": "5",
        "ноль": "0",
        "один": "1",
        "одна": "1",
        "два": "2",
        "две": "2",
        "три": "3",
        "четыре": "4",
        "пять": "5",
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
        result = canonicalizeSurfaceForms(result)

        if terminalPeriodEnabled {
            if let last = result.last, !last.isPunctuation {
                result += "."
            }
        } else {
            result = stripTrailingPeriods(result)
        }

        return result
    }

    static func canonicalizeSurfaceForms(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = applyCanonicalLexicon(text)
        result = applyCanonicalFormatting(result)
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

        for (source, replacement) in canonicalWordReplacements {
            let escaped = NSRegularExpression.escapedPattern(for: source)
            result = result.replacingOccurrences(
                of: "\\b\(escaped)\\b",
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        for (source, replacement) in canonicalPhraseReplacements {
            let escaped = NSRegularExpression.escapedPattern(for: source)
            result = result.replacingOccurrences(
                of: "\\b\(escaped)\\b",
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return result
    }

    private static func applyCanonicalFormatting(_ text: String) -> String {
        var result = text
        result = carryForwardExplicitTimeOfDay(in: result)
        result = replaceNumberIdentifiers(in: result)
        result = replacePaperFormats(in: result)
        result = replaceProjectTitles(in: result)
        result = replaceMixedProductPhrases(in: result)
        result = replaceHyphenatedTechRoles(in: result)
        result = replaceUnitAbbreviations(in: result)
        result = replaceTemperatureForms(in: result)
        return result
    }

    private static func carryForwardExplicitTimeOfDay(in text: String) -> String {
        replacingMatches(in: text, regex: explicitTimeOfDayCorrectionPattern) { match, source in
            guard
                let prepositionRange = Range(match.range(at: 1), in: source),
                let timeOfDayRange = Range(match.range(at: 3), in: source),
                let correctedTimeRange = Range(match.range(at: 4), in: source)
            else {
                return matchedSubstring(for: match, in: source)
            }

            let preposition = String(source[prepositionRange])
            let timeOfDay = String(source[timeOfDayRange]).lowercased()
            let correctedTime = String(source[correctedTimeRange])
            return "\(preposition) \(correctedTime) \(timeOfDay)"
        }
    }

    private static func replaceNumberIdentifiers(in text: String) -> String {
        var result = replacingMatches(in: text, regex: numericIdentifierPattern) { match, source in
            guard let digitsRange = Range(match.range(at: 1), in: source) else {
                return matchedSubstring(for: match, in: source)
            }

            let digits = source[digitsRange].filter(\.isNumber)
            guard !digits.isEmpty else {
                return matchedSubstring(for: match, in: source)
            }

            return "№\(digits)"
        }

        result = replacingMatches(in: result, regex: spokenIdentifierPattern) { match, source in
            guard let sequenceRange = Range(match.range(at: 1), in: source) else {
                return matchedSubstring(for: match, in: source)
            }

            let words = source[sequenceRange]
                .split(whereSeparator: \.isWhitespace)
                .map { $0.lowercased() }
            let digits = words.compactMap { structuredDigitWords[$0] }.joined()
            guard digits.count == words.count else {
                return matchedSubstring(for: match, in: source)
            }

            return "№\(digits)"
        }

        return result
    }

    private static func replacePaperFormats(in text: String) -> String {
        replacingMatches(in: text, regex: paperFormatPattern) { match, source in
            guard
                let contextRange = Range(match.range(at: 1), in: source),
                let valueRange = Range(match.range(at: 2), in: source)
            else {
                return matchedSubstring(for: match, in: source)
            }

            let context = String(source[contextRange])
            let rawValue = String(source[valueRange]).lowercased()
            guard let digit = paperFormatDigits[rawValue] else {
                return matchedSubstring(for: match, in: source)
            }

            return "\(context) А\(digit)"
        }
    }

    private static func replaceProjectTitles(in text: String) -> String {
        replacingMatches(in: text, regex: projectTitlePattern) { match, source in
            guard
                let prefixRange = Range(match.range(at: 1), in: source),
                let titleRange = Range(match.range(at: 2), in: source)
            else {
                return matchedSubstring(for: match, in: source)
            }

            let prefix = String(source[prefixRange])
            let title = String(source[titleRange])
            return "\(prefix)«\(formatProjectTitle(title))»"
        }
    }

    private static func replaceMixedProductPhrases(in text: String) -> String {
        replacingMatches(in: text, regex: jiraServerPattern) { _, _ in
            "Jira Server"
        }
    }

    private static func replaceHyphenatedTechRoles(in text: String) -> String {
        replacingMatches(in: text, regex: techRolePattern) { match, source in
            guard
                let tokenRange = Range(match.range(at: 1), in: source),
                let roleRange = Range(match.range(at: 2), in: source)
            else {
                return matchedSubstring(for: match, in: source)
            }

            return "\(source[tokenRange])-\(source[roleRange])"
        }
    }

    private static func replaceUnitAbbreviations(in text: String) -> String {
        let patterns: [(NSRegularExpression, (String) -> String)] = [
            (unitPattern("\\d+(?:,\\d+)?", "кг"), { formatMeasuredUnit(number: $0, forms: ("килограмм", "килограмма", "килограммов")) }),
            (unitPattern("\\d+(?:,\\d+)?", "л"), { formatMeasuredUnit(number: $0, forms: ("литр", "литра", "литров")) }),
            (unitPattern("\\d+(?:,\\d+)?", "км"), { formatMeasuredUnit(number: $0, forms: ("километр", "километра", "километров")) }),
        ]

        var result = text
        for (regex, replacement) in patterns {
            result = replacingMatches(in: result, regex: regex) { match, source in
                guard let numberRange = Range(match.range(at: 1), in: source) else {
                    return matchedSubstring(for: match, in: source)
                }
                let number = String(source[numberRange])
                return replacement(number)
            }
        }
        return result
    }

    private static func replaceTemperatureForms(in text: String) -> String {
        var result = replacingMatches(in: text, regex: celsiusWordPattern) { match, source in
            guard let numberRange = Range(match.range(at: 1), in: source) else {
                return matchedSubstring(for: match, in: source)
            }
            return "\(source[numberRange])°C"
        }

        result = replacingMatches(in: result, regex: celsiusSpacingPattern) { match, source in
            guard let numberRange = Range(match.range(at: 1), in: source) else {
                return matchedSubstring(for: match, in: source)
            }
            return "\(source[numberRange])°C"
        }
        return result
    }

    private static func formatProjectTitle(_ title: String) -> String {
        title
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { word in
                let lowercased = word.lowercased()
                return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func formatMeasuredUnit(
        number: String,
        forms: (String, String, String)
    ) -> String {
        let normalized = number.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else {
            return "\(number) \(forms.2)"
        }
        let unit = pluralizedUnit(for: value, forms: forms)
        return "\(number) \(unit)"
    }

    private static func pluralizedUnit(
        for value: Double,
        forms: (String, String, String)
    ) -> String {
        if value.rounded(.down) != value {
            return forms.1
        }

        let intValue = abs(Int(value))
        let lastTwo = intValue % 100
        let lastOne = intValue % 10
        if (11...14).contains(lastTwo) {
            return forms.2
        }
        if lastOne == 1 {
            return forms.0
        }
        if (2...4).contains(lastOne) {
            return forms.1
        }
        return forms.2
    }

    private static func replacingMatches(
        in text: String,
        regex: NSRegularExpression,
        replacement: (NSTextCheckingResult, String) -> String
    ) -> String {
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(matchRange, with: replacement(match, result))
        }
        return result
    }

    private static func matchedSubstring(for match: NSTextCheckingResult, in source: String) -> String {
        guard let range = Range(match.range, in: source) else { return "" }
        return String(source[range])
    }

    private static func unitPattern(_ numberPattern: String, _ unit: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: "(?i)\\b(\(numberPattern))\\s*\(NSRegularExpression.escapedPattern(for: unit))\\b")
        } catch {
            fatalError("Invalid unit regex: \(error)")
        }
    }

    private static let celsiusWordPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: "(?i)\\b(\\d+(?:,\\d+)?)\\s+градус(?:а|ов)?(?:\\s+цельсия)?\\b")
        } catch {
            fatalError("Invalid celsius word regex: \(error)")
        }
    }()

    private static let celsiusSpacingPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: "(?i)\\b(\\d+(?:,\\d+)?)\\s*°\\s*c\\b")
        } catch {
            fatalError("Invalid celsius spacing regex: \(error)")
        }
    }()

    private static let explicitTimeOfDayCorrectionPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: "(?i)\\b(в|к|до|после)\\s+([\\p{L}\\d:]+)\\s+(утра|вечера|дня|ночи)(?:\\s+или\\s+нет)?\\s+(?:лучше|точнее|вернее)\\s+\\1\\s+([\\p{L}\\d:]+)\\b"
            )
        } catch {
            fatalError("Invalid explicit time-of-day correction regex: \(error)")
        }
    }()

    private static let numericIdentifierPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: "(?i)\\bномер\\s+(\\d(?:[\\d\\s]{0,14}\\d)?)\\b")
        } catch {
            fatalError("Invalid numeric identifier regex: \(error)")
        }
    }()

    private static let spokenIdentifierPattern: NSRegularExpression = {
        let digitPattern = structuredDigitWords.keys
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")

        do {
            return try NSRegularExpression(
                pattern: "(?i)\\bномер\\s+((?:\(digitPattern))(?:\\s+(?:\(digitPattern)))*)\\b"
            )
        } catch {
            fatalError("Invalid spoken identifier regex: \(error)")
        }
    }()

    private static let paperFormatPattern: NSRegularExpression = {
        let valuePattern = paperFormatDigits.keys
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")

        do {
            return try NSRegularExpression(
                pattern: "(?i)\\b(бумаг\\w*|лист\\w*|формат\\w*)[\\.,:]?\\s+[aа]\\s*(?:-|)?\\s*(\(valuePattern))\\b"
            )
        } catch {
            fatalError("Invalid paper format regex: \(error)")
        }
    }()

    private static let jiraServerPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: "(?i)\\bjira\\s+сервер(?:а|у|ом|е)?\\b")
        } catch {
            fatalError("Invalid Jira Server regex: \(error)")
        }
    }()

    private static let projectTitlePattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: "(по\\s+проекту\\s+)([А-ЯЁа-яё\\d-]+)",
                options: [.caseInsensitive]
            )
        } catch {
            fatalError("Invalid project title regex: \(error)")
        }
    }()

    private static let techRolePattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: "\\b(ML|iOS|QA)\\s+(инженер[а-яё]*|разработчик[а-яё]*)\\b",
                options: [.caseInsensitive]
            )
        } catch {
            fatalError("Invalid tech role regex: \(error)")
        }
    }()
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
        guard !text.isEmpty else { return false }
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
        contract: LLMOutputContract,
        terminalPeriodEnabled: Bool = true,
        ignoredOutputLiterals: Set<String> = []
    ) -> NormalizationPipelinePostflight {
        let canonicalOutput = DeterministicNormalizer.canonicalizeSurfaceForms(
            NumberNormalizer.normalize(llmOutput)
        )
        let gateResult = NormalizationGate.evaluate(
            input: deterministicText,
            output: canonicalOutput,
            contract: contract,
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
