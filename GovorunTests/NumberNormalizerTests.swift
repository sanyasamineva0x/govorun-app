@testable import Govorun
import XCTest

final class NumberParserTests: XCTestCase {
    // MARK: - parseNumber: единицы

    func test_parse_ноль() {
        let r = NumberNormalizer.parseNumber(["ноль"])
        XCTAssertEqual(r?.value, 0)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    func test_parse_один() {
        let r = NumberNormalizer.parseNumber(["один"])
        XCTAssertEqual(r?.value, 1)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    func test_parse_одна() {
        let r = NumberNormalizer.parseNumber(["одна"])
        XCTAssertEqual(r?.value, 1)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    func test_parse_два() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["два"])?.value, 2)
    }

    func test_parse_две() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["две"])?.value, 2)
    }

    func test_parse_девять() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["девять"])?.value, 9)
    }

    // MARK: - parseNumber: косвенные падежи

    func test_parse_трём() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["трём"])?.value, 3)
    }

    func test_parse_двум() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["двум"])?.value, 2)
    }

    func test_parse_пяти() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["пяти"])?.value, 5)
    }

    func test_parse_одному() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["одному"])?.value, 1)
    }

    // MARK: - parseNumber: подростки

    func test_parse_десять() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["десять"])?.value, 10)
    }

    func test_parse_одиннадцать() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["одиннадцать"])?.value, 11)
    }

    func test_parse_девятнадцать() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["девятнадцать"])?.value, 19)
    }

    // MARK: - parseNumber: десятки

    func test_parse_двадцать() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["двадцать"])?.value, 20)
    }

    func test_parse_двадцать_пять() {
        let r = NumberNormalizer.parseNumber(["двадцать", "пять"])
        XCTAssertEqual(r?.value, 25)
        XCTAssertEqual(r?.consumedCount, 2)
    }

    func test_parse_девяносто() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["девяносто"])?.value, 90)
    }

    // MARK: - parseNumber: сотни

    func test_parse_сто() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["сто"])?.value, 100)
    }

    func test_parse_двести() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["двести"])?.value, 200)
    }

    func test_parse_сто_двадцать_пять() {
        let r = NumberNormalizer.parseNumber(["сто", "двадцать", "пять"])
        XCTAssertEqual(r?.value, 125)
        XCTAssertEqual(r?.consumedCount, 3)
    }

    func test_parse_девятьсот_девяносто_девять() {
        let r = NumberNormalizer.parseNumber(["девятьсот", "девяносто", "девять"])
        XCTAssertEqual(r?.value, 999)
        XCTAssertEqual(r?.consumedCount, 3)
    }

    // MARK: - parseNumber: тысячи

    func test_parse_тысяча() {
        let r = NumberNormalizer.parseNumber(["тысяча"])
        XCTAssertEqual(r?.value, 1_000)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    func test_parse_две_тысячи() {
        let r = NumberNormalizer.parseNumber(["две", "тысячи"])
        XCTAssertEqual(r?.value, 2_000)
        XCTAssertEqual(r?.consumedCount, 2)
    }

    func test_parse_двадцать_пять_тысяч() {
        let r = NumberNormalizer.parseNumber(["двадцать", "пять", "тысяч"])
        XCTAssertEqual(r?.value, 25_000)
        XCTAssertEqual(r?.consumedCount, 3)
    }

    func test_parse_сто_двадцать_пять_тысяч_триста() {
        let r = NumberNormalizer.parseNumber(["сто", "двадцать", "пять", "тысяч", "триста"])
        XCTAssertEqual(r?.value, 125_300)
        XCTAssertEqual(r?.consumedCount, 5)
    }

    // MARK: - parseNumber: миллионы

    func test_parse_миллион() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["миллион"])?.value, 1_000_000)
    }

    func test_parse_два_миллиона() {
        let r = NumberNormalizer.parseNumber(["два", "миллиона"])
        XCTAssertEqual(r?.value, 2_000_000)
        XCTAssertEqual(r?.consumedCount, 2)
    }

    func test_parse_миллион_двести_тысяч_триста() {
        let r = NumberNormalizer.parseNumber(["миллион", "двести", "тысяч", "триста"])
        XCTAssertEqual(r?.value, 1_200_300)
        XCTAssertEqual(r?.consumedCount, 4)
    }

    // MARK: - parseNumber: миллиарды

    func test_parse_миллиард() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["миллиард"])?.value, 1_000_000_000)
    }

    // MARK: - parseNumber: спецформы

    func test_parse_полтора() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["полтора"])?.value, 1.5)
    }

    func test_parse_полторы() {
        XCTAssertEqual(NumberNormalizer.parseNumber(["полторы"])?.value, 1.5)
    }

    func test_parse_три_с_половиной() {
        let r = NumberNormalizer.parseNumber(["три", "с", "половиной"])
        XCTAssertEqual(r?.value, 3.5)
        XCTAssertEqual(r?.consumedCount, 3)
    }

    func test_parse_полторы_тысячи() {
        let r = NumberNormalizer.parseNumber(["полторы", "тысячи"])
        XCTAssertEqual(r?.value, 1_500)
        XCTAssertEqual(r?.consumedCount, 2)
    }

    // MARK: - parseNumber: стоп-слова

    func test_parse_stops_at_non_numeral() {
        let r = NumberNormalizer.parseNumber(["двадцать", "пять", "рублей"])
        XCTAssertEqual(r?.value, 25)
        XCTAssertEqual(r?.consumedCount, 2)
    }

    func test_parse_non_numeral_returns_nil() {
        XCTAssertNil(NumberNormalizer.parseNumber(["кошка"]))
    }

    func test_parse_digit_token_returns_nil() {
        XCTAssertNil(NumberNormalizer.parseNumber(["25"]))
    }

    // MARK: - formatNumber

    func test_format_small_integer() {
        XCTAssertEqual(NumberNormalizer.formatNumber(25), "25")
    }

    func test_format_thousand() {
        XCTAssertEqual(NumberNormalizer.formatNumber(1_000), "1 000")
    }

    func test_format_large() {
        XCTAssertEqual(NumberNormalizer.formatNumber(25_000), "25 000")
    }

    func test_format_million() {
        XCTAssertEqual(NumberNormalizer.formatNumber(1_200_300), "1 200 300")
    }

    func test_format_decimal() {
        XCTAssertEqual(NumberNormalizer.formatNumber(1.5), "1,5")
    }

    func test_format_poltysy_is_integer() {
        // полторы тысячи = 1500.0 → целое
        XCTAssertEqual(NumberNormalizer.formatNumber(1_500), "1 500")
    }
}

