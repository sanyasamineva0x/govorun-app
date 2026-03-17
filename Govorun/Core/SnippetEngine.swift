import Foundation

// MARK: - SnippetRecord (lightweight, для Core/)

struct SnippetRecord: Sendable {
    let trigger: String
    let content: String
    let matchMode: MatchMode
    let isEnabled: Bool
}

// MARK: - SnippetEngine

final class SnippetEngine: SnippetMatching, @unchecked Sendable {

    private let lock = NSLock()
    private var snippets: [SnippetRecord] = []

    func updateSnippets(_ snippets: [SnippetRecord]) {
        lock.lock()
        self.snippets = snippets
        lock.unlock()
    }

    func match(_ text: String) -> SnippetMatch? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        lock.lock()
        let current = snippets
        lock.unlock()

        // 1. Standalone — весь транскрипт ≈ триггер (exact + fuzzy)
        for snippet in current where snippet.isEnabled {
            let trigger = snippet.trigger.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if standaloneMatch(normalized, trigger: trigger, mode: snippet.matchMode) {
                return SnippetMatch(trigger: snippet.trigger, content: snippet.content, kind: .standalone)
            }
        }

        // 2. Embedded — триггер внутри фразы (longest trigger first, EXACT ONLY)
        let sorted = current.filter(\.isEnabled).sorted { $0.trigger.count > $1.trigger.count }
        for snippet in sorted {
            let trigger = snippet.trigger.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if embeddedExact(normalized, trigger: trigger) {
                return SnippetMatch(trigger: snippet.trigger, content: snippet.content, kind: .embedded)
            }
        }

        return nil
    }

    // MARK: - Standalone Match

    private func standaloneMatch(_ normalized: String, trigger: String, mode: MatchMode) -> Bool {
        switch mode {
        case .exact:
            return Self.tokenize(normalized) == Self.tokenize(trigger)
        case .fuzzy:
            let normTokens = Self.tokenize(normalized).joined(separator: " ")
            let trigTokens = Self.tokenize(trigger).joined(separator: " ")
            let distance = SnippetEngine.levenshteinDistance(normTokens, trigTokens)
            let threshold = Int(ceil(Double(trigTokens.count) * 0.3))
            return distance <= threshold
        }
    }

    // MARK: - Embedded Exact Match

    private func embeddedExact(_ text: String, trigger: String) -> Bool {
        let textTokens = Self.tokenize(text)
        let triggerTokens = Self.tokenize(trigger)
        let windowSize = triggerTokens.count
        guard textTokens.count > windowSize else { return false }

        for i in 0...(textTokens.count - windowSize) {
            let window = Array(textTokens[i..<(i + windowSize)])
            if window == triggerTokens { return true }
        }
        return false
    }

    // MARK: - Tokenize

    static func tokenize(_ text: String) -> [String] {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let collapsed = lowered.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )

        return collapsed.split(separator: " ").compactMap { word in
            let stripped = word.trimmingCharacters(in: .punctuationCharacters)
            return stripped.isEmpty ? nil : stripped
        }
    }

    // MARK: - Levenshtein Distance

    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        // Одна строка DP (оптимизация по памяти)
        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,         // удаление
                    curr[j - 1] + 1,     // вставка
                    prev[j - 1] + cost   // замена
                )
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }
}
