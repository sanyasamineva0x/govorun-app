import Foundation

// MARK: - Продуктовый режим

enum ProductMode: String, CaseIterable, Codable {
    case standard
    case superMode = "super"

    var usesLLM: Bool {
        self == .superMode
    }

    var title: String {
        switch self {
        case .standard:
            "Говорун"
        case .superMode:
            "Говорун Super"
        }
    }

    var subtitle: String {
        switch self {
        case .standard:
            "Быстрый голосовой ввод без ИИ-обработки"
        case .superMode:
            "Голосовой ввод с ИИ-усилением"
        }
    }
}
