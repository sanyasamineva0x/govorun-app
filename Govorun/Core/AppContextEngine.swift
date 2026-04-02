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
        return AppContext(
            bundleId: rawBundleId ?? "",
            appName: rawAppName ?? ""
        )
    }
}