// MARK: - Проценты

final class PercentageNormalizerTests: XCTestCase {
    func test_двадцать_пять_процентов() {
        XCTAssertEqual(NumberNormalizer.normalize("двадцать пять процентов"), "25%")
    }

    func test_сто_процентов() {
        XCTAssertEqual(NumberNormalizer.normalize("сто процентов"), "100%")
    }

    func test_полтора_процента() {
        XCTAssertEqual(NumberNormalizer.normalize("полтора процента"), "1,5%")
    }

    func test_пять_процентов_годовых() {
        XCTAssertEqual(NumberNormalizer.normalize("пять процентов годовых"), "5% годовых")
    }

    func test_no_match_процент_without_number() {
        XCTAssertEqual(NumberNormalizer.normalize("процентов нет"), "процентов нет")
    }
}

// MARK: - Валюты

final class CurrencyNormalizerTests: XCTestCase {
    func test_тысяча_рублей() {
        XCTAssertEqual(NumberNormalizer.normalize("тысяча рублей"), "1 000 рублей")
    }

    func test_пятьсот_долларов() {
        XCTAssertEqual(NumberNormalizer.normalize("пятьсот долларов"), "500 долларов")
    }

    func test_двести_евро() {
        XCTAssertEqual(NumberNormalizer.normalize("двести евро"), "200 евро")
    }

    func test_три_с_половиной_тысячи_рублей() {
        XCTAssertEqual(NumberNormalizer.normalize("три с половиной тысячи рублей"), "3 500 рублей")
    }

    func test_currency_preserves_word_after() {
        XCTAssertEqual(NumberNormalizer.normalize("стоит двести рублей в месяц"), "стоит 200 рублей в месяц")
    }

    func test_девятьсот_рублей_пятьдесят_копеек() {
        XCTAssertEqual(
            NumberNormalizer.normalize("девятьсот рублей пятьдесят копеек"),
            "900 рублей 50 копеек"
        )
    }
}

// MARK: - Время

final class TimeNormalizerTests: XCTestCase {
    /// Время (H:MM) — с явным контекстом
    func test_в_пять_часов() {
        XCTAssertEqual(NumberNormalizer.normalize("в пять часов"), "в 5:00")
    }

    func test_в_два_часа_пятнадцать_минут() {
        XCTAssertEqual(NumberNormalizer.normalize("в два часа пятнадцать минут"), "в 2:15")
    }

    func test_к_трём_часам() {
        XCTAssertEqual(NumberNormalizer.normalize("к трём часам"), "к 3:00")
    }

    /// Длительность — НЕ H:MM
    func test_пять_часов_end_of_sentence_is_duration() {
        XCTAssertEqual(NumberNormalizer.normalize("пять часов"), "5 часов")
    }

    func test_пять_часов_работы_is_duration() {
        XCTAssertEqual(NumberNormalizer.normalize("пять часов работы"), "5 часов работы")
    }

    func test_три_часа_ожидания_is_duration() {
        XCTAssertEqual(NumberNormalizer.normalize("три часа ожидания"), "3 часа ожидания")
    }

    /// Минуты
    func test_двадцать_минут() {
        XCTAssertEqual(NumberNormalizer.normalize("двадцать минут"), "20 минут")
    }

    func test_полчаса() {
        XCTAssertEqual(NumberNormalizer.normalize("полчаса"), "30 минут")
    }

    /// Не трогаем
    func test_без_четверти_три_untouched() {
        XCTAssertEqual(NumberNormalizer.normalize("без четверти три"), "без четверти три")
    }

    func test_три_тридцать_untouched() {
        XCTAssertEqual(NumberNormalizer.normalize("три тридцать"), "три тридцать")
    }

    func test_в_пятнадцать_тридцать() {
        XCTAssertEqual(NumberNormalizer.normalize("в пятнадцать тридцать"), "в 15:30")
    }

    func test_в_девять_вечера_stays() {
        XCTAssertEqual(NumberNormalizer.normalize("в девять вечера"), "в девять вечера")
    }
}

// MARK: - Даты

final class DateNormalizerTests: XCTestCase {
    func test_тринадцатое_марта() {
        XCTAssertEqual(NumberNormalizer.normalize("тринадцатое марта"), "13 марта")
    }

    func test_двадцать_пятое_января() {
        XCTAssertEqual(NumberNormalizer.normalize("двадцать пятое января"), "25 января")
    }

    func test_первое_сентября() {
        XCTAssertEqual(NumberNormalizer.normalize("первое сентября"), "1 сентября")
    }

