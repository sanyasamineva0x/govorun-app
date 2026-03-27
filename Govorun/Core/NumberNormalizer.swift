import Foundation

/// Детерминистическая нормализация русских числительных
enum NumberNormalizer {
    // MARK: - Token (v2)

    private struct Token: Equatable {
        var leading: String // «, (, [, "
        var core: String // слово, число, символ
        var trailing: String // ., ,, !, ?, ;, :, ), ], », "
    }

    /// Символы-ведущая пунктуация
    private static let leadingPunctuation: Set<Character> = [
        "«", "(", "[", "\"", "'", "\u{201E}", "\u{201C}", "\u{2039}", "\u{2014}",
    ]

    /// Символы-замыкающая пунктуация
    private static let trailingPunctuation: Set<Character> = [
        ".", ",", "!", "?", ";", ":", ")", "]", "»", "\"", "'", "\u{201D}", "\u{203A}", "\u{2026}", "\u{2014}",
    ]

    /// Контентные символы — остаются в core
    private static let contentSymbols: Set<Character> = ["%", "₽", "$", "€", "№", "-"]

    private static func tokenize(_ text: String) -> [Token] {
        let chunks = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return chunks.map { chunk in
            var leading = ""
            var trailing = ""
            var chars = Array(chunk)

            // Отделить leading пунктуацию
            while let first = chars.first,
                  leadingPunctuation.contains(first), !contentSymbols.contains(first)
            {
                leading.append(first)
                chars.removeFirst()
            }

            // Отделить trailing пунктуацию
            while let last = chars.last,
                  trailingPunctuation.contains(last), !contentSymbols.contains(last)
            {
                trailing.insert(last, at: trailing.startIndex)
                chars.removeLast()
            }

            return Token(leading: leading, core: String(chars), trailing: trailing)
        }
    }

    private static func render(_ tokens: [Token]) -> String {
        tokens.map { $0.leading + $0.core + $0.trailing }.joined(separator: " ")
    }

    /// Roundtrip для тестирования: tokenize → render
    static func tokenizeRoundtrip(_ text: String) -> String {
        render(tokenize(text))
    }

    // MARK: - Replace helper (v2)

    private static func replace(
        _ tokens: inout [Token],
        range: ClosedRange<Int>,
        with core: String,
        carryTrailingFrom lastIdx: Int
    ) {
        guard range.lowerBound >= 0,
              range.upperBound < tokens.count,
              lastIdx >= 0,
              lastIdx < tokens.count
        else {
            print("[Govorun] replace() out of bounds: range=\(range), lastIdx=\(lastIdx), count=\(tokens.count)")
            assertionFailure("replace() out of bounds")
            return
        }
        let trailing = tokens[lastIdx].trailing
        let leading = tokens[range.lowerBound].leading
        tokens.replaceSubrange(range, with: [
            Token(leading: leading, core: core, trailing: trailing),
        ])
    }

    // MARK: - Span model (v2)

    private enum SpanKind {
        case percent(Double)
        case money(amount: Double, currency: Currency, kopecks: Int?)
        case time(hour: Int, minute: Int)
        case duration(value: Double, unit: DurationUnit)
        case date(day: Int, month: String, year: Int?)
        case ordinal(value: Int, suffix: String)
        case cardinal(Double)
        case expandedAbbreviation(Double)
        case currencySymbolToWord(Double, Currency)
        case formattedNumber(Double)
    }

    private enum DurationUnit: String {
        case hours, minutes
    }

    private struct Span {
        let range: Range<Int>
        let kind: SpanKind
        let priority: Int
    }

    /// Приоритеты — выше = побеждает при конфликте
    private enum SpanPriority {
        static let money = 100
        static let time = 90
        static let date = 85
        static let percent = 80
        static let currencySymbol = 75
        static let abbreviation = 70
        static let ordinal = 60
        static let duration = 55
        static let formattedNumber = 50
        static let cardinal = 40
    }

    // Конфликт-резолюция: greedy по приоритету
    private static func resolveConflicts(_ spans: [Span]) -> [Span] {
        let sorted = spans.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            return $0.range.count > $1.range.count
        }
        var accepted: [Span] = []
        var occupiedIndices = Set<Int>()

        for span in sorted {
            let indices = Set(span.range)
            if indices.isDisjoint(with: occupiedIndices) {
                accepted.append(span)
                occupiedIndices.formUnion(indices)
            }
        }

        // Сортировать по позиции для применения справа налево
        return accepted.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    // MARK: - Currency (v2)

    private enum Currency: String {
        case rub, usd, eur

        static let symbols: [String: Currency] = [
            "\u{20BD}": .rub, "руб": .rub,
            "$": .usd, "\u{20AC}": .eur,
        ]

        static let wordForms: [String: Currency] = [
            "рубль": .rub, "рубля": .rub, "рублей": .rub,
            "рублям": .rub, "рублями": .rub, "рублях": .rub, "руб": .rub,
            "доллар": .usd, "доллара": .usd, "долларов": .usd,
            "долларам": .usd, "долларами": .usd, "долларах": .usd,
            "евро": .eur,
        ]

        func form(for value: Double) -> String {
            let absVal = abs(value)
            guard absVal <= Double(Int.max) else {
                switch self {
                case .rub: return "рублей"
                case .usd: return "долларов"
                case .eur: return "евро"
                }
            }
            let int = Int(absVal)
            let lastTwo = int % 100
            let lastOne = int % 10

            let idx = if lastTwo >= 11, lastTwo <= 14 {
                2
            } else if lastOne == 1 {
                0
            } else if lastOne >= 2, lastOne <= 4 {
                1
            } else {
                2
            }

            switch self {
            case .rub: return ["рубль", "рубля", "рублей"][idx]
            case .usd: return ["доллар", "доллара", "долларов"][idx]
            case .eur: return "евро"
            }
        }

        func subunitForm(for value: Int) -> String? {
            guard self == .rub else { return nil }

            let absVal = abs(value)
            let lastTwo = absVal % 100
            let lastOne = absVal % 10

            if (11...14).contains(lastTwo) {
                return "копеек"
            }
            if lastOne == 1 {
                return "копейка"
            }
            if (2...4).contains(lastOne) {
                return "копейки"
            }
            return "копеек"
        }
    }

    // MARK: - Multiplier abbreviations (v2)

