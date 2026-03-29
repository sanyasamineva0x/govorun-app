import Foundation

// MARK: - Стиль текста

enum SuperTextStyle: String, CaseIterable, Codable {
    case relaxed
    case normal
    case formal
}

// MARK: - Режим выбора стиля

enum SuperStyleMode: String, CaseIterable {
    case auto
    case manual
}

// MARK: - Свойства

extension SuperTextStyle {
    var contract: LLMOutputContract {
        .normalization
    }

    var displayName: String {
        switch self {
        case .relaxed: "Расслабленный"
        case .normal: "Обычный"
        case .formal: "Формальный"
        }
    }

    func applyDeterministic(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        switch self {
        case .relaxed:
            return text.prefix(1).lowercased() + text.dropFirst()
        case .normal, .formal:
            return text.prefix(1).uppercased() + text.dropFirst()
        }
    }
}

// MARK: - Таблицы алиасов

extension SuperTextStyle {
    static let brandAliases: [(original: String, relaxed: String)] = [
        ("Slack", "слак"),
        ("Zoom", "зум"),
        ("Telegram", "телега"),
        ("Jira", "жира"),
        ("Notion", "ношен"),
        ("GitHub", "гитхаб"),
        ("YouTube", "ютуб"),
        ("Google", "гугл"),
        ("WhatsApp", "вотсап"),
        ("Discord", "дискорд"),
        ("Figma", "фигма"),
        ("Docker", "докер"),
        ("Chrome", "хром"),
        ("Safari", "сафари"),
        ("Teams", "тимс"),
        ("Trello", "трелло"),
        ("Confluence", "конфлюенс"),
        ("Excel", "эксель"),
        ("Word", "ворд"),
        ("Photoshop", "фотошоп"),
        ("iPhone", "айфон"),
        ("MacBook", "макбук"),
        ("Windows", "винда"),
        ("Linux", "линукс"),
        ("Python", "питон"),
    ]

    static let techTermAliases: [(original: String, relaxed: String)] = [
        ("PDF", "пдф"),
        ("API", "апи"),
        ("URL", "урл"),
        ("PR", "пр"),
    ]
}