    func test_тридцать_первое_декабря() {
        XCTAssertEqual(NumberNormalizer.normalize("тридцать первое декабря"), "31 декабря")
    }

    func test_relative_date_untouched() {
        XCTAssertEqual(NumberNormalizer.normalize("завтра"), "завтра")
    }

    func test_date_in_sentence() {
        XCTAssertEqual(NumberNormalizer.normalize("встреча двадцатого апреля"), "встреча 20 апреля")
    }

    func test_двадцать_третье_марта_две_тысячи_двадцать_шестого() {
        XCTAssertEqual(
            NumberNormalizer.normalize("двадцать третье марта две тысячи двадцать шестого"),
            "23 марта 2026"
        )
    }
}

// MARK: - Порядковые (без месяца)

final class OrdinalNormalizerTests: XCTestCase {
    func test_двадцать_пятое() {
        XCTAssertEqual(NumberNormalizer.normalize("двадцать пятое"), "25-е")
    }

    func test_третий_этаж() {
        XCTAssertEqual(NumberNormalizer.normalize("третий этаж"), "3-й этаж")
    }

    func test_пятая_версия() {
        XCTAssertEqual(NumberNormalizer.normalize("пятая версия"), "5-я версия")
    }

    func test_на_двадцать_пятом_этаже() {
        XCTAssertEqual(NumberNormalizer.normalize("на двадцать пятом этаже"), "на 25-м этаже")
    }

    func test_первый() {
        XCTAssertEqual(NumberNormalizer.normalize("первый"), "1-й")
    }

    func test_одиннадцатая() {
        XCTAssertEqual(NumberNormalizer.normalize("одиннадцатая"), "11-я")
    }
}

// MARK: - Кардиналы

final class CardinalNormalizerTests: XCTestCase {
    func test_двадцать_пять() {
        XCTAssertEqual(NumberNormalizer.normalize("двадцать пять"), "25")
    }

    func test_сто_тридцать() {
        XCTAssertEqual(NumberNormalizer.normalize("сто тридцать"), "130")
    }

    func test_три_тысячи_двести() {
        XCTAssertEqual(NumberNormalizer.normalize("три тысячи двести"), "3 200")
    }

    /// ≤ 9 без контекста — оставить словом
    func test_три_кота_stays() {
        XCTAssertEqual(NumberNormalizer.normalize("три кота"), "три кота")
    }

    func test_пять_stays_alone() {
        XCTAssertEqual(NumberNormalizer.normalize("пять"), "пять")
    }

    /// ≥ 10 — всегда нормализуем
    func test_десять_always() {
        XCTAssertEqual(NumberNormalizer.normalize("десять"), "10")
    }

    /// ≤ 9 с trigger-словом — нормализуем
    func test_пять_метров() {
        XCTAssertEqual(NumberNormalizer.normalize("пять метров"), "5 метров")
    }

    func test_три_килограмма() {
        XCTAssertEqual(NumberNormalizer.normalize("три килограмма"), "3 килограмма")
    }

    /// Уже цифры — не трогаем
    func test_digit_passthrough() {
        XCTAssertEqual(NumberNormalizer.normalize("у меня 3 кошки"), "у меня 3 кошки")
    }

    /// Идемпотентность
    func test_idempotent() {
        let once = NumberNormalizer.normalize("двадцать пять процентов")
        let twice = NumberNormalizer.normalize(once)
        XCTAssertEqual(once, twice)
    }
}

// MARK: - Смешанные предложения

final class MixedSentenceNormalizerTests: XCTestCase {
    func test_mixed_time_and_currency() {
        XCTAssertEqual(
            NumberNormalizer.normalize("встреча в пять часов стоит триста рублей"),
            "встреча в 5:00 стоит 300 рублей"
        )
    }

    func test_mixed_date_and_percent() {
        XCTAssertEqual(
            NumberNormalizer.normalize("двадцатого марта скидка двадцать процентов"),
            "20 марта скидка 20%"
        )
    }

    func test_sentence_with_small_number_no_context() {
        XCTAssertEqual(
            NumberNormalizer.normalize("купи три яблока и двадцать пять апельсинов"),
            "купи три яблока и 25 апельсинов"
        )
    }
}

// MARK: - Интеграция через DeterministicNormalizer

final class NumberNormalizerIntegrationTests: XCTestCase {
    func test_deterministic_normalizer_converts_numbers() {
        // DeterministicNormalizer adds capitalization + period
        XCTAssertEqual(
            DeterministicNormalizer.normalize("встреча в пять часов стоит триста рублей"),
            "Встреча в 5:00 стоит 300 рублей."
        )
    }

    func test_fillers_removed_then_numbers_normalized() {
        // "%" — пунктуация, DeterministicNormalizer не добавляет точку
        XCTAssertEqual(
            DeterministicNormalizer.normalize("ну типа двадцать пять процентов"),
            "25%"
        )
    }

    func test_numbers_and_capitalization() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("тринадцатое марта. двести рублей"),
            "13 марта. 200 рублей."
        )
    }

    func test_temperature_canon_from_spoken_celsius() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("на улице двадцать пять градусов цельсия", terminalPeriodEnabled: false),
            "На улице 25°C"
        )
    }

    func test_unit_abbreviation_canon_expands_to_full_form() {
        XCTAssertEqual(
            DeterministicNormalizer.normalize("купи 5 кг яблок и 2 л молока", terminalPeriodEnabled: false),
            "Купи 5 килограммов яблок и 2 литра молока"
        )
    }
}