    private static let multiplierAbbreviations: [String: Double] = [
        "тыс": 1_000, "тыс.": 1_000,
        "млн": 1_000_000, "млн.": 1_000_000,
        "млрд": 1_000_000_000, "млрд.": 1_000_000_000,
    ]

    // MARK: - Numeric parser (v2)

    /// Парсит цифровой токен из потока Token: 1 000, 2,5, 2000000, 1 000₽, 2 млн
    /// Возвращает (value, consumed, currency?, isAbbreviated?)
    private struct NumericParseResult {
        let value: Double
        let consumed: Int
        let currency: Currency?
        let isAbbreviated: Bool // 2 млн → true
    }

    private static func parseNumericNumber(_ tokens: [Token], at start: Int) -> NumericParseResult? {
        guard start < tokens.count else { return nil }
        let firstCore = tokens[start].core

        // Первый токен должен начинаться с цифры
        guard let firstChar = firstCore.first, firstChar.isNumber else { return nil }

        // Разобрать core: может содержать валютный символ в конце (1000₽)
        var numericPart = firstCore
        var embeddedCurrency: Currency? = nil

        // Проверить встроенный символ валюты в конце
        if let lastChar = numericPart.last, let curr = Currency.symbols[String(lastChar)] {
            embeddedCurrency = curr
            numericPart = String(numericPart.dropLast())
        }

        // Парсить число: поддержка запятой как десятичного разделителя
        guard let baseValue = parseDecimalString(numericPart) else { return nil }

        var value = baseValue
        var consumed = 1
        var currency = embeddedCurrency
        var isAbbreviated = false

        // Следующие токены: пробельные группы (1 000 000) или сокращения (млн, тыс)
        if embeddedCurrency == nil {
            // Попробовать склеить пробельно-разделённое число: 1 000, 1 000 000
            if let spaceGrouped = tryParseSpaceGroupedNumber(tokens, startIdx: start, baseStr: numericPart),
               spaceGrouped.consumed > 1
            {
                value = spaceGrouped.value
                consumed = spaceGrouped.consumed

                // Проверить валютный символ в последнем потреблённом токене
                let lastCore = tokens[start + consumed - 1].core
                if let lastChar = lastCore.last, let curr = Currency.symbols[String(lastChar)] {
                    currency = curr
                    // Пересчитать без символа
                    let cleanLast = String(lastCore.dropLast())
                    if let cleanVal = parseDecimalString(cleanLast) {
                        let prefix = tokens[start..<(start + consumed - 1)].map(\.core).joined()
                        if let fullVal = parseDecimalString(prefix + cleanLast) {
                            value = fullVal
                        } else {
                            value = cleanVal
                        }
                    }
                }
            }

            // Проверить сокращение-множитель после числа
            if start + consumed < tokens.count {
                let nextCore = tokens[start + consumed].core.lowercased()
                if let mult = multiplierAbbreviations[nextCore] {
                    value *= mult
                    consumed += 1
                    isAbbreviated = true
                }
            }

            // Проверить валютный символ как отдельный токен после числа
            if currency == nil, start + consumed < tokens.count {
                let nextCore = tokens[start + consumed].core
                if let curr = Currency.symbols[nextCore] {
                    currency = curr
                    consumed += 1
                }
            }
        }

        return NumericParseResult(value: value, consumed: consumed, currency: currency, isAbbreviated: isAbbreviated)
    }

