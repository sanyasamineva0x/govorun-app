import Foundation

enum ListFormatter {
    // MARK: - Семьи маркеров

    private enum ListStyle {
        case numbered
        case dashed
    }

    private struct MarkerFamily {
        let markers: [String]
        let style: ListStyle
        let minCount: Int
    }

    private static let numberedFamilies: [MarkerFamily] = [
        MarkerFamily(markers: [
            "первое", "второе", "третье", "четвёртое", "пятое",
            "шестое", "седьмое", "восьмое", "девятое", "десятое",
        ], style: .numbered, minCount: 2),
        MarkerFamily(markers: [
            "во-первых", "во-вторых", "в-третьих", "в-четвёртых", "в-пятых",
        ], style: .numbered, minCount: 2),
        MarkerFamily(markers: [
            "пункт один", "пункт два", "пункт три", "пункт четыре", "пункт пять",
            "пункт шесть", "пункт семь", "пункт восемь", "пункт девять", "пункт десять",
        ], style: .numbered, minCount: 2),
    ]

    private static let dashedFamilies: [MarkerFamily] = [
        MarkerFamily(markers: [
            "кроме того", "помимо этого", "а также",
        ], style: .dashed, minCount: 2),
        MarkerFamily(markers: [
            "плюс", "также", "ещё", "далее",
        ], style: .dashed, minCount: 3),
    ]

    private static let allFamilies: [MarkerFamily] = numberedFamilies + dashedFamilies

    // MARK: - Public API

    static func format(_ text: String, style: SuperTextStyle? = nil) -> String {
        guard !text.isEmpty else { return "" }

        let lowered = text.lowercased()

        guard let (family, positions) = detectFamily(in: lowered) else {
            return text
        }

        let extracted = extractItems(from: text, positions: positions)
        let nonEmptyItems = extracted.items.filter { !$0.isEmpty }
        guard nonEmptyItems.count >= 2 else { return text }

        let capitalize = style != .relaxed

        return buildList(
            header: extracted.header,
            items: nonEmptyItems,
            style: family.style,
            capitalize: capitalize
        )
    }

    // MARK: - Детекция

    private static func detectFamily(
        in lowered: String
    ) -> (family: MarkerFamily, positions: [(range: Range<String.Index>, marker: String)])? {
        var bestFamily: MarkerFamily?
        var bestPositions: [(range: Range<String.Index>, marker: String)] = []

        for family in allFamilies {
            let positions = findMarkerPositions(in: lowered, markers: family.markers)
            guard positions.count >= family.minCount else { continue }

            let isNumbered = family.style == .numbered
            let bestIsNumbered = bestFamily?.style == .numbered

            if bestFamily == nil
                || (isNumbered && !bestIsNumbered)
                || (isNumbered == bestIsNumbered && positions.count > bestPositions.count)
            {
                bestFamily = family
                bestPositions = positions
            }
        }

        guard let family = bestFamily else { return nil }
        return (family, bestPositions)
    }

    private static func findMarkerPositions(
        in lowered: String,
        markers: [String]
    ) -> [(range: Range<String.Index>, marker: String)] {
        var positions: [(range: Range<String.Index>, marker: String)] = []
        var occupied: [Range<String.Index>] = []

        let sorted = markers.sorted { $0.count > $1.count }

        for marker in sorted {
            var searchStart = lowered.startIndex
            while let range = lowered.range(of: marker, range: searchStart..<lowered.endIndex) {
                let isWordStart = range.lowerBound == lowered.startIndex
                    || lowered[lowered.index(before: range.lowerBound)].isWhitespace
                let isWordEnd = range.upperBound == lowered.endIndex
                    || lowered[range.upperBound].isWhitespace
                    || lowered[range.upperBound].isPunctuation

                let overlaps = occupied.contains { $0.overlaps(range) }

                if isWordStart, isWordEnd, !overlaps {
                    positions.append((range, marker))
                    occupied.append(range)
                }
                searchStart = range.upperBound
            }
        }

        positions.sort { $0.range.lowerBound < $1.range.lowerBound }
        return positions
    }

    // MARK: - Извлечение пунктов

    private static func extractItems(
        from text: String,
        positions: [(range: Range<String.Index>, marker: String)]
    ) -> (header: String?, items: [String]) {
        var items: [String] = []
        let header: String?

        let firstPos = positions[0]
        let beforeFirst = String(text[text.startIndex..<firstPos.range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        header = beforeFirst.isEmpty ? nil : beforeFirst

        for i in 0..<positions.count {
            let start = positions[i].range.upperBound
            let end = i + 1 < positions.count
                ? positions[i + 1].range.lowerBound
                : text.endIndex
            let raw = String(text[start..<end])
            let cleaned = cleanItem(raw)
            items.append(cleaned)
        }

        return (header, items)
    }

    private static let leadingPunctuation: Set<Character> = [",", ":", "-", "–", "—"]
    private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?"]

    private static func cleanItem(_ raw: String) -> String {
        var s = raw

        while let first = s.first(where: { !$0.isWhitespace }) {
            if leadingPunctuation.contains(first) {
                s = String(s.drop(while: { $0.isWhitespace || leadingPunctuation.contains($0) }))
            } else {
                break
            }
        }

        s = s.trimmingCharacters(in: .whitespaces)

        while let last = s.last, trailingPunctuation.contains(last) {
            s = String(s.dropLast())
        }

        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Сборка списка

    private static func buildList(
        header: String?,
        items: [String],
        style: ListStyle,
        capitalize: Bool
    ) -> String {
        var lines: [String] = []

        if let header {
            lines.append(header)
        }

        for (i, item) in items.enumerated() {
            let formatted = capitalize ? capitalizeFirst(item) : item
            switch style {
            case .numbered:
                lines.append("\(i + 1). \(formatted)")
            case .dashed:
                lines.append("– \(formatted)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