// MARK: - Edge cases (test gaps from review)

final class NumberNormalizerEdgeCaseTests: XCTestCase {
    /// Gap 1: Empty input
    func test_normalize_empty_string() {
        XCTAssertEqual(NumberNormalizer.normalize(""), "")
    }

    func test_parseNumber_empty_array() {
        XCTAssertNil(NumberNormalizer.parseNumber([]))
    }

    /// Gap 2: четверть
    func test_parse_четверть() {
        let r = NumberNormalizer.parseNumber(["четверть"])
        XCTAssertEqual(r?.value, 0.25)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    func test_format_quarter() {
        XCTAssertEqual(NumberNormalizer.formatNumber(0.25), "0,25")
    }

    func test_format_zero() {
        XCTAssertEqual(NumberNormalizer.formatNumber(0), "0")
    }

    /// Gap 3: Спецформы — самодостаточные (fix verification)
    func test_полтора_два_stops_after_полтора() {
        let r = NumberNormalizer.parseNumber(["полтора", "два"])
        XCTAssertEqual(r?.value, 1.5)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    func test_четверть_пять_stops_after_четверть() {
        let r = NumberNormalizer.parseNumber(["четверть", "пять"])
        XCTAssertEqual(r?.value, 0.25)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    /// Gap 4: ноль terminal (fix verification)
    func test_ноль_пять_stops_after_ноль() {
        let r = NumberNormalizer.parseNumber(["ноль", "пять"])
        XCTAssertEqual(r?.value, 0)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    func test_ноль_ноль_stops_after_first() {
        let r = NumberNormalizer.parseNumber(["ноль", "ноль"])
        XCTAssertEqual(r?.value, 0)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    /// Gap 5: Multiplier ordering (fix verification)
    func test_тысяча_тысяча_stops() {
        let r = NumberNormalizer.parseNumber(["тысяча", "тысяча"])
        XCTAssertEqual(r?.value, 1_000)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    func test_тысяча_миллион_stops() {
        let r = NumberNormalizer.parseNumber(["тысяча", "миллион"])
        XCTAssertEqual(r?.value, 1_000)
        XCTAssertEqual(r?.consumedCount, 1)
    }

    /// Gap 6: четверть часа (fix verification)
    func test_четверть_часа_untouched() {
        XCTAssertEqual(NumberNormalizer.normalize("четверть часа"), "четверть часа")
    }

    /// Gap 7: Time range validation (fix verification)
    func test_двести_часов_not_time() {
        XCTAssertEqual(NumberNormalizer.normalize("в двести часов"), "в 200 часов")
    }

    /// Gap 8: Time prepositions — до/с/после
    func test_до_пяти_часов() {
        XCTAssertEqual(NumberNormalizer.normalize("до пяти часов"), "до 5:00")
    }

    func test_после_шести_часов() {
        XCTAssertEqual(NumberNormalizer.normalize("после шести часов"), "после 6:00")
    }

    func test_с_трёх_часов() {
        XCTAssertEqual(NumberNormalizer.normalize("с трёх часов"), "с 3:00")
    }

    /// Gap 9: Trailing punctuation on triggers
    func test_percent_with_trailing_period() {
        XCTAssertEqual(NumberNormalizer.normalize("двадцать пять процентов."), "25%.")
    }

    func test_date_month_with_trailing_period() {
        XCTAssertEqual(NumberNormalizer.normalize("тринадцатое марта."), "13 марта.")
    }

    /// Gap 10: tensCardinals 40-90 (fix verification)
    func test_сорок_пятый_ordinal() {
        XCTAssertEqual(NumberNormalizer.normalize("сорок пятый"), "45-й")
    }

    func test_пятьдесят_второй_ordinal() {
        XCTAssertEqual(NumberNormalizer.normalize("пятьдесят второй"), "52-й")
    }

    /// Gap 11: Idempotency — все трансформации
    func test_idempotent_currency() {
        let once = NumberNormalizer.normalize("тысяча рублей")
        let twice = NumberNormalizer.normalize(once)
        XCTAssertEqual(once, twice)
    }

    func test_idempotent_time() {
        let once = NumberNormalizer.normalize("в пять часов")
        let twice = NumberNormalizer.normalize(once)
        XCTAssertEqual(once, twice)
    }

    func test_idempotent_ordinal() {
        let once = NumberNormalizer.normalize("пятая версия")
        let twice = NumberNormalizer.normalize(once)
        XCTAssertEqual(once, twice)
    }

    func test_idempotent_date() {
        let once = NumberNormalizer.normalize("тринадцатое марта")
        let twice = NumberNormalizer.normalize(once)
        XCTAssertEqual(once, twice)
    }

    /// Gap 12: Transformation ordering — число после валюты
    func test_number_after_currency_still_normalizes() {
        XCTAssertEqual(
            NumberNormalizer.normalize("сто рублей двадцать"),
            "100 рублей 20"
        )
    }

    /// Gap 13: пять часов без контекста = длительность
    func test_пять_часов_alone_is_duration() {
        XCTAssertEqual(NumberNormalizer.normalize("пять часов"), "5 часов")
    }
}

// MARK: - Token layer (v2) roundtrip

final class TokenLayerTests: XCTestCase {
    func test_roundtrip_plain_text() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("привет мир"),
            "привет мир"
        )
    }

    func test_roundtrip_trailing_period() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("двадцать пять процентов."),
            "двадцать пять процентов."
        )
    }

    func test_roundtrip_trailing_comma() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("тысяча рублей, в месяц"),
            "тысяча рублей, в месяц"
        )
    }