    /// Парсить строку как число (запятая = десятичный разделитель)
    private static func parseDecimalString(_ s: String) -> Double? {
        guard !s.isEmpty else { return nil }
        let normalized = s.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    /// Склеить пробельно-разделённое число: "1" "000" "000" → 1000000
    private static func tryParseSpaceGroupedNumber(
        _ tokens: [Token], startIdx: Int, baseStr: String
    ) -> (value: Double, consumed: Int)? {
        var accumulated = baseStr
        var consumed = 1
        var idx = startIdx + 1

        while idx < tokens.count {
            let core = tokens[idx].core
            // Группа из 3 цифр (возможно с валютным символом в конце)
            var digits = core
            if let last = digits.last, Currency.symbols[String(last)] != nil {
                digits = String(digits.dropLast())
            }
            guard digits.count == 3, digits.allSatisfy(\.isNumber) else { break }
            // Предыдущий токен не должен иметь trailing пунктуацию
            guard tokens[idx - 1].trailing.isEmpty else { break }
            accumulated += digits
            consumed += 1
            idx += 1
        }

        guard consumed > 1, let val = Double(accumulated) else {
            guard let baseVal = Double(baseStr) else { return nil }
            return (baseVal, 1)
        }
        return (val, consumed)
        // consumed == 1 fallback не используется (call site проверяет consumed > 1),
        // но возвращаем корректное значение а не nil для forward compatibility
    }

    /// Тестовый доступ для numeric parser
    static func testParseNumeric(_ text: String) -> (value: Double, consumed: Int, currency: String?, abbreviated: Bool)? {
        let tokens = tokenize(text)
        guard let result = parseNumericNumber(tokens, at: 0) else { return nil }
        return (result.value, result.consumed, result.currency?.rawValue, result.isAbbreviated)
    }

    // Тестовый доступ для conflict resolution
    // spans: [(lowerBound, upperBound, priority, label)]
    // Возвращает labels принятых спанов в порядке позиции
    static func testResolveConflicts(_ spans: [(Int, Int, Int, String)]) -> [String] {
        let testSpans = spans.map { lb, ub, prio, _ in
            Span(range: lb..<ub, kind: .cardinal(0), priority: prio)
        }
        let resolved = resolveConflicts(testSpans)
        return resolved.compactMap { r in
            spans.first(where: {
                $0.0 == r.range.lowerBound && $0.1 == r.range.upperBound && $0.2 == r.priority
            })?.3
        }
    }

    // MARK: - CanonicalFormatter (v2)

    private enum CanonicalFormatter {
        static func formatInteger(_ value: Double) -> String {
            NumberNormalizer.formatNumber(value)
        }

        static func formatPercent(_ value: Double) -> String {
            NumberNormalizer.formatNumber(value) + "%"
        }

        static func formatMoney(_ value: Double, _ currency: Currency, kopecks: Int? = nil) -> String {
            var result = NumberNormalizer.formatNumber(value) + " " + currency.form(for: value)
            if let kopecks, let subunit = currency.subunitForm(for: kopecks) {
                result += " \(kopecks) \(subunit)"
            }
            return result
        }

        static func formatTime(_ hour: Int, _ minute: Int) -> String {
            String(format: "%d:%02d", hour, minute)
        }

        static func formatDuration(_ value: Double, _ unit: DurationUnit) -> String {
            // Длительность: оставляем единицу как есть (слово-триггер сохраняется отдельно)
            NumberNormalizer.formatNumber(value)
        }

        static func formatOrdinal(_ value: Int, _ suffix: String) -> String {
            "\(value)\(suffix)"
        }
    }

    /// Тестовый доступ к CanonicalFormatter
    static func testFormatPercent(_ value: Double) -> String {
        CanonicalFormatter.formatPercent(value)
    }

    static func testFormatMoney(_ value: Double, currency: String) -> String? {
        guard let curr = Currency(rawValue: currency) else { return nil }
        return CanonicalFormatter.formatMoney(value, curr)
    }

    static func testFormatTime(_ hour: Int, _ minute: Int) -> String {
        CanonicalFormatter.formatTime(hour, minute)
    }

    static func testFormatOrdinal(_ value: Int, _ suffix: String) -> String {
        CanonicalFormatter.formatOrdinal(value, suffix)
    }

    // MARK: - Span parsers (v2)

    /// Парсить слово-число из токена (кардинал, спецформа, множитель)
    private static func parseSpokenNumber(_ tokens: [Token], at start: Int) -> (value: Double, consumedCount: Int)? {
        guard start >= 0, start < tokens.count else { return nil }
        let words = tokens[start...].map { $0.core.lowercased() }
        return parseNumber(Array(words))
    }

    // Проценты: "двадцать пять процентов" или "25%"
    private static func parsePercentSpans(_ tokens: [Token]) -> [Span] {
        var spans: [Span] = []
        var i = 0
        while i < tokens.count {
            // Numeric: 25% (процент в core)
            if let numResult = parseNumericNumber(tokens, at: i) {
                let lastIdx = i + numResult.consumed - 1
                let lastCore = tokens[lastIdx].core
                if lastCore.hasSuffix("%") {
                    let numStr = String(lastCore.dropLast())
                    if let val = parseDecimalString(numStr) {
                        spans.append(Span(range: i..<(i + numResult.consumed), kind: .percent(val), priority: SpanPriority.percent))
                        i += numResult.consumed
                        continue
                    }
                }
            }

            // Spoken: "двадцать пять процентов"
            if let spoken = parseSpokenNumber(tokens, at: i) {
                let afterIdx = i + spoken.consumedCount
                if afterIdx < tokens.count {
                    let nextCore = tokens[afterIdx].core.lowercased()
                    if percentWords.contains(nextCore) {
                        spans.append(Span(
                            range: i..<(afterIdx + 1),
                            kind: .percent(spoken.value),
                            priority: SpanPriority.percent
                        ))
                        i = afterIdx + 1
                        continue
                    }
                }
            }

            i += 1
        }
        return spans
    }

    // Деньги: "тысяча рублей", "1000₽", "500$", числo + валютное слово
    private static func parseMoneySpans(_ tokens: [Token]) -> [Span] {
        var spans: [Span] = []
        var i = 0
        while i < tokens.count {
            // Numeric с валютой: 1000₽, 500$, 1 000₽
            if let numResult = parseNumericNumber(tokens, at: i), let currency = numResult.currency {
                let subunit = parseCurrencySubunit(tokens, at: i + numResult.consumed, currency: currency)
                spans.append(Span(
                    range: i..<(i + numResult.consumed + (subunit?.consumed ?? 0)),
                    kind: .money(amount: numResult.value, currency: currency, kopecks: subunit?.value),
                    priority: SpanPriority.currencySymbol
                ))
                i += numResult.consumed + (subunit?.consumed ?? 0)
                continue
            }

            // Numeric + валютное слово: 100 рублей
            if let numResult = parseNumericNumber(tokens, at: i), numResult.currency == nil {
                let afterIdx = i + numResult.consumed
                if afterIdx < tokens.count {
                    let nextCore = tokens[afterIdx].core.lowercased()
                    if let curr = Currency.wordForms[nextCore] {
                        let subunit = parseCurrencySubunit(tokens, at: afterIdx + 1, currency: curr)
                        spans.append(Span(
                            range: i..<(afterIdx + 1 + (subunit?.consumed ?? 0)),
                            kind: .money(amount: numResult.value, currency: curr, kopecks: subunit?.value),
                            priority: SpanPriority.money
                        ))
                        i = afterIdx + 1 + (subunit?.consumed ?? 0)
                        continue
                    }
                }
            }

            // Spoken + валютное слово: "тысяча рублей"
            if let spoken = parseSpokenNumber(tokens, at: i) {
                let afterIdx = i + spoken.consumedCount
                if afterIdx < tokens.count {
                    let nextCore = tokens[afterIdx].core.lowercased()
                    if let curr = Currency.wordForms[nextCore] {
                        let subunit = parseCurrencySubunit(tokens, at: afterIdx + 1, currency: curr)
                        spans.append(Span(
                            range: i..<(afterIdx + 1 + (subunit?.consumed ?? 0)),
                            kind: .money(amount: spoken.value, currency: curr, kopecks: subunit?.value),
                            priority: SpanPriority.money
                        ))
                        i = afterIdx + 1 + (subunit?.consumed ?? 0)
                        continue
                    }
                }
            }

            i += 1
        }
        return spans
    }

    private static func parseCurrencySubunit(
        _ tokens: [Token],
        at start: Int,
        currency: Currency
    ) -> (value: Int, consumed: Int)? {
        guard currency == .rub, start < tokens.count else { return nil }

        if let numeric = parseNumericNumber(tokens, at: start), numeric.currency == nil {
            let nextIndex = start + numeric.consumed
            if nextIndex < tokens.count,
               kopeckWords.contains(tokens[nextIndex].core.lowercased()),
               numeric.value.rounded(.down) == numeric.value
            {
                let value = Int(numeric.value)
                if (0...99).contains(value) {
                    return (value, numeric.consumed + 1)
                }
            }
        }

        if let spoken = parseSpokenNumber(tokens, at: start) {
            let nextIndex = start + spoken.consumedCount
            if nextIndex < tokens.count,
               kopeckWords.contains(tokens[nextIndex].core.lowercased()),
               spoken.value.rounded(.down) == spoken.value
            {
                let value = Int(spoken.value)
                if (0...99).contains(value) {
                    return (value, spoken.consumedCount + 1)
                }
            }
        }

        return nil
    }

    /// Abbreviation spans: 2 млн → 2 000 000
    private static func parseAbbreviationSpans(_ tokens: [Token]) -> [Span] {
        var spans: [Span] = []
        var i = 0
        while i < tokens.count {
            if let numResult = parseNumericNumber(tokens, at: i), numResult.isAbbreviated, numResult.currency == nil {
                spans.append(Span(
                    range: i..<(i + numResult.consumed),
                    kind: .expandedAbbreviation(numResult.value),
                    priority: SpanPriority.abbreviation
                ))
                i += numResult.consumed
                continue
            }
            i += 1
        }
        return spans
    }

    /// Время и длительность
    private static func parseTimeSpans(_ tokens: [Token]) -> [Span] {
        var spans: [Span] = []
        var i = 0

        // Спецслово: полчаса → 30 минут (duration)
        while i < tokens.count {
            if tokens[i].core.lowercased() == "полчаса" {
                spans.append(Span(
                    range: i..<(i + 1),
                    kind: .duration(value: 30, unit: .minutes),
                    priority: SpanPriority.duration
                ))
                i += 1
                continue
            }

            let lower = tokens[i].core.lowercased()

            // Паттерн 1: предлог + число + час (+ число + минут) → time
            if timePrepositions.contains(lower), i + 1 < tokens.count {
                if let hourResult = parseSpokenNumber(tokens, at: i + 1) {
                    let minuteStart = i + 1 + hourResult.consumedCount
                    if let minuteResult = parseSpokenNumber(tokens, at: minuteStart) {
                        let hour = Int(hourResult.value)
                        let minutes = Int(minuteResult.value)
                        let afterMinute = minuteStart + minuteResult.consumedCount

                        if (0...23).contains(hour),
                           (0...59).contains(minutes),
                           !(afterMinute < tokens.count && timeOfDayWords.contains(tokens[afterMinute].core.lowercased()))
                        {
                            spans.append(Span(
                                range: (i + 1)..<afterMinute,
                                kind: .time(hour: hour, minute: minutes),
                                priority: SpanPriority.time
                            ))
                            i = afterMinute
                            continue
                        }
                    }
                }

                if let hourResult = parseSpokenNumber(tokens, at: i + 1) {
                    let hourIdx = i + 1 + hourResult.consumedCount
                    if hourIdx < tokens.count, hourWords.contains(tokens[hourIdx].core.lowercased()) {
                        let hour = Int(hourResult.value)
                        guard hour >= 0, hour <= 23 else { i += 1; continue }

                        // Проверяем минуты
                        let afterHourIdx = hourIdx + 1
                        if afterHourIdx < tokens.count,
                           let minResult = parseSpokenNumber(tokens, at: afterHourIdx)
                        {
                            let minWordIdx = afterHourIdx + minResult.consumedCount
                            if minWordIdx < tokens.count, minuteWords.contains(tokens[minWordIdx].core.lowercased()) {
                                let minutes = Int(minResult.value)
                                if minutes >= 0, minutes <= 59 {
                                    // предлог + H часов M минут → span НЕ включает предлог (он остаётся)
                                    spans.append(Span(
                                        range: (i + 1)..<(minWordIdx + 1),
                                        kind: .time(hour: hour, minute: minutes),
                                        priority: SpanPriority.time
                                    ))
                                    i = minWordIdx + 1
                                    continue
                                }
                            }
                        }

                        // предлог + H часов → H:00
                        spans.append(Span(
                            range: (i + 1)..<(hourIdx + 1),
                            kind: .time(hour: hour, minute: 0),
                            priority: SpanPriority.time
                        ))
                        i = hourIdx + 1
                        continue
                    }
                }
                i += 1
                continue
            }

            // Паттерн 2: число + час/минут (без предлога) → duration
            if let numResult = parseSpokenNumber(tokens, at: i) {
                let unitIdx = i + numResult.consumedCount
                if unitIdx < tokens.count {
                    let unitWord = tokens[unitIdx].core.lowercased()

                    if hourWords.contains(unitWord) {
                        // Дробные (четверть часа) — не трогаем
                        guard numResult.value >= 1, numResult.value == numResult.value.rounded(.down) else {
                            i += 1
                            continue
                        }
                        let hourInt = Int(numResult.value)
                        guard hourInt >= 0, hourInt <= 23 else { i += 1; continue }

                        spans.append(Span(
                            range: i..<(unitIdx + 1),
                            kind: .duration(value: numResult.value, unit: .hours),
                            priority: SpanPriority.duration
                        ))
                        i = unitIdx + 1
                        continue
                    }

                    if minuteWords.contains(unitWord) {
                        spans.append(Span(
                            range: i..<(unitIdx + 1),
                            kind: .duration(value: numResult.value, unit: .minutes),
                            priority: SpanPriority.duration
                        ))
                        i = unitIdx + 1
                        continue
                    }
                }
            }

            i += 1
        }
        return spans
    }

    // Даты: порядковое + месяц
    private static func parseDateSpans(_ tokens: [Token]) -> [Span] {
        var spans: [Span] = []
        var i = 0
        while i < tokens.count {
            let lower = tokens[i].core.lowercased()

            // Составное: "двадцать" + порядковое + месяц
            if let tens = tensCardinals[lower], i + 2 < tokens.count {
                let nextLower = tokens[i + 1].core.lowercased()
                if let ord = ordinalForms[nextLower], ord.value <= 9 {
                    let dayValue = tens + ord.value
                    let monthIdx = i + 2
                    if monthIdx < tokens.count, months.contains(tokens[monthIdx].core.lowercased()) {
                        let year = parseYear(tokens, at: monthIdx + 1)
                        let upperBound = monthIdx + 1 + (year?.consumed ?? 0)
                        spans.append(Span(
                            range: i..<upperBound,
                            kind: .date(day: dayValue, month: tokens[monthIdx].core, year: year?.value),
                            priority: SpanPriority.date
                        ))
                        i = upperBound
                        continue
                    }
                }
            }

            // Простое порядковое + месяц
            if let ord = ordinalForms[lower], i + 1 < tokens.count {
                let monthIdx = i + 1
                if months.contains(tokens[monthIdx].core.lowercased()) {
                    let year = parseYear(tokens, at: monthIdx + 1)
                    let upperBound = monthIdx + 1 + (year?.consumed ?? 0)
                    spans.append(Span(
                        range: i..<upperBound,
                        kind: .date(day: ord.value, month: tokens[monthIdx].core, year: year?.value),
                        priority: SpanPriority.date
                    ))
                    i = upperBound
                    continue
                }
            }

            i += 1
        }
        return spans
    }

    private static func parseYear(_ tokens: [Token], at start: Int) -> (value: Int, consumed: Int)? {
        guard start < tokens.count else { return nil }

        if let numeric = parseNumericNumber(tokens, at: start),
           numeric.currency == nil,
           !numeric.isAbbreviated,
           numeric.value.rounded(.down) == numeric.value
        {
            let year = Int(numeric.value)
            if validYearRange.contains(year) {
                let trailingYearWord = start + numeric.consumed < tokens.count &&
                    yearWords.contains(tokens[start + numeric.consumed].core.lowercased())
                return (year, numeric.consumed + (trailingYearWord ? 1 : 0))
            }
        }

        let words = Array(tokens[start...]).map { $0.core.lowercased() }
        if let spoken = parseNumber(words), spoken.value.rounded(.down) == spoken.value {
            let year = Int(spoken.value)
            if start + spoken.consumedCount < tokens.count,
               let ordinal = ordinalForms[words[spoken.consumedCount]],
               let combined = combineYear(base: year, suffixValue: ordinal.value),
               validYearRange.contains(combined)
            {
                var consumed = spoken.consumedCount + 1
                if start + consumed < tokens.count,
                   yearWords.contains(tokens[start + consumed].core.lowercased())
                {
                    consumed += 1
                }
                return (combined, consumed)
            }

            if validYearRange.contains(year) {
                let trailingYearWord = start + spoken.consumedCount < tokens.count &&
                    yearWords.contains(tokens[start + spoken.consumedCount].core.lowercased())
                return (year, spoken.consumedCount + (trailingYearWord ? 1 : 0))
            }
        }

        return nil
    }

    private static func combineYear(base: Int, suffixValue: Int) -> Int? {
        guard validYearRange.contains(base), suffixValue >= 0, suffixValue < 100 else { return nil }
        let suffixWidth = suffixValue >= 10 ? 2 : 1
        let divisor = suffixWidth == 2 ? 100 : 10
        guard base % divisor == 0 else { return nil }
        return base + suffixValue
    }

    /// Порядковые числительные (без месяца — даты обрабатываются parseDateSpans)
    private static func parseOrdinalSpans(_ tokens: [Token]) -> [Span] {
        var spans: [Span] = []
        var i = 0
        while i < tokens.count {
            let lower = tokens[i].core.lowercased()

            // Составное: "двадцать" + порядковое единицы → N-суффикс
            if let tens = tensCardinals[lower], i + 1 < tokens.count {
                let nextLower = tokens[i + 1].core.lowercased()
                if let ord = ordinalForms[nextLower], ord.value <= 9 {
                    let combined = tens + ord.value
                    spans.append(Span(
                        range: i..<(i + 2),
                        kind: .ordinal(value: combined, suffix: ord.suffix),
                        priority: SpanPriority.ordinal
                    ))
                    i += 2
                    continue
                }
            }

            // Простое порядковое
            if let ord = ordinalForms[lower] {
                spans.append(Span(
                    range: i..<(i + 1),
                    kind: .ordinal(value: ord.value, suffix: ord.suffix),
                    priority: SpanPriority.ordinal
                ))
                i += 1
                continue
            }

            i += 1
        }
        return spans
    }

    /// Кардиналы
    private static func parseCardinalSpans(_ tokens: [Token]) -> [Span] {
        var spans: [Span] = []
        var i = 0
        while i < tokens.count {
            // Цифровой токен — пропускаем
            if let first = tokens[i].core.first, first.isNumber {
                // GigaAM большие числа: 2000000 → formatted
                if let numResult = parseNumericNumber(tokens, at: i), numResult.currency == nil, !numResult.isAbbreviated {
                    guard numResult.value <= Double(Int.max) else { i += numResult.consumed; continue }
                    let intVal = Int(numResult.value)
                    if intVal >= 1_000, numResult.consumed == 1, Double(intVal) == numResult.value {
                        let formatted = formatNumber(numResult.value)
                        let currentCore = tokens[i].core
                        if formatted != currentCore {
                            spans.append(Span(
                                range: i..<(i + 1),
                                kind: .formattedNumber(numResult.value),
                                priority: SpanPriority.formattedNumber
                            ))
                        }
                    }
                }
                i += 1
                continue
            }

            if let spoken = parseSpokenNumber(tokens, at: i) {
                let afterIdx = i + spoken.consumedCount
                let nextWord = afterIdx < tokens.count ? tokens[afterIdx].core.lowercased() : nil

                // ≤ 9 без триггера — оставить словом
                if spoken.value <= 9, spoken.value >= 0 {
                    if let next = nextWord, cardinalTriggers.contains(next) {
                        spans.append(Span(
                            range: i..<afterIdx,
                            kind: .cardinal(spoken.value),
                            priority: SpanPriority.cardinal
                        ))
                        i = afterIdx
                    } else {
                        i += spoken.consumedCount
                    }
                    continue
                }

                // "три тридцать" — потенциальное время, не трогаем
                if spoken.consumedCount == 1, spoken.value >= 10, spoken.value <= 59, i > 0 {
                    let prevLower = tokens[i - 1].core.lowercased()
                    if let prevVal = cardinals[prevLower], prevVal >= 1, prevVal <= 12 {
                        i += 1
                        continue
                    }
                }

                // ≥ 10 — всегда нормализуем
                spans.append(Span(
                    range: i..<afterIdx,
                    kind: .cardinal(spoken.value),
                    priority: SpanPriority.cardinal
                ))
                i = afterIdx
                continue
            }

            i += 1
        }
        return spans
    }

    // MARK: - applySpans (v2)

    private static func applySpans(_ tokens: inout [Token], _ spans: [Span]) {
        // Применяем справа налево чтобы не сбивать индексы
        for span in spans.reversed() {
            guard !span.range.isEmpty else { continue }
            let lastIdx = span.range.upperBound - 1
            let rangeC = span.range.lowerBound...lastIdx

            let formatted: String
            switch span.kind {
            case .percent(let val):
                formatted = CanonicalFormatter.formatPercent(val)
            case .money(let amount, let curr, let kopecks):
                formatted = CanonicalFormatter.formatMoney(amount, curr, kopecks: kopecks)
            case .currencySymbolToWord(let amount, let curr):
                formatted = CanonicalFormatter.formatMoney(amount, curr)
            case .expandedAbbreviation(let val):
                // Точка аббревиатуры (тыс., млн., млрд.) — не пунктуация предложения
                let abbrevCore = tokens[lastIdx].core.lowercased()
                if multiplierAbbreviations[abbrevCore] != nil,
                   multiplierAbbreviations[abbrevCore + "."] != nil,
                   tokens[lastIdx].trailing.hasPrefix(".")
                {
                    tokens[lastIdx].trailing = String(tokens[lastIdx].trailing.dropFirst())
                }
                formatted = CanonicalFormatter.formatInteger(val)
            case .formattedNumber(let val):
                formatted = CanonicalFormatter.formatInteger(val)
            case .time(let h, let m):
                formatted = CanonicalFormatter.formatTime(h, m)
            case .duration(let val, let unit):
                if span.range.count == 1 {
                    // Одиночный токен (полчаса) → "30 минут"
                    let unitWord = unit == .minutes ? "минут" : "часов"
                    formatted = CanonicalFormatter.formatDuration(val, unit) + " " + unitWord
                } else {
                    guard span.range.count >= 2 else { continue }
                    // Длительность: заменяем только числовые токены, unit-слово сохраняется
                    let numFormatted = CanonicalFormatter.formatDuration(val, unit)
                    let numRangeC = span.range.lowerBound...(lastIdx - 1)
                    replace(&tokens, range: numRangeC, with: numFormatted, carryTrailingFrom: lastIdx - 1)
                    continue
                }
            case .date(let day, let month, let year):
                if let year {
                    formatted = "\(day) \(month) \(year)"
                } else {
                    guard span.range.count >= 2 else { continue }
                    let numRangeC = span.range.lowerBound...(lastIdx - 1)
                    replace(&tokens, range: numRangeC, with: "\(day)", carryTrailingFrom: lastIdx - 1)
                    continue
                }
            case .ordinal(let val, let suffix):
                formatted = CanonicalFormatter.formatOrdinal(val, suffix)
            case .cardinal(let val):
                formatted = CanonicalFormatter.formatInteger(val)
            }

            replace(&tokens, range: rangeC, with: formatted, carryTrailingFrom: lastIdx)
        }
    }

    // MARK: - v2 normalize pipeline

    private static func normalizeV2All(_ text: String) -> String {
        var tokens = tokenize(text)
        let spans = parseAllSpans(tokens)
        let resolved = resolveConflicts(spans)
        applySpans(&tokens, resolved)
        return render(tokens)
    }

    private static func parseAllSpans(_ tokens: [Token]) -> [Span] {
        var spans: [Span] = []
        spans += parsePercentSpans(tokens)
        spans += parseMoneySpans(tokens)
        spans += parseAbbreviationSpans(tokens)
        spans += parseTimeSpans(tokens)
        spans += parseDateSpans(tokens)
        spans += parseOrdinalSpans(tokens)
        spans += parseCardinalSpans(tokens)
        return spans
    }

    // MARK: - Словари

    // Кардиналы: все падежные и родовые формы → числовое значение
    private static let cardinals: [String: Double] = [
        // Ноль
        "ноль": 0, "нуль": 0,
        // Единицы
        "один": 1, "одна": 1, "одно": 1,
        "два": 2, "две": 2,
        "три": 3,
        "четыре": 4,
        "пять": 5,
        "шесть": 6,
        "семь": 7,
        "восемь": 8,
        "девять": 9,
        // Косвенные падежи 1–10
        "одному": 1, "одной": 1, "одним": 1, "одного": 1, "одном": 1, "одну": 1,
        "двум": 2, "двух": 2, "двумя": 2,
        "трём": 3, "трёх": 3, "тремя": 3, "трем": 3, "трех": 3,
        "четырём": 4, "четырёх": 4, "четырьмя": 4, "четырем": 4, "четырех": 4,
        "пяти": 5, "пятью": 5,
        "шести": 6, "шестью": 6,
        "семи": 7, "семью": 7,
        "восьми": 8, "восемью": 8, "восьмью": 8,
        "девяти": 9, "девятью": 9,
        "десяти": 10, "десятью": 10,
        // Подростки (10–19)
        "десять": 10,
        "одиннадцать": 11, "одиннадцати": 11,
        "двенадцать": 12, "двенадцати": 12,
        "тринадцать": 13, "тринадцати": 13,
        "четырнадцать": 14, "четырнадцати": 14,
        "пятнадцать": 15, "пятнадцати": 15,
        "шестнадцать": 16, "шестнадцати": 16,
        "семнадцать": 17, "семнадцати": 17,
        "восемнадцать": 18, "восемнадцати": 18,
        "девятнадцать": 19, "девятнадцати": 19,
        // Десятки (20–90)
        "двадцать": 20, "двадцати": 20,
        "тридцать": 30, "тридцати": 30,
        "сорок": 40, "сорока": 40,
        "пятьдесят": 50, "пятидесяти": 50,
        "шестьдесят": 60, "шестидесяти": 60,
        "семьдесят": 70, "семидесяти": 70,
        "восемьдесят": 80, "восьмидесяти": 80,
        "девяносто": 90, "девяноста": 90,
        // Сотни (100–900)
        "сто": 100, "ста": 100,
        "двести": 200, "двухсот": 200,
        "триста": 300, "трёхсот": 300, "трехсот": 300,
        "четыреста": 400, "четырёхсот": 400, "четырехсот": 400,
        "пятьсот": 500, "пятисот": 500,
        "шестьсот": 600, "шестисот": 600,
        "семьсот": 700, "семисот": 700,
        "восемьсот": 800, "восьмисот": 800,
        "девятьсот": 900, "девятисот": 900,
    ]

    /// Множители
    private static let multipliers: [String: Double] = [
        "тысяча": 1_000, "тысячи": 1_000, "тысяч": 1_000, "тысячам": 1_000, "тысячами": 1_000, "тысячах": 1_000,
        "миллион": 1_000_000, "миллиона": 1_000_000, "миллионов": 1_000_000, "миллионам": 1_000_000,
        "миллиард": 1_000_000_000, "миллиарда": 1_000_000_000, "миллиардов": 1_000_000_000, "миллиардам": 1_000_000_000,
    ]

    /// Спецформы
    private static let specialForms: [String: Double] = [
        "полтора": 1.5, "полторы": 1.5,
        "четверть": 0.25,
    ]

    // MARK: - parseNumber

    /// Жадный парсер: два регистра (total + group)
    static func parseNumber(_ words: [String]) -> (value: Double, consumedCount: Int)? {
        guard !words.isEmpty else { return nil }

        // Цифровой токен — не парсим
        if let first = words.first?.first, first.isNumber { return nil }

        var total: Double = 0
        var group: Double = 0
        var consumed = 0
        var lastMultiplier: Double = 0
        // Трекинг порядка внутри группы: единицы после десятков — ок, десятки после единиц — стоп
        var groupHasUnit = false // 1-9
        var groupHasTens = false // 10-90 (включая подростки)
        var groupHasHundred = false // 100-900

        var i = 0
        while i < words.count {
            let word = words[i].lowercased()

            // Спецформа "с половиной" (два слова)
            if word == "с", i + 1 < words.count, words[i + 1].lowercased() == "половиной" {
                guard consumed > 0 else { break }
                group += 0.5
                consumed += 2
                i += 2
                continue
            }

            // Спецформы (полтора/полторы/четверть) — самодостаточные, не комбинируются с кардиналами
            if let val = specialForms[word] {
                group += val
                consumed += 1
                groupHasUnit = true
                i += 1
                continue
            }

            // Множитель (тысяча/миллион/миллиард) — строго по убыванию
            if let mult = multipliers[word] {
                if lastMultiplier > 0 && mult >= lastMultiplier { break }
                let g = group == 0 ? 1.0 : group
                total += g * mult
                group = 0
                lastMultiplier = mult
                groupHasUnit = false
                groupHasTens = false
                groupHasHundred = false
                consumed += 1
                i += 1
                continue
            }

            // Кардинал (единицы, подростки, десятки, сотни)
            if let val = cardinals[word] {
                // Проверяем порядок: русские числа = сотня + десяток + единица
                if val >= 100 {
                    if groupHasHundred || groupHasTens || groupHasUnit { break }
                    groupHasHundred = true
                } else if val >= 10 {
                    if groupHasTens || groupHasUnit { break }
                    groupHasTens = true
                } else if val >= 1 {
                    if groupHasUnit { break }
                    groupHasUnit = true
                } else {
                    // val == 0 ("ноль"/"нуль") — standalone, не комбинируется
                    if consumed > 0 { break }
                    groupHasUnit = true
                }
                group += val
                consumed += 1
                i += 1
                continue
            }

            // Стоп-слово
            break
        }

        guard consumed > 0 else { return nil }

        let value = total + group
        return (value, consumed)
    }

    // MARK: - formatNumber

    /// ГОСТ: пробелы-разделители для ≥1000, запятая для дробных
    static func formatNumber(_ value: Double) -> String {
        let isInteger = value.truncatingRemainder(dividingBy: 1) == 0

        if isInteger {
            guard value >= Double(Int.min), value <= Double(Int.max) else {
                return "\(value)"
            }
            let intVal = Int(value)
            if abs(intVal) < 1_000 {
                return "\(intVal)"
            }
            // Разбиваем на группы по 3 с пробелом
            let s = "\(abs(intVal))"
            var result = ""
            for (idx, ch) in s.reversed().enumerated() {
                if idx > 0, idx % 3 == 0 { result.append(" ") }
                result.append(ch)
            }
            let formatted = String(result.reversed())
            return intVal < 0 ? "-\(formatted)" : formatted
        } else {
            // Дробное: запятая. Округляем до 2 знаков для защиты от floating-point артефактов
            let rounded = (value * 100).rounded()/100
            let absRounded = abs(rounded)
            let intPart = Int(absRounded)
            let fracRaw = absRounded - Double(intPart)
            let fracDigits = Int((fracRaw * 100).rounded())
            let sign = value < 0 ? "-" : ""
            // Убрать trailing zero: 1,50 → 1,5
            if fracDigits % 10 == 0 {
                return "\(sign)\(intPart),\(fracDigits/10)"
            }
            return "\(sign)\(intPart),\(fracDigits)"
        }
    }

    // MARK: - Триггеры процентов

    private static let percentWords: Set<String> = [
        "процент", "процента", "процентов", "процентам", "процентами", "процентах",
    ]

    private static let timePrepositions: Set<String> = ["в", "к", "до", "с", "после"]

    private static let hourWords: Set<String> = [
        "час", "часа", "часов", "часам", "часами", "часах",
    ]

    private static let minuteWords: Set<String> = [
        "минут", "минуты", "минуту", "минута", "минутам", "минутами", "минутах",
    ]

    private static let timeOfDayWords: Set<String> = [
        "утра", "вечера", "дня", "ночи",
    ]

    // MARK: - Порядковые числительные (полный словарь форм)

    /// (value, suffix) — суффикс для записи "N-й", "N-е", "N-го" и т.д.
    private static let ordinalForms: [String: (value: Int, suffix: String)] = [
        // 1
        "первый": (1, "-й"), "первая": (1, "-я"), "первое": (1, "-е"),
        "первого": (1, "-го"), "первому": (1, "-му"), "первом": (1, "-м"),
        "первым": (1, "-м"), "первой": (1, "-й"), "первую": (1, "-ю"),
        // 2
        "второй": (2, "-й"), "вторая": (2, "-я"), "второе": (2, "-е"),
        "второго": (2, "-го"), "второму": (2, "-му"), "втором": (2, "-м"),
        "вторым": (2, "-м"), "вторую": (2, "-ю"),
        // 3
        "третий": (3, "-й"), "третья": (3, "-я"), "третье": (3, "-е"),
        "третьего": (3, "-го"), "третьему": (3, "-му"), "третьем": (3, "-м"),
        "третьим": (3, "-м"), "третью": (3, "-ю"),
        // 4
        "четвёртый": (4, "-й"), "четвертый": (4, "-й"), "четвёртая": (4, "-я"), "четвертая": (4, "-я"),
        "четвёртое": (4, "-е"), "четвертое": (4, "-е"),
        "четвёртого": (4, "-го"), "четвертого": (4, "-го"),
        "четвёртому": (4, "-му"), "четвертому": (4, "-му"),
        "четвёртом": (4, "-м"), "четвертом": (4, "-м"),
        // 5
        "пятый": (5, "-й"), "пятая": (5, "-я"), "пятое": (5, "-е"),
        "пятого": (5, "-го"), "пятому": (5, "-му"), "пятом": (5, "-м"),
        "пятым": (5, "-м"), "пятую": (5, "-ю"),
        // 6
        "шестой": (6, "-й"), "шестая": (6, "-я"), "шестое": (6, "-е"),
        "шестого": (6, "-го"), "шестому": (6, "-му"), "шестом": (6, "-м"),
        // 7
        "седьмой": (7, "-й"), "седьмая": (7, "-я"), "седьмое": (7, "-е"),
        "седьмого": (7, "-го"), "седьмому": (7, "-му"), "седьмом": (7, "-м"),
        // 8
        "восьмой": (8, "-й"), "восьмая": (8, "-я"), "восьмое": (8, "-е"),
        "восьмого": (8, "-го"), "восьмому": (8, "-му"), "восьмом": (8, "-м"),
        // 9
        "девятый": (9, "-й"), "девятая": (9, "-я"), "девятое": (9, "-е"),
        "девятого": (9, "-го"), "девятому": (9, "-му"), "девятом": (9, "-м"),
        // 10
        "десятый": (10, "-й"), "десятая": (10, "-я"), "десятое": (10, "-е"),
        "десятого": (10, "-го"), "десятому": (10, "-му"), "десятом": (10, "-м"),
        // 11
        "одиннадцатый": (11, "-й"), "одиннадцатая": (11, "-я"), "одиннадцатое": (11, "-е"),
        "одиннадцатого": (11, "-го"), "одиннадцатому": (11, "-му"), "одиннадцатом": (11, "-м"),
        // 12
        "двенадцатый": (12, "-й"), "двенадцатая": (12, "-я"), "двенадцатое": (12, "-е"),
        "двенадцатого": (12, "-го"), "двенадцатому": (12, "-му"), "двенадцатом": (12, "-м"),
        // 13
        "тринадцатый": (13, "-й"), "тринадцатая": (13, "-я"), "тринадцатое": (13, "-е"),
        "тринадцатого": (13, "-го"), "тринадцатому": (13, "-му"), "тринадцатом": (13, "-м"),
        // 14
        "четырнадцатый": (14, "-й"), "четырнадцатая": (14, "-я"), "четырнадцатое": (14, "-е"),
        "четырнадцатого": (14, "-го"), "четырнадцатому": (14, "-му"), "четырнадцатом": (14, "-м"),
        // 15
        "пятнадцатый": (15, "-й"), "пятнадцатая": (15, "-я"), "пятнадцатое": (15, "-е"),
        "пятнадцатого": (15, "-го"), "пятнадцатому": (15, "-му"), "пятнадцатом": (15, "-м"),
        // 16
        "шестнадцатый": (16, "-й"), "шестнадцатая": (16, "-я"), "шестнадцатое": (16, "-е"),
        "шестнадцатого": (16, "-го"), "шестнадцатому": (16, "-му"), "шестнадцатом": (16, "-м"),
        // 17
        "семнадцатый": (17, "-й"), "семнадцатая": (17, "-я"), "семнадцатое": (17, "-е"),
        "семнадцатого": (17, "-го"), "семнадцатому": (17, "-му"), "семнадцатом": (17, "-м"),
        // 18
        "восемнадцатый": (18, "-й"), "восемнадцатая": (18, "-я"), "восемнадцатое": (18, "-е"),
        "восемнадцатого": (18, "-го"), "восемнадцатому": (18, "-му"), "восемнадцатом": (18, "-м"),
        // 19
        "девятнадцатый": (19, "-й"), "девятнадцатая": (19, "-я"), "девятнадцатое": (19, "-е"),
        "девятнадцатого": (19, "-го"), "девятнадцатому": (19, "-му"), "девятнадцатом": (19, "-м"),
        // 20
        "двадцатый": (20, "-й"), "двадцатая": (20, "-я"), "двадцатое": (20, "-е"),
        "двадцатого": (20, "-го"), "двадцатому": (20, "-му"), "двадцатом": (20, "-м"),
        // 30
        "тридцатый": (30, "-й"), "тридцатая": (30, "-я"), "тридцатое": (30, "-е"),
        "тридцатого": (30, "-го"), "тридцатом": (30, "-м"),
        // 40
        "сороковой": (40, "-й"), "сороковая": (40, "-я"), "сороковое": (40, "-е"),
        "сорокового": (40, "-го"), "сороковом": (40, "-м"),
        // 50
        "пятидесятый": (50, "-й"), "пятидесятого": (50, "-го"),
        // 100
        "сотый": (100, "-й"), "сотая": (100, "-я"), "сотое": (100, "-е"),
        "сотого": (100, "-го"), "сотом": (100, "-м"),
    ]

    /// Десятки-кардиналы для составных порядковых ("двадцать" + "пятое")
    private static let tensCardinals: [String: Int] = [
        "двадцать": 20, "тридцать": 30, "сорок": 40,
        "пятьдесят": 50, "шестьдесят": 60, "семьдесят": 70,
        "восемьдесят": 80, "девяносто": 90,
    ]

    /// Месяцы (родительный падеж)
    private static let months: Set<String> = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря",
    ]

    private static let yearWords: Set<String> = [
        "год", "года", "году", "годом",
    ]

    private static let kopeckWords: Set<String> = [
        "копейка", "копейки", "копеек", "копейкам", "копейками", "копейках", "коп",
    ]

    private static let validYearRange = 1_000...2_100

    private static let cardinalTriggers: Set<String> = [
        "метр", "метра", "метров", "метрам",
        "километр", "километра", "километров", "километрам",
        "сантиметр", "сантиметра", "сантиметров",
        "миллиметр", "миллиметра", "миллиметров",
        "килограмм", "килограмма", "килограммов", "килограммам",
        "грамм", "грамма", "граммов", "граммам",
        "тонн", "тонна", "тонны", "тоннам",
        "литр", "литра", "литров", "литрам",
        "градус", "градуса", "градусов",
        "штук", "штуки", "штука", "штукам",
        "гектар", "гектара", "гектаров",
        "раз", "раза",
    ]

    // MARK: - normalize

    static func normalize(_ text: String) -> String {
        normalizeV2All(text)
    }
}
