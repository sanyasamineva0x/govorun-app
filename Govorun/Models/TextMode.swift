import Foundation

// MARK: - Режимы текста

enum TextMode: String, CaseIterable, Codable, Sendable {
    case chat
    case email
    case document
    case note
    case code
    case universal
}

// MARK: - Промпт-генерация

extension TextMode {

    /// Базовый system prompt (design-doc 5.4)
    static func basePrompt(currentDate: Date, personalDictionary: [String: String] = [:]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        let dateString = formatter.string(from: currentDate)

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ru_RU")
        dayFormatter.dateFormat = "EEEE"
        let dayOfWeek = dayFormatter.string(from: currentDate)

        let dictBlock: String
        if personalDictionary.isEmpty {
            dictBlock = ""
        } else {
            let entries = personalDictionary.map { "\($0.key)→\($0.value)" }.joined(separator: ", ")
            dictBlock = "\n- Личный словарь: \(entries)"
        }

        return """
        Ты обрабатываешь устную речь, превращая её в чистый письменный текст.
        Сегодня: \(dateString), \(dayOfWeek).

        ПРИОРИТЕТ ПРАВИЛ (от высшего к низшему):
        1. Самокоррекция
        2. Стилевой блок (см. ниже)
        3. Очистка, транслитерация, числа

        САМОКОРРЕКЦИЯ — главное правило:
        Если человек поправляет себя на ходу — бери ТОЛЬКО ПОСЛЕДНЮЮ версию, старую УДАЛИ целиком.
        Маркеры коррекции: «ой точнее», «то есть», «нет подожди», «в смысле», \
        «я имею в виду», «или нет лучше», «хотя нет», «а нет», «не X а Y» и так далее.
        Убери маркер И ВСЁ, что было ДО него по теме коррекции. Оставь только финальный вариант.
        ТИПИЧНАЯ ОШИБКА: НЕ расставляй запятые в самокоррекции — УДАЛЯЙ всё до маркера.
        «в понедельник или нет лучше во вторник» — НЕПРАВИЛЬНО: «В понедельник или нет, лучше во вторник.» ПРАВИЛЬНО: «Во вторник»
        Примеры самокоррекции:
        «в понедельник или нет лучше во вторник» → «Во вторник»
        «напиши маше а нет лучше пете» → «Напиши Пете»
        «купи молоко хотя нет лучше кефир» → «Купи кефир»

        ОЧИСТКА:
        - Убирай слова-паразиты (ну, короче, типа, в общем, как бы, вот, значит)
        - Убери мелкие оговорки и запинки
        - Добавь пунктуацию и заглавные буквы
        - НЕ заменяй слова синонимами — сохрани лексику автора
        - НЕ переставляй слова местами — сохрани порядок слов автора
        - НЕ добавляй слов, которых не было в оригинале (никаких «пожалуйста», «её», «это»)
        - Удаление филлеров и самокоррекции — это не перефразирование
        - Не удаляй характерные фразы и мат — они часть речи автора
        - Если это вопрос — ставь вопросительный знак

        ТРАНСЛИТЕРАЦИЯ:
        - Правило транслитерации брендов задаётся стилевым блоком ниже
        - Устоявшиеся заимствования → кириллица (интернет, компьютер)\(dictBlock)

        ЧИСЛА И ДАТЫ:
        - Числительные → цифры, деньги → с символом (₽, $), время → HH:MM
        - Относительные даты оставляй как есть (завтра, в четверг, на следующей неделе)
        - Проценты → %
        - Русская локаль: запятая в дробях, пробелы в тысячах

        ПРИМЕРЫ (формат: вход → выход):
        «ну привет саня короче в общем давай встретимся в пять» → \
        «Привет, Саня, давай встретимся в 17:00»
        «отправь отчёт марку ой точнее саше в четверг» → \
        «Отправь отчёт Саше в четверг»
        «закинь таск в жиру на пятьсот рублей» → \
        «Закинь таск в Jira на 500 ₽»
        «нахуй эту задачу закрой» → «Нахуй, эту задачу закрой»
        «открой ноушн» → «Открой Notion»

        Кавычки — ёлочки («»).
        Верни ТОЛЬКО обработанный текст, без объяснений.
        """
    }

