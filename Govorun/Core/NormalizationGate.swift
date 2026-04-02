import Foundation

// MARK: - Контракт выхода LLM

enum LLMOutputContract: Equatable {
    case normalization
    case rewriting
}

// MARK: - Результат gate

enum NormalizationGateFailureReason: Equatable {
    case empty
    case refusal
    case disproportionateLength
    case missingProtectedTokens([String])
    case excessiveEdits(ratio: Double, threshold: Double)
    case invalidLengthRatio(actual: Double, allowed: ClosedRange<Double>)
}

extension NormalizationGateFailureReason: CustomStringConvertible {
    var analyticsValue: String {
        switch self {
        case .empty:
            "empty"
        case .refusal:
            "refusal"
        case .disproportionateLength:
            "disproportionate_length"
        case .missingProtectedTokens:
            "missing_protected_tokens"
        case .excessiveEdits:
            "excessive_edits"
        case .invalidLengthRatio:
            "invalid_length_ratio"
        }
    }

    var description: String {
        switch self {
        case .empty:
            "empty"
        case .refusal:
            "refusal"
        case .disproportionateLength:
            "disproportionate_length"
        case .missingProtectedTokens(let tokens):
            "missing_protected_tokens(\(tokens.joined(separator: ",")))"
        case .excessiveEdits(let ratio, let threshold):
            "excessive_edits(ratio=\(String(format: "%.3f", ratio)), threshold=\(String(format: "%.3f", threshold)))"
        case .invalidLengthRatio(let actual, let allowed):
            "invalid_length_ratio(actual=\(String(format: "%.3f", actual)), allowed=\(String(format: "%.3f", allowed.lowerBound))...\(String(format: "%.3f", allowed.upperBound)))"
        }
    }
}

struct NormalizationGateResult: Equatable {
    let output: String
    let failureReason: NormalizationGateFailureReason?

    var accepted: Bool {
        failureReason == nil
    }

    static func accepted(_ output: String) -> Self {
        Self(output: output, failureReason: nil)
    }

    static func rejected(
        fallback: String,
        reason: NormalizationGateFailureReason
    ) -> Self {
        Self(output: fallback, failureReason: reason)
    }
}

// MARK: - Gate

enum NormalizationGate {
    private static let correctionPhraseMarkers = [
        "ой точнее",
        "точнее",
        "то есть",
        "нет подожди",
        "в смысле",
        "я имею в виду",
        "имею в виду",
        "или нет",
        "хотя нет",
        "а нет",
    ]

