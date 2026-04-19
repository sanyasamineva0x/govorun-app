import Foundation

// MARK: - Хинты для нормализации

struct NormalizationHints: Equatable {
    let personalDictionary: [String: String]
    let appName: String?
    let currentDate: Date
    let snippetContext: SnippetContext?
    let snippetDictionary: [String: String]

    init(
        personalDictionary: [String: String] = [:],
        appName: String? = nil,
        currentDate: Date = Date(),
        snippetContext: SnippetContext? = nil,
        snippetDictionary: [String: String] = [:]
    ) {
        self.personalDictionary = personalDictionary
        self.appName = appName
        self.currentDate = currentDate
        self.snippetContext = snippetContext
        self.snippetDictionary = snippetDictionary
    }
}
