import Foundation

// MARK: - AppContext

struct AppContext: Equatable {
    let bundleId: String
    let appName: String
}

// MARK: - Протокол: определение frontmost app

protocol WorkspaceProviding: AnyObject {
    func frontmostApp() -> (bundleId: String?, appName: String?)
}

// MARK: - AppContextEngine

final class AppContextEngine {
    private let workspace: WorkspaceProviding

    init(workspace: WorkspaceProviding) {
        self.workspace = workspace
    }

    func detectCurrentApp() -> AppContext {
        let (rawBundleId, rawAppName) = workspace.frontmostApp()
        let bundleId = rawBundleId ?? ""
        let appName = rawAppName ?? ""

        return AppContext(
            bundleId: bundleId,
            appName: appName
        )
    }
}

// MARK: - NSWorkspace-реализация WorkspaceProviding

#if canImport(Cocoa)
import Cocoa

final class NSWorkspaceProvider: WorkspaceProviding {
    func frontmostApp() -> (bundleId: String?, appName: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }
}
#endif