    /// Стилевой блок (design-doc 6.4)
    var styleBlock: String {
        switch self {
        case .chat:
            return "Стиль: разговорный, краткий. Регистр \"ты\". " +
                "ПЕРЕОПРЕДЕЛЕНИЕ регистра: НЕ ставь заглавную букву в начале предложения. Пиши всё строчными, как в мессенджере. Без точки в конце. " +
                "ПЕРЕОПРЕДЕЛЕНИЕ транслитерации: бренды → кириллица строчными (слак, зум, жира, гитхаб, ноушн). " +
                "Пример: «скинь в слак» → «скинь в слак», «открой ноушн» → «открой ноушн»."
        case .email:
            return "Стиль: деловой, вежливый. Регистр \"Вы\". " +
                "Полные предложения. Транслитерация: бренды → оригинал (Slack, Zoom)."
        case .document:
            return "Стиль: формальный, структурированный. Регистр \"Вы\". " +
                "Абзацы где уместно. Транслитерация: бренды → оригинал."
        case .note:
            return "Стиль: свободный, лаконичный. Регистр \"ты\". " +
                "Если перечисление — оформи списком. " +
                "Транслитерация: бренды → оригинал (Slack, Zoom, Jira)."
        case .code:
            return "Минимальная обработка. Технические термины не трогать. " +
                "Транслитерация: всё → оригинал (pull request, staging, deploy)."
        case .universal:
            return "Регистр \"ты\" по умолчанию. Чистый текст. " +
                "Транслитерация: бренды → оригинал (Slack, Zoom, Jira)."
        }
    }

    /// Полный system prompt = base + style + snippet block
    func systemPrompt(
        currentDate: Date,
        personalDictionary: [String: String] = [:],
        snippetContext: SnippetContext? = nil,
        appName: String? = nil
    ) -> String {
        var prompt = TextMode.basePrompt(currentDate: currentDate, personalDictionary: personalDictionary)
        prompt += "\n\n" + styleBlock

        if let app = appName, !app.isEmpty {
            prompt += """

            КОНТЕКСТ ПРИЛОЖЕНИЯ:
            Пользователь диктует в приложении «\(app)».
            Учитывай это при выборе тональности и оформления.
            """
        }

        if let snippet = snippetContext {
            prompt += """

            ПОДСТАНОВКА:
            Пользователь использовал голосовое сокращение «\(snippet.trigger)».
            На место этого сокращения вставь РОВНО токен \(SnippetPlaceholder.token) — без кавычек, без изменений.
            НЕ вставляй значение сокращения — только токен.
            Построй естественное предложение вокруг токена.
            Токен должен стоять отдельно, окружённым пробелами или пунктуацией.
            Примеры:
            - "скинь на мой имейл" → "Скинь на мой имейл: \(SnippetPlaceholder.token)"
            - "привет вот мой адрес" → "Привет, мой адрес — \(SnippetPlaceholder.token)."
            - "отправь на мой телефон" → "Отправь на мой телефон: \(SnippetPlaceholder.token)."
            """
        }

        return prompt
    }
}

// MARK: - Snippet Placeholder

enum SnippetPlaceholder {
    static let token = "[[[GOVORUN_SNIPPET]]]"
}

// MARK: - Snippet Context

struct SnippetContext: Sendable, Equatable {
    let trigger: String
}

// MARK: - Хинты для нормализации

struct NormalizationHints: Sendable, Equatable {
    let personalDictionary: [String: String]
    let appName: String?
    let textMode: TextMode
    let currentDate: Date
    let snippetContext: SnippetContext?

    init(
        personalDictionary: [String: String] = [:],
        appName: String? = nil,
        textMode: TextMode = .universal,
        currentDate: Date = Date(),
        snippetContext: SnippetContext? = nil
    ) {
        self.personalDictionary = personalDictionary
        self.appName = appName
        self.textMode = textMode
        self.currentDate = currentDate
        self.snippetContext = snippetContext
    }
}
