import Cocoa

// MARK: - NSWorkspace-реализация WorkspaceProviding

final class NSWorkspaceProvider: WorkspaceProviding {

    func frontmostApp() -> (bundleId: String?, appName: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }
}

// MARK: - UserDefaults-реализация AppModeOverriding

final class UserDefaultsAppModeOverrides: AppModeOverriding {

    private static let key = "AppModeOverrides"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func modeOverride(for bundleId: String) -> String? {
        let dict = defaults.dictionary(forKey: Self.key) as? [String: String]
        return dict?[bundleId]
    }

    func setModeOverride(_ mode: String?, for bundleId: String) {
        var dict = (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
        dict[bundleId] = mode
        defaults.set(dict, forKey: Self.key)
    }

    func allOverrides() -> [String: String] {
        (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
    }
}
