import Foundation

// MARK: - Продуктовый режим

enum ProductMode: String, CaseIterable, Codable {
    case standard
    case superMode = "super"
    case cloud

    var usesLLM: Bool {
        self == .superMode || self == .cloud
    }

    var usesLocalLLM: Bool {
        self == .superMode
    }

    var isCloud: Bool {
        self == .cloud
    }

    var title: String {
        switch self {
        case .standard:
            "Говорун"
        case .superMode:
            "Говорун Super"
        case .cloud:
            "Говорун Cloud"
        }
    }

    var subtitle: String {
        switch self {
        case .standard:
            "Быстрый голосовой ввод без ИИ-обработки"
        case .superMode:
            "Голосовой ввод с ИИ-усилением"
        case .cloud:
            "Голосовой ввод через GigaChat Max"
        }
    }
}