    func test_roundtrip_parentheses() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("(тысяча рублей)"),
            "(тысяча рублей)"
        )
    }

    func test_roundtrip_guillemets() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("«привет!»"),
            "«привет!»"
        )
    }

    func test_roundtrip_percent_symbol() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("25%."),
            "25%."
        )
    }

    func test_roundtrip_currency_symbol() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("1000\u{20BD}"),
            "1000\u{20BD}"
        )
    }

    func test_roundtrip_ordinal_dash() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("25-й этаж"),
            "25-й этаж"
        )
    }

    func test_roundtrip_exclamation() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("отлично!"),
            "отлично!"
        )
    }

    func test_roundtrip_multiple_punctuation() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("правда?!"),
            "правда?!"
        )
    }

    func test_roundtrip_empty_string() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip(""),
            ""
        )
    }

    func test_roundtrip_single_word() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("слово"),
            "слово"
        )
    }

    func test_roundtrip_complex_sentence() {
        XCTAssertEqual(
            NumberNormalizer.tokenizeRoundtrip("(до пяти часов,) стоит 200 рублей."),
            "(до пяти часов,) стоит 200 рублей."
        )
    }
}

// MARK: - Numeric parser (v2)

final class NumericParserTests: XCTestCase {
    /// Простое целое число
    func test_simple_integer() {
        let r = NumberNormalizer.testParseNumeric("42")
        XCTAssertEqual(r?.value, 42)
        XCTAssertEqual(r?.consumed, 1)
        XCTAssertNil(r?.currency)
    }

    /// Пробельно-разделённое число: 1 000
    func test_space_grouped_1000() {
        let r = NumberNormalizer.testParseNumeric("1 000")
        XCTAssertEqual(r?.value, 1_000)
        XCTAssertEqual(r?.consumed, 2)
    }

    // Пробельно-разделённое: 1 000 000
    func test_space_grouped_million() {
        let r = NumberNormalizer.testParseNumeric("1 000 000")
        XCTAssertEqual(r?.value, 1_000_000)
        XCTAssertEqual(r?.consumed, 3)
    }

    /// Дробное с запятой: 2,5
    func test_decimal_comma() {
        let r = NumberNormalizer.testParseNumeric("2,5")
        XCTAssertEqual(r?.value, 2.5)
        XCTAssertEqual(r?.consumed, 1)
    }

    /// Слитное большое число: 2000000
    func test_large_solid_number() {
        let r = NumberNormalizer.testParseNumeric("2000000")
        XCTAssertEqual(r?.value, 2_000_000)
        XCTAssertEqual(r?.consumed, 1)
    }

    /// Число + символ рубля: 1000₽
    func test_currency_symbol_rub() {
        let r = NumberNormalizer.testParseNumeric("1000\u{20BD}")
        XCTAssertEqual(r?.value, 1_000)
        XCTAssertEqual(r?.consumed, 1)
        XCTAssertEqual(r?.currency, "rub")
    }

    /// Пробельное + символ рубля: 1 000₽
    func test_space_grouped_with_currency() {
        let r = NumberNormalizer.testParseNumeric("1 000\u{20BD}")
        XCTAssertEqual(r?.value, 1_000)
        XCTAssertEqual(r?.consumed, 2)
        XCTAssertEqual(r?.currency, "rub")
    }

    /// Число + $ символ
    func test_currency_symbol_usd() {
        let r = NumberNormalizer.testParseNumeric("500$")
        XCTAssertEqual(r?.value, 500)
        XCTAssertEqual(r?.currency, "usd")
    }

    /// Число + € символ
    func test_currency_symbol_eur() {
        let r = NumberNormalizer.testParseNumeric("200\u{20AC}")
        XCTAssertEqual(r?.value, 200)
        XCTAssertEqual(r?.currency, "eur")
    }

    // Сокращение: 2 млн
    func test_abbreviation_mln() {
        let r = NumberNormalizer.testParseNumeric("2 млн")
        XCTAssertEqual(r?.value, 2_000_000)
        XCTAssertEqual(r?.consumed, 2)
        XCTAssertEqual(r?.abbreviated, true)
    }

    // Сокращение: 5 тыс.
    func test_abbreviation_tys() {
        let r = NumberNormalizer.testParseNumeric("5 тыс.")
        XCTAssertEqual(r?.value, 5_000)
        XCTAssertEqual(r?.consumed, 2)
        XCTAssertEqual(r?.abbreviated, true)
    }

    // Сокращение: 3 млрд
    func test_abbreviation_mlrd() {
        let r = NumberNormalizer.testParseNumeric("3 млрд")
        XCTAssertEqual(r?.value, 3_000_000_000)
        XCTAssertEqual(r?.consumed, 2)
    }

    /// Не число — nil
    func test_non_numeric_returns_nil() {
        let r = NumberNormalizer.testParseNumeric("привет")
        XCTAssertNil(r)
    }

    /// Слово, начинающееся не с цифры
    func test_word_starting_with_letter_returns_nil() {
        let r = NumberNormalizer.testParseNumeric("abc123")
        XCTAssertNil(r)
    }

    /// Число без trailing группы не склеивает
    func test_number_followed_by_word() {
        let r = NumberNormalizer.testParseNumeric("100 рублей")
        XCTAssertEqual(r?.value, 100)
        XCTAssertEqual(r?.consumed, 1)
    }

    /// 25 (маленькое число)
    func test_small_two_digit() {
        let r = NumberNormalizer.testParseNumeric("25")
        XCTAssertEqual(r?.value, 25)
        XCTAssertEqual(r?.consumed, 1)
    }
}

