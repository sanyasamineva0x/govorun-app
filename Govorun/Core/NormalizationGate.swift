import Foundation

// MARK: - LLM Output Contract

enum LLMOutputContract: Equatable {
    case normalization
    case rewriting
}

extension TextMode {
    var llmOutputContract: LLMOutputContract {
        .normalization
    }
}

// MARK: - Gate Result

enum NormalizationGateFailureReason: Equatable {
    case empty
    case refusal
    case disproportionateLength
    case missingProtectedTokens([String])
    case excessiveEdits(ratio: Double, threshold: Double)
    case invalidLengthRatio(actual: Double, allowed: ClosedRange<Double>)
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
    private static let correctionMarkers = [
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
        " нет ",
    ]

    private static let protectedTokenPatterns = [
        #"https?://\S+"#,
        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        #"\b[\p{Latin}][\p{Latin}\p{Number}_./:+-]*\b"#,
        #"\b[\p{Letter}\p{Number}_-]*\d[\p{Letter}\p{Number}_-]*\b"#,
        #"[₽$€¥]"#,
    ]

    static func evaluate(
        input: String,
        output: String,
        contract: LLMOutputContract
    ) -> NormalizationGateResult {
        switch LLMResponseGuard.firstIssue(output, rawTranscript: input) {
        case .empty?:
            return .rejected(fallback: input, reason: .empty)
        case .refusal?:
            return .rejected(fallback: input, reason: .refusal)
        case .disproportionateLength?:
            return .rejected(fallback: input, reason: .disproportionateLength)
        case nil:
            break
        }

        switch contract {
        case .normalization:
            return evaluateNormalization(input: input, output: output)
        case .rewriting:
            return evaluateRewriting(input: input, output: output)
        }
    }

    // MARK: - Normalization

    private static func evaluateNormalization(
        input: String,
        output: String
    ) -> NormalizationGateResult {
        let protectedTokens = protectedTokensForNormalization(input)
        let missingTokens = missingProtectedTokens(
            expected: protectedTokens,
            actualText: output
        )
        if !missingTokens.isEmpty {
            return .rejected(
                fallback: input,
                reason: .missingProtectedTokens(missingTokens)
            )
        }

        let inputTokens = tokenizeForDistance(input)
        let outputTokens = tokenizeForDistance(output)

        guard !inputTokens.isEmpty else {
            return .accepted(output)
        }

        let distance = tokenEditDistance(lhs: inputTokens, rhs: outputTokens)
        let denominator = max(max(inputTokens.count, outputTokens.count), 1)
        let ratio = Double(distance)/Double(denominator)
        let threshold = editDistanceThreshold(for: inputTokens.count, input: input)

        guard ratio <= threshold else {
            return .rejected(
                fallback: input,
                reason: .excessiveEdits(ratio: ratio, threshold: threshold)
            )
        }

        return .accepted(output)
    }

    // MARK: - Rewriting

    private static func evaluateRewriting(
        input: String,
        output: String
    ) -> NormalizationGateResult {
        let protectedTokens = protectedTokensForNormalization(input)
        let missingTokens = missingProtectedTokens(
            expected: protectedTokens,
            actualText: output
        )
        if !missingTokens.isEmpty {
            return .rejected(
                fallback: input,
                reason: .missingProtectedTokens(missingTokens)
            )
        }

        let inputCount = max(tokenizeForDistance(input).count, 1)
        let outputCount = tokenizeForDistance(output).count
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

    // MARK: - Heuristics

    private static func protectedTokensForNormalization(_ input: String) -> [String] {
        let source = correctionAwareProtectedSource(in: input)
        var tokens = Set<String>()

        for pattern in protectedTokenPatterns {
            tokens.formUnion(matches(of: pattern, in: source))
        }

        return tokens.sorted()
    }

    private static func correctionAwareProtectedSource(in input: String) -> String {
        let lowered = " " + input.lowercased() + " "

        guard let marker = correctionMarkers
            .compactMap({ lowered.range(of: $0, options: [.caseInsensitive, .backwards]) })
            .max(by: { $0.lowerBound < $1.lowerBound })
        else {
            return input
        }

        let offset = lowered.distance(from: lowered.startIndex, to: marker.upperBound)
        let originalStart = input.index(
            input.startIndex,
            offsetBy: max(offset - 2, 0),
            limitedBy: input.endIndex
        ) ?? input.startIndex
        let tail = String(input[originalStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return tail.isEmpty ? input : String(tail)
    }

    private static func missingProtectedTokens(
        expected: [String],
        actualText: String
    ) -> [String] {
        let actualCanonical = Set(expectedTokens(in: actualText))
        return expected.filter { !actualCanonical.contains(canonicalize($0)) }
    }

    private static func expectedTokens(in text: String) -> [String] {
        var tokens = Set<String>()
        for pattern in protectedTokenPatterns {
            tokens.formUnion(matches(of: pattern, in: text))
        }
        return Array(tokens)
    }

    private static func matches(of pattern: String, in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }

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

    private static func editDistanceThreshold(for tokenCount: Int, input: String) -> Double {
        if hasCorrectionCue(input) {
            return 0.8
        }

        return tokenCount < 10 ? 0.25 : 0.4
    }

    private static func hasCorrectionCue(_ input: String) -> Bool {
        let lowered = " " + input.lowercased() + " "
        return correctionMarkers.contains(where: { lowered.contains($0) })
    }

    private static func tokenizeForDistance(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map {
                canonicalize(
                    String($0).trimmingCharacters(in: .punctuationCharacters)
                )
            }
            .filter { !$0.isEmpty }
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