    private static let standaloneNetRegex: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"(?<![\p{L}\p{N}_])нет(?![\p{L}\p{N}_])"#,
                options: [.caseInsensitive]
            )
        } catch {
            preconditionFailure("Невалидный regex correction marker: \(error)")
        }
    }()

    private static let protectedTokenPatterns = [
        #"https?://\S+"#,
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        #"\b[\p{Latin}][\p{Latin}\p{Number}_./:+-]*\b"#,
        #"\b[\p{Letter}\p{Number}_-]*\d[\p{Letter}\p{Number}_-]*\b"#,
        #"[₽$€¥]"#,
    ]

    private static let protectedTokenRegexes: [NSRegularExpression] = protectedTokenPatterns.map {
        do {
            return try NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Невалидный regex protected token pattern: \($0). Ошибка: \(error)")
        }
    }

    static func evaluate(
        input: String,
        output: String,
        contract: LLMOutputContract,
        superStyle: SuperTextStyle? = nil,
        ignoredOutputLiterals: Set<String> = []
    ) -> NormalizationGateResult {
        switch (contract, LLMResponseGuard.firstIssue(output, rawTranscript: input)) {
        case (_, .empty?):
            return .rejected(fallback: input, reason: .empty)
        case (_, .refusal?):
            return .rejected(fallback: input, reason: .refusal)
        case (.normalization, .disproportionateLength?):
            return .rejected(fallback: input, reason: .disproportionateLength)
        case (.rewriting, .disproportionateLength?),
             (_, nil):
            break
        }

        switch contract {
        case .normalization:
            return evaluateNormalization(
                input: input,
                output: output,
                ignoredOutputLiterals: ignoredOutputLiterals,
                superStyle: superStyle
            )
        case .rewriting:
            return evaluateRewriting(
                input: input,
                output: output,
                ignoredOutputLiterals: ignoredOutputLiterals,
                superStyle: superStyle
            )
        }
    }

    // MARK: - Нормализация

    private static func evaluateNormalization(
        input: String,
        output: String,
        ignoredOutputLiterals: Set<String>,
        superStyle: SuperTextStyle?
    ) -> NormalizationGateResult {
        let protectedTokens = protectedTokensForNormalization(input)
        let missingTokens = missingProtectedTokens(
            expected: protectedTokens,
            actualText: output,
            ignoredOutputLiterals: ignoredOutputLiterals,
            superStyle: superStyle
        )
        if !missingTokens.isEmpty {
            return .rejected(
                fallback: input,
                reason: .missingProtectedTokens(missingTokens)
            )
        }

        let inputTokens = normalizeStyleTokens(
            tokenizeForDistance(input), style: superStyle
        )
        let outputTokens = normalizeStyleTokens(
            tokenizeForDistance(output, ignoredLiterals: ignoredOutputLiterals),
            style: superStyle
        )

        guard !inputTokens.isEmpty else {
            return .accepted(output)
        }

        let distance = tokenEditDistance(lhs: inputTokens, rhs: outputTokens)
        let denominator = max(max(inputTokens.count, outputTokens.count), 1)
        let ratio = Double(distance)/Double(denominator)
        let threshold = editDistanceThreshold(for: inputTokens.count, input: input, style: superStyle)

        guard ratio <= threshold else {
            return .rejected(
                fallback: input,
                reason: .excessiveEdits(ratio: ratio, threshold: threshold)
            )
        }

        return .accepted(output)
    }

    // MARK: - Переписывание

    private static func evaluateRewriting(
        input: String,
        output: String,
        ignoredOutputLiterals: Set<String>,
        superStyle: SuperTextStyle?
    ) -> NormalizationGateResult {
        let protectedTokens = protectedTokensForNormalization(input)
        let missingTokens = missingProtectedTokens(
            expected: protectedTokens,
            actualText: output,
            ignoredOutputLiterals: ignoredOutputLiterals,
            superStyle: superStyle
        )
        if !missingTokens.isEmpty {
            return .rejected(
                fallback: input,
                reason: .missingProtectedTokens(missingTokens)
            )
        }

        let inputCount = max(tokenizeForDistance(input).count, 1)
        let outputCount = tokenizeForDistance(
            output,
            ignoredLiterals: ignoredOutputLiterals
        ).count
        let ratio = Double(outputCount)/Double(inputCount)
        let allowed = 0.5...1.5

        guard allowed.contains(ratio) else {
            return .rejected(
                fallback: input,
                reason: .invalidLengthRatio(actual: ratio, allowed: allowed)
            )
        }

        return .accepted(output)
    }

    // MARK: - Эвристики

    private static func protectedTokensForNormalization(_ input: String) -> [String] {
        let source = correctionAwareProtectedSource(in: input)
        var tokens = Set<String>()

        for regex in protectedTokenRegexes {
            tokens.formUnion(matches(of: regex, in: source))
        }

        return tokens.sorted()
    }

    private static func correctionAwareProtectedSource(in input: String) -> String {
        guard let marker = lastCorrectionMarkerRange(in: input)
        else {
            return input
        }

        let tail = String(input[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return tail.isEmpty ? input : tail
    }

    // MARK: - Алиас-таблицы

    private static let relaxedAliasLookup: [String: String] = {
        var dict = [String: String]()
        for alias in SuperTextStyle.brandAliases {
            let canonOriginal = canonicalize(alias.original)
            let canonRelaxed = canonicalize(alias.relaxed)
            dict[canonRelaxed] = canonOriginal
            dict[canonOriginal] = canonOriginal
        }
        for alias in SuperTextStyle.techTermAliases {
            let canonOriginal = canonicalize(alias.original)
            let canonRelaxed = canonicalize(alias.relaxed)
            dict[canonRelaxed] = canonOriginal
            dict[canonOriginal] = canonOriginal
        }
        return dict
    }()

    private static let formalAliasLookup: [String: String] = {
        var dict = [String: String]()
        for pair in SuperTextStyle.slangExpansions {
            let canonSlang = canonicalize(pair.slang)
            let canonFull = canonicalize(pair.full)
            dict[canonSlang] = canonFull
            dict[canonFull] = canonFull
        }
        return dict
    }()

    private static func aliasLookup(for style: SuperTextStyle?) -> [String: String] {
        switch style {
        case .relaxed: relaxedAliasLookup
        case .formal: formalAliasLookup
        case .normal, nil: [:]
        }
    }

    private static func missingProtectedTokens(
        expected: [String],
        actualText: String,
        ignoredOutputLiterals: Set<String>,
        superStyle: SuperTextStyle?
    ) -> [String] {
        let actualCanonical = Set(
            extractProtectedTokens(
                from: actualText,
                ignoredLiterals: ignoredOutputLiterals
            )
        )
        let lookup = aliasLookup(for: superStyle)

        // Все слова output для алиас-проверки (Cyrillic алиасы не попадают в protectedTokenRegexes)
        let allOutputWords: Set<String> = {
            guard !lookup.isEmpty else { return [] }
            return Set(
                tokenizeForDistance(actualText, ignoredLiterals: ignoredOutputLiterals)
            )
        }()

        return expected.filter { token in
            let canon = canonicalize(token)
            if actualCanonical.contains(canon) { return false }
            if let canonical = lookup[canon], actualCanonical.contains(canonical) || allOutputWords.contains(canonical) { return false }
            for (variant, target) in lookup where target == canon {
                if actualCanonical.contains(variant) || allOutputWords.contains(variant) { return false }
            }
            return true
        }
    }

    private static func extractProtectedTokens(
        from text: String,
        ignoredLiterals: Set<String> = []
    ) -> [String] {
        var tokens = Set<String>()
        let sanitizedText = stripIgnoredLiterals(
            in: text,
            ignoredLiterals: ignoredLiterals
        )

        for regex in protectedTokenRegexes {
            tokens.formUnion(matches(of: regex, in: sanitizedText))
        }
        return Array(tokens)
    }

    private static func matches(of regex: NSRegularExpression, in text: String) -> Set<String> {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: nsRange)

        return Set(
            matches.compactMap { match in
                guard match.range.location != NSNotFound else { return nil }
                return canonicalize(nsText.substring(with: match.range))
            }
        )
    }

    private static func normalizeStyleTokens(
        _ tokens: [String],
        style: SuperTextStyle?
    ) -> [String] {
        let lookup = aliasLookup(for: style)
        guard !lookup.isEmpty else { return tokens }
        return tokens.flatMap { token -> [String] in
            if let canonical = lookup[token] {
                let parts = canonical.split(whereSeparator: \.isWhitespace).map(String.init)
                return parts.isEmpty ? [token] : parts
            }
            return [token]
        }
    }

    private static func editDistanceThreshold(
        for tokenCount: Int,
        input: String,
        style: SuperTextStyle?
    ) -> Double {
        if hasCorrectionCue(input) {
            return 0.8
        }

        switch style {
        case .relaxed, .formal:
            return tokenCount < 10 ? 0.35 : 0.50
        case .normal, nil:
            return tokenCount < 10 ? 0.25 : 0.4
        }
    }

    private static func hasCorrectionCue(_ input: String) -> Bool {
        lastCorrectionMarkerRange(in: input) != nil
    }

    private static func lastCorrectionMarkerRange(in input: String) -> Range<String.Index>? {
        let phraseRanges = correctionPhraseMarkers.compactMap {
            input.range(of: $0, options: [.caseInsensitive, .backwards])
        }
        let standaloneRanges = matchRanges(of: standaloneNetRegex, in: input).filter { standaloneRange in
            !phraseRanges.contains(where: { $0.overlaps(standaloneRange) })
        }

        return (phraseRanges + standaloneRanges).max(by: { $0.lowerBound < $1.lowerBound })
    }

    private static func matchRanges(
        of regex: NSRegularExpression,
        in text: String
    ) -> [Range<String.Index>] {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsRange).compactMap {
            Range($0.range, in: text)
        }
    }

    private static func tokenizeForDistance(
        _ text: String,
        ignoredLiterals: Set<String> = []
    ) -> [String] {
        stripIgnoredLiterals(in: text, ignoredLiterals: ignoredLiterals)
            .split(whereSeparator: \.isWhitespace)
            .map {
                canonicalize(
                    String($0).trimmingCharacters(in: .punctuationCharacters)
                )
            }
            .filter { !$0.isEmpty }
    }

    private static func stripIgnoredLiterals(
        in text: String,
        ignoredLiterals: Set<String>
    ) -> String {
        guard !ignoredLiterals.isEmpty else { return text }

        var result = text
        for literal in ignoredLiterals where !literal.isEmpty {
            result = result.replacingOccurrences(of: literal, with: " ")
        }
        return result
    }

    private static func canonicalize(_ token: String) -> String {
        token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()
    }

    private static func tokenEditDistance(
        lhs: [String],
        rhs: [String]
    ) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)

        for (leftIndex, leftToken) in lhs.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(rhs.count + 1)

            for (rightIndex, rightToken) in rhs.enumerated() {
                let substitutionCost = leftToken == rightToken ? 0 : 1
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + substitutionCost
                current.append(min(insertion, deletion, substitution))
            }

            previous = current
        }

        return previous[rhs.count]
    }
}