// MARK: - Span conflict resolution (v2)

final class SpanConflictTests: XCTestCase {
    /// money (100) побеждает cardinal (40) при пересечении
    func test_money_beats_cardinal() {
        let result = NumberNormalizer.testResolveConflicts([
            (0, 3, 40, "cardinal"), // "тысяча" как кардинал (tokens 0-2)
            (0, 3, 100, "money"), // "тысяча рублей" как деньги (tokens 0-2)
        ])
        XCTAssertEqual(result, ["money"])
    }

    /// Непересекающиеся спаны — оба принимаются
    func test_non_overlapping_both_accepted() {
        let result = NumberNormalizer.testResolveConflicts([
            (0, 2, 80, "percent"),
            (3, 5, 100, "money"),
        ])
        XCTAssertEqual(result, ["percent", "money"])
    }

    /// time (90) побеждает duration (55)
    func test_time_beats_duration() {
        let result = NumberNormalizer.testResolveConflicts([
            (0, 3, 55, "duration"),
            (0, 3, 90, "time"),
        ])
        XCTAssertEqual(result, ["time"])
    }

    /// date (85) побеждает ordinal (60)
    func test_date_beats_ordinal() {
        let result = NumberNormalizer.testResolveConflicts([
            (0, 2, 60, "ordinal"),
            (0, 2, 85, "date"),
        ])
        XCTAssertEqual(result, ["date"])
    }

    /// ordinal (60) побеждает cardinal (40)
    func test_ordinal_beats_cardinal() {
        let result = NumberNormalizer.testResolveConflicts([
            (0, 2, 40, "cardinal"),
            (0, 2, 60, "ordinal"),
        ])
        XCTAssertEqual(result, ["ordinal"])
    }

    /// percent (80) побеждает cardinal (40)
    func test_percent_beats_cardinal() {
        let result = NumberNormalizer.testResolveConflicts([
            (0, 3, 40, "cardinal"),
            (0, 3, 80, "percent"),
        ])
        XCTAssertEqual(result, ["percent"])
    }

    /// Три спана: высокий поглощает средний, низкий непересекающийся — принят
    func test_three_spans_partial_overlap() {
        let result = NumberNormalizer.testResolveConflicts([
            (0, 3, 100, "money"), // tokens 0-2
            (1, 3, 40, "cardinal"), // tokens 1-2, пересекается с money
            (4, 6, 60, "ordinal"), // tokens 4-5, не пересекается
        ])
        XCTAssertEqual(result, ["money", "ordinal"])
    }

    /// Пустой вход
    func test_empty_spans() {
        let result = NumberNormalizer.testResolveConflicts([])
        XCTAssertEqual(result, [])
    }

    /// Один спан
    func test_single_span() {
        let result = NumberNormalizer.testResolveConflicts([
            (0, 2, 40, "cardinal"),
        ])
        XCTAssertEqual(result, ["cardinal"])
    }
}

// MARK: - CanonicalFormatter (v2)

final class CanonicalFormatterTests: XCTestCase {
    /// formatPercent
    func test_format_percent_integer() {
        XCTAssertEqual(NumberNormalizer.testFormatPercent(25), "25%")
    }

    func test_format_percent_decimal() {
        XCTAssertEqual(NumberNormalizer.testFormatPercent(1.5), "1,5%")
    }

    func test_format_percent_hundred() {
        XCTAssertEqual(NumberNormalizer.testFormatPercent(100), "100%")
    }

    /// formatMoney
    func test_format_money_rub() {
        XCTAssertEqual(NumberNormalizer.testFormatMoney(1_000, currency: "rub"), "1 000 рублей")
    }

    func test_format_money_usd() {
        XCTAssertEqual(NumberNormalizer.testFormatMoney(500, currency: "usd"), "500 долларов")
    }

    func test_format_money_eur() {
        XCTAssertEqual(NumberNormalizer.testFormatMoney(200, currency: "eur"), "200 евро")
    }

    func test_format_money_large() {
        XCTAssertEqual(NumberNormalizer.testFormatMoney(2_000_000, currency: "rub"), "2 000 000 рублей")
    }

    /// formatTime
    func test_format_time_full_hour() {
        XCTAssertEqual(NumberNormalizer.testFormatTime(5, 0), "5:00")
    }

    func test_format_time_with_minutes() {
        XCTAssertEqual(NumberNormalizer.testFormatTime(2, 15), "2:15")
    }

    func test_format_time_single_digit_minute() {
        XCTAssertEqual(NumberNormalizer.testFormatTime(10, 5), "10:05")
    }

    /// formatOrdinal
    func test_format_ordinal_basic() {
        XCTAssertEqual(NumberNormalizer.testFormatOrdinal(25, "-й"), "25-й")
    }

    func test_format_ordinal_feminine() {
        XCTAssertEqual(NumberNormalizer.testFormatOrdinal(5, "-я"), "5-я")
    }

    func test_format_ordinal_neuter() {
        XCTAssertEqual(NumberNormalizer.testFormatOrdinal(1, "-е"), "1-е")
    }
}

// MARK: - v2 проценты + деньги через Span

final class V2PercentMoneySpanTests: XCTestCase {
    /// Spoken проценты с пунктуацией
    func test_percent_trailing_period() {
        XCTAssertEqual(NumberNormalizer.normalize("двадцать пять процентов."), "25%.")
    }

    func test_percent_trailing_comma() {
        XCTAssertEqual(NumberNormalizer.normalize("двадцать пять процентов, и всё"), "25%, и всё")
    }

