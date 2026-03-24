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
        static let activationKey = "activationKey"
        static let terminalPeriodEnabled = "terminalPeriodEnabled"
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
        migrateRecordingMode()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.defaultTextMode: "universal",
            Keys.recordingMode: RecordingMode.default.rawValue,
            Keys.soundEnabled: true,
            Keys.saveAudioHistory: false,
            Keys.terminalPeriodEnabled: true,
        ])
    }

    /// Миграция: v0.1.8 хранил recordingMode как "hold", теперь enum "pushToTalk"
    private func migrateRecordingMode() {
        if defaults.string(forKey: Keys.recordingMode) == "hold" {
            defaults.set(RecordingMode.pushToTalk.rawValue, forKey: Keys.recordingMode)
        }
    }

    // MARK: - Properties

    var defaultTextMode: String {
        get { defaults.string(forKey: Keys.defaultTextMode) ?? "universal" }
        set {
            defaults.set(newValue, forKey: Keys.defaultTextMode)
            objectWillChange.send()
        }
    }

    var recordingMode: RecordingMode {
        get {
            guard let raw = defaults.string(forKey: Keys.recordingMode) else {
                return .default
            }
            guard let mode = RecordingMode(rawValue: raw) else {
                print("[Govorun] RecordingMode: неизвестное значение '\(raw)', используем pushToTalk")
                return .default
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.recordingMode)
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

    var terminalPeriodEnabled: Bool {
        get { defaults.bool(forKey: Keys.terminalPeriodEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.terminalPeriodEnabled)
            objectWillChange.send()
        }
    }

    var activationKey: ActivationKey {
        get {
            guard let jsonString = defaults.string(forKey: Keys.activationKey),
                  let data = jsonString.data(using: .utf8),
                  let key = try? JSONDecoder().decode(ActivationKey.self, from: data)
            else {
                return .default
            }
            return key
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let jsonString = String(data: data, encoding: .utf8)
            {
                defaults.set(jsonString, forKey: Keys.activationKey)
                objectWillChange.send()
            } else {
                print("[Govorun] ActivationKey: не удалось сохранить \(newValue)")
            }
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.defaultTextMode)
        defaults.removeObject(forKey: Keys.recordingMode)
        defaults.removeObject(forKey: Keys.soundEnabled)
        defaults.removeObject(forKey: Keys.saveAudioHistory)
        defaults.removeObject(forKey: Keys.activationKey)
        defaults.removeObject(forKey: Keys.terminalPeriodEnabled)
        // launchAtLogin управляется через SMAppService, не UserDefaults
        registerDefaults()
        objectWillChange.send()
    }
}
