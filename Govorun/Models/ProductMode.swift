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
            "Только GigaAM и deterministic-очистка. Быстрее и предсказуемо."
        case .superMode:
            "Добавляет локальную LLM-нормализацию для более чистого текста."
        }
    }
}