    // GigaAM: 1000₽ → 1 000 рублей
    func test_gigaam_rub_symbol() {
        XCTAssertEqual(NumberNormalizer.normalize("1000\u{20BD}"), "1 000 рублей")
    }

    // GigaAM: 500$ → 500 долларов
    func test_gigaam_usd_symbol() {
        XCTAssertEqual(NumberNormalizer.normalize("500$"), "500 долларов")
    }

    // GigaAM: 200€ → 200 евро
    func test_gigaam_eur_symbol() {
        XCTAssertEqual(NumberNormalizer.normalize("200\u{20AC}"), "200 евро")
    }

    // GigaAM: 1 000₽ (с пробелом) → 1 000 рублей
    func test_gigaam_rub_symbol_space_grouped() {
        XCTAssertEqual(NumberNormalizer.normalize("1 000\u{20BD}"), "1 000 рублей")
    }

    // GigaAM: 2 млн → 2 000 000
    func test_gigaam_abbreviation_mln() {
        XCTAssertEqual(NumberNormalizer.normalize("2 млн"), "2 000 000")
    }

    // GigaAM: 5 тыс. → 5 000
    func test_gigaam_abbreviation_tys() {
        XCTAssertEqual(NumberNormalizer.normalize("5 тыс."), "5 000")
    }

    // Смешанное: GigaAM число + spoken слова
    func test_mixed_numeric_and_spoken() {
        XCTAssertEqual(
            NumberNormalizer.normalize("итого 1000\u{20BD} и двадцать пять процентов"),
            "итого 1 000 рублей и 25%"
        )
    }

    // Пунктуация: (тысяча рублей,)
    func test_money_in_parentheses() {
        XCTAssertEqual(
            NumberNormalizer.normalize("(тысяча рублей)"),
            "(1 000 рублей)"
        )
    }

    /// Число + валютное слово: 100 рублей
    func test_numeric_plus_currency_word() {
        XCTAssertEqual(NumberNormalizer.normalize("100 рублей"), "100 рублей")
    }

    /// Символ валюты с пунктуацией: 1000₽.
    func test_currency_symbol_with_trailing_period() {
        XCTAssertEqual(NumberNormalizer.normalize("1000\u{20BD}."), "1 000 рублей.")
    }
}

// MARK: - v2 время + даты через Span

final class V2TimeDateSpanTests: XCTestCase {
    /// Время с предлогом + пунктуация
    func test_time_with_trailing_comma() {
        XCTAssertEqual(
            NumberNormalizer.normalize("в пять часов, на встрече"),
            "в 5:00, на встрече"
        )
    }

    /// Длительность с пунктуацией
    func test_duration_trailing_period() {
        XCTAssertEqual(
            NumberNormalizer.normalize("пять часов."),
            "5 часов."
        )
    }

    /// Дата с пунктуацией
    func test_date_trailing_period() {
        XCTAssertEqual(
            NumberNormalizer.normalize("тринадцатое марта."),
            "13 марта."
        )
    }

    /// Скобочная дата
    func test_date_in_parentheses() {
        XCTAssertEqual(
            NumberNormalizer.normalize("(первое сентября)"),
            "(1 сентября)"
        )
    }

    /// Время в скобках
    func test_time_in_parentheses() {
        XCTAssertEqual(
            NumberNormalizer.normalize("(до пяти часов)"),
            "(до 5:00)"
        )
    }

    /// Полчаса
    func test_polchasa() {
        XCTAssertEqual(NumberNormalizer.normalize("полчаса"), "30 минут")
    }
}

// MARK: - Property tests (v2)

final class NumberNormalizerPropertyTests: XCTestCase {
    // Идемпотентность: normalize(normalize(x)) == normalize(x)
    func test_idempotent_percent() {
        let once = NumberNormalizer.normalize("двадцать пять процентов")
        XCTAssertEqual(NumberNormalizer.normalize(once), once)
    }

    func test_idempotent_money() {
        let once = NumberNormalizer.normalize("тысяча рублей")
        XCTAssertEqual(NumberNormalizer.normalize(once), once)
    }

    func test_idempotent_time() {
        let once = NumberNormalizer.normalize("в пять часов")
        XCTAssertEqual(NumberNormalizer.normalize(once), once)
    }

    func test_idempotent_date() {
        let once = NumberNormalizer.normalize("тринадцатое марта")
        XCTAssertEqual(NumberNormalizer.normalize(once), once)
    }

    func test_idempotent_ordinal() {
        let once = NumberNormalizer.normalize("двадцать пятый")
        XCTAssertEqual(NumberNormalizer.normalize(once), once)
    }

    func test_idempotent_cardinal() {
        let once = NumberNormalizer.normalize("двадцать пять")
        XCTAssertEqual(NumberNormalizer.normalize(once), once)
    }

    func test_idempotent_gigaam_currency() {
        let once = NumberNormalizer.normalize("1000\u{20BD}")
        XCTAssertEqual(NumberNormalizer.normalize(once), once)
    }

    func test_idempotent_gigaam_abbreviation() {
        let once = NumberNormalizer.normalize("2 млн")
        XCTAssertEqual(NumberNormalizer.normalize(once), once)
    }

    /// Пунктуация сохраняется
    func test_punctuation_preserved_period() {
        let result = NumberNormalizer.normalize("двадцать пятое.")
        XCTAssertTrue(result.hasSuffix("."), "Точка потеряна: \(result)")
    }

    func test_punctuation_preserved_comma() {
        let result = NumberNormalizer.normalize("тысяча рублей,")
        XCTAssertTrue(result.hasSuffix(","), "Запятая потеряна: \(result)")
    }

