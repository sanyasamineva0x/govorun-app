import Foundation

// MARK: - Хинты для нормализации

struct NormalizationHints: Equatable {
    let personalDictionary: [String: String]
    let appName: String?
    let currentDate: Date
    let snippetContext: SnippetContext?

    init(
        personalDictionary: [String: String] = [:],
        appName: String? = nil,
        currentDate: Date = Date(),
        snippetContext: SnippetContext? = nil
    ) {
        self.personalDictionary = personalDictionary
        self.appName = appName
        self.currentDate = currentDate
        self.snippetContext = snippetContext
    }
}
