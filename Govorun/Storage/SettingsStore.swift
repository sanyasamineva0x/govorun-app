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
        static let llmBaseURL = "llmBaseURL"
        static let llmModel = "llmModel"
        static let llmRequestTimeout = "llmRequestTimeout"
        static let llmHealthcheckTimeout = "llmHealthcheckTimeout"
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
            Keys.terminalPeriodEnabled: false,
            Keys.llmBaseURL: LocalLLMConfiguration.defaultBaseURLString,
            Keys.llmModel: LocalLLMConfiguration.defaultModel,
            Keys.llmRequestTimeout: LocalLLMConfiguration.defaultRequestTimeout,
            Keys.llmHealthcheckTimeout: LocalLLMConfiguration.defaultHealthcheckTimeout,
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

    var llmBaseURL: String {
        get {
            let stored = defaults.string(forKey: Keys.llmBaseURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty {
                return stored
            }
            return LocalLLMConfiguration.defaultBaseURLString
        }
        set {
            defaults.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.llmBaseURL
            )
            objectWillChange.send()
        }
    }

    var llmModel: String {
        get {
            let stored = defaults.string(forKey: Keys.llmModel)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty {
                return stored
            }
            return LocalLLMConfiguration.defaultModel
        }
        set {
            defaults.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.llmModel
            )
            objectWillChange.send()
        }
    }

    var llmRequestTimeout: TimeInterval {
        get {
            let value = defaults.double(forKey: Keys.llmRequestTimeout)
            return value > 0 ? value : LocalLLMConfiguration.defaultRequestTimeout
        }
        set {
            defaults.set(max(0.1, newValue), forKey: Keys.llmRequestTimeout)
            objectWillChange.send()
        }
    }

    var llmHealthcheckTimeout: TimeInterval {
        get {
            let value = defaults.double(forKey: Keys.llmHealthcheckTimeout)
            return value > 0 ? value : LocalLLMConfiguration.defaultHealthcheckTimeout
        }
        set {
            defaults.set(max(0.1, newValue), forKey: Keys.llmHealthcheckTimeout)
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
        defaults.removeObject(forKey: Keys.llmBaseURL)
        defaults.removeObject(forKey: Keys.llmModel)
        defaults.removeObject(forKey: Keys.llmRequestTimeout)
        defaults.removeObject(forKey: Keys.llmHealthcheckTimeout)
        // launchAtLogin управляется через SMAppService, не UserDefaults
        registerDefaults()
        objectWillChange.send()
    }
}
