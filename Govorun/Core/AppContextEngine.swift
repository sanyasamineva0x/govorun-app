import Foundation

// MARK: - AppContext

struct AppContext: Sendable, Equatable {
    let bundleId: String
    let appName: String
    let textMode: TextMode
}

// MARK: - Протокол: определение frontmost app

protocol WorkspaceProviding: AnyObject {
    func frontmostApp() -> (bundleId: String?, appName: String?)
}

// MARK: - Протокол: пользовательские переопределения режимов

protocol AppModeOverriding: AnyObject {
    func modeOverride(for bundleId: String) -> String?
    func setModeOverride(_ mode: String?, for bundleId: String)
    func allOverrides() -> [String: String]
}

// MARK: - Маппинг bundleId → TextMode

private let defaultAppModes: [String: TextMode] = [
    // Мессенджеры → .chat
    "ru.keepcoder.Telegram": .chat,
    "com.tinyspeck.slackmacgap": .chat,
    "net.whatsapp.WhatsApp": .chat,
    "com.apple.MobileSMS": .chat,

    // Почта → .email
    "com.apple.mail": .email,
    "com.readdle.smartemail.macos": .email,

    // Браузеры → .universal
    "com.google.Chrome": .universal,
    "com.apple.Safari": .universal,
    "org.mozilla.firefox": .universal,
    "company.thebrowser.Browser": .universal,

    // Документы → .document
    "com.apple.iWork.Pages": .document,
    "com.microsoft.Word": .document,
    "notion.id": .document,

    // Заметки → .note
    "com.apple.Notes": .note,
    "md.obsidian": .note,

    // Код → .code
    "com.microsoft.VSCode": .code,
    "com.apple.dt.Xcode": .code,
    "com.todesktop.230313mzl4w4u92": .code,
]

// MARK: - AppContextEngine

final class AppContextEngine {

    private let workspace: WorkspaceProviding
    private let modeOverrides: AppModeOverriding

    init(workspace: WorkspaceProviding, modeOverrides: AppModeOverriding) {
        self.workspace = workspace
        self.modeOverrides = modeOverrides
    }

    func detectCurrentApp() -> AppContext {
        let (rawBundleId, rawAppName) = workspace.frontmostApp()
        let bundleId = rawBundleId ?? ""
        let appName = rawAppName ?? ""
        let mode = resolveTextMode(for: bundleId)

        return AppContext(
            bundleId: bundleId,
            appName: appName,
            textMode: mode
        )
    }

    func textMode(for bundleId: String) -> TextMode {
        resolveTextMode(for: bundleId)
    }

    // MARK: - Private

    private func resolveTextMode(for bundleId: String) -> TextMode {
        // Пользовательский override приоритетнее
        if let overrideRaw = modeOverrides.modeOverride(for: bundleId),
           let mode = TextMode(rawValue: overrideRaw) {
            return mode
        }

        return defaultAppModes[bundleId] ?? .universal
    }
}
