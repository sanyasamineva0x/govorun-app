import Foundation
import ServiceManagement

// MARK: - SettingsStore

final class SettingsStore: ObservableObject {

    private let defaults: UserDefaults

    // MARK: - Keys

    private enum Keys {
        static let defaultTextMode = "defaultTextMode"
        static let recordingMode = "recordingMode"
        static let soundEnabled = "soundEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let saveAudioHistory = "saveAudioHistory"
        static let onboardingCompleted = "onboardingCompleted"
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.defaultTextMode: "universal",
            Keys.recordingMode: "hold",
            Keys.soundEnabled: true,
            Keys.saveAudioHistory: true,
        ])
    }

    // MARK: - Properties

    var defaultTextMode: String {
        get { defaults.string(forKey: Keys.defaultTextMode) ?? "universal" }
        set {
            defaults.set(newValue, forKey: Keys.defaultTextMode)
            objectWillChange.send()
        }
    }

    var recordingMode: String {
        get { defaults.string(forKey: Keys.recordingMode) ?? "hold" }
        set {
            defaults.set(newValue, forKey: Keys.recordingMode)
            objectWillChange.send()
        }
    }

    var soundEnabled: Bool {
        get { defaults.bool(forKey: Keys.soundEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.soundEnabled)
            objectWillChange.send()
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[Govorun] Launch at login: \(error)")
            }
            objectWillChange.send()
        }
    }

    var saveAudioHistory: Bool {
        get { defaults.bool(forKey: Keys.saveAudioHistory) }
        set {
            defaults.set(newValue, forKey: Keys.saveAudioHistory)
            objectWillChange.send()
        }
    }

    var onboardingCompleted: Bool {
        get { defaults.bool(forKey: Keys.onboardingCompleted) }
        set {
            defaults.set(newValue, forKey: Keys.onboardingCompleted)
            objectWillChange.send()
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.defaultTextMode)
        defaults.removeObject(forKey: Keys.recordingMode)
        defaults.removeObject(forKey: Keys.soundEnabled)
        defaults.removeObject(forKey: Keys.saveAudioHistory)
        // launchAtLogin управляется через SMAppService, не UserDefaults
        registerDefaults()
        objectWillChange.send()
    }
}
