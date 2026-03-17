import Foundation
import SwiftData

// MARK: - Режим сопоставления

enum MatchMode: String, Codable, Sendable {
    case exact
    case fuzzy
}

// MARK: - Snippet (SwiftData)

@Model
final class Snippet {
    var trigger: String
    var content: String
    var matchMode: MatchMode
    var isEnabled: Bool
    var usageCount: Int
    var createdAt: Date

    init(
        trigger: String,
        content: String,
        matchMode: MatchMode = .fuzzy,
        isEnabled: Bool = true,
        usageCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.trigger = trigger
        self.content = content
        self.matchMode = matchMode
        self.isEnabled = isEnabled
        self.usageCount = usageCount
        self.createdAt = createdAt
    }
}
