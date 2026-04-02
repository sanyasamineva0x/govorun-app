import Cocoa

final class NSWorkspaceProvider: WorkspaceProviding {
    func frontmostApp() -> (bundleId: String?, appName: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }
}
