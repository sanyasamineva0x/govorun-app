import Foundation
import SwiftData

@Model
final class DictionaryEntry {
    var word: String
    var alternatives: [String]
    var isAutoLearned: Bool
    var usageCount: Int
    var createdAt: Date

    init(
        word: String,
        alternatives: [String] = [],
        isAutoLearned: Bool = false,
        usageCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.word = word
        self.alternatives = alternatives
        self.isAutoLearned = isAutoLearned
        self.usageCount = usageCount
        self.createdAt = createdAt
    }
}