    func test_punctuation_preserved_exclamation() {
        let result = NumberNormalizer.normalize("двадцать пять!")
        XCTAssertTrue(result.hasSuffix("!"), "Восклицательный знак потерян: \(result)")
    }

    func test_punctuation_preserved_parentheses() {
        let result = NumberNormalizer.normalize("(двадцать пять)")
        XCTAssertTrue(result.hasPrefix("(") && result.hasSuffix(")"), "Скобки потеряны: \(result)")
    }

    /// Unsupported input → unchanged
    func test_unsupported_unchanged() {
        XCTAssertEqual(NumberNormalizer.normalize("привет мир"), "привет мир")
    }

    func test_empty_unchanged() {
        XCTAssertEqual(NumberNormalizer.normalize(""), "")
    }
}

// MARK: - GigaAM tabular tests (v2)

final class GigaAMTabularTests: XCTestCase {
    /// Канонический формат: GigaAM цифры → каноническое представление
    func test_gigaam_1000_rub() {
        XCTAssertEqual(NumberNormalizer.normalize("1000\u{20BD}"), "1 000 рублей")
    }

    func test_gigaam_500_usd() {
        XCTAssertEqual(NumberNormalizer.normalize("500$"), "500 долларов")
    }

    func test_gigaam_2_mln() {
        XCTAssertEqual(NumberNormalizer.normalize("2 млн"), "2 000 000")
    }

    func test_gigaam_5_tys() {
        XCTAssertEqual(NumberNormalizer.normalize("5 тыс."), "5 000")
    }

    func test_gigaam_2000000_formatted() {
        XCTAssertEqual(NumberNormalizer.normalize("2000000"), "2 000 000")
    }

    func test_gigaam_25_percent_already_canonical() {
        XCTAssertEqual(NumberNormalizer.normalize("25%"), "25%")
    }

    /// Canonical equivalence: spoken == numeric
    func test_canonical_money_equivalence() {
        let spoken = NumberNormalizer.normalize("тысяча рублей")
        let numeric = NumberNormalizer.normalize("1000\u{20BD}")
        XCTAssertEqual(spoken, numeric)
    }

    func test_canonical_abbreviation_equivalence() {
        let abbrev = NumberNormalizer.normalize("2 млн")
        let full = NumberNormalizer.normalize("два миллиона")
        XCTAssertEqual(abbrev, full)
    }

    /// Сложные GigaAM-реальные фразы
    func test_gigaam_trailing_punctuation_period() {
        XCTAssertEqual(NumberNormalizer.normalize("двадцать пятое."), "25-е.")
    }

    func test_gigaam_in_parentheses_with_comma() {
        XCTAssertEqual(
            NumberNormalizer.normalize("(до пяти часов,)"),
            "(до 5:00,)"
        )
    }

    func test_gigaam_percent_with_period() {
        XCTAssertEqual(NumberNormalizer.normalize("25%."), "25%.")
    }

    func test_gigaam_1000_rub_with_period() {
        XCTAssertEqual(NumberNormalizer.normalize("1000\u{20BD}."), "1 000 рублей.")
    }

    // #8: дробная аббревиатура
    func test_gigaam_decimal_abbreviation_mln() {
        XCTAssertEqual(NumberNormalizer.normalize("2,5 млн"), "2 500 000")
    }

    func test_idempotent_decimal_abbreviation() {
        let once = NumberNormalizer.normalize("2,5 млн")
        XCTAssertEqual(NumberNormalizer.normalize(once), once)
    }

    // #10: 3 млрд через normalize()
    func test_gigaam_abbreviation_mlrd() {
        XCTAssertEqual(NumberNormalizer.normalize("3 млрд"), "3 000 000 000")
    }

    // #11: canonical form — склонение по числу
    func test_один_рубль_canonical_form() {
        XCTAssertEqual(NumberNormalizer.normalize("один рубль"), "1 рубль")
    }
}

// MARK: - Склонение валют

final class CurrencyDeclensionTests: XCTestCase {
    func test_один_рубль() {
        XCTAssertEqual(NumberNormalizer.normalize("один рубль"), "1 рубль")
    }

    func test_два_рубля() {
        XCTAssertEqual(NumberNormalizer.normalize("два рубля"), "2 рубля")
    }

    func test_пять_рублей() {
        XCTAssertEqual(NumberNormalizer.normalize("пять рублей"), "5 рублей")
    }

    func test_двадцать_один_рубль() {
        XCTAssertEqual(NumberNormalizer.normalize("двадцать один рубль"), "21 рубль")
    }

    func test_одиннадцать_рублей() {
        XCTAssertEqual(NumberNormalizer.normalize("одиннадцать рублей"), "11 рублей")
    }

    func test_сто_два_доллара() {
        XCTAssertEqual(NumberNormalizer.normalize("сто два доллара"), "102 доллара")
    }

    func test_тысяча_рублей() {
        XCTAssertEqual(NumberNormalizer.normalize("тысяча рублей"), "1 000 рублей")
    }

    func test_один_доллар() {
        XCTAssertEqual(NumberNormalizer.normalize("один доллар"), "1 доллар")
    }

    func test_евро_не_склоняется() {
        XCTAssertEqual(NumberNormalizer.normalize("одно евро"), "1 евро")
        XCTAssertEqual(NumberNormalizer.normalize("два евро"), "2 евро")
        XCTAssertEqual(NumberNormalizer.normalize("пять евро"), "5 евро")
    }
}
