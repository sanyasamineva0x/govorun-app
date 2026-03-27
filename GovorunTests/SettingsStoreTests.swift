@testable import Govorun
import XCTest

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        let suiteName = "com.govorun.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        if let suite = defaults.volatileDomainNames.first {
            defaults.removePersistentDomain(forName: suite)
        }
        defaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - 1. Дефолтные значения

    func test_default_values() {
        XCTAssertEqual(store.defaultTextMode, "universal")
        XCTAssertEqual(store.recordingMode, .pushToTalk)
        XCTAssertTrue(store.soundEnabled)
        XCTAssertFalse(store.saveAudioHistory, "По умолчанию аудио не сохраняется (privacy)")
        XCTAssertEqual(store.llmBaseURL, LocalLLMConfiguration.defaultBaseURLString)
        XCTAssertEqual(store.llmModel, LocalLLMConfiguration.defaultModel)
        XCTAssertEqual(store.llmRequestTimeout, LocalLLMConfiguration.defaultRequestTimeout)
        XCTAssertEqual(store.llmHealthcheckTimeout, LocalLLMConfiguration.defaultHealthcheckTimeout)
        // launchAtLogin: SMAppService, зависит от системного состояния
        XCTAssertFalse(store.onboardingCompleted)
    }

    // MARK: - 2. Сохранение и чтение

    func test_set_default_text_mode() {
        store.defaultTextMode = "chat"
        XCTAssertEqual(store.defaultTextMode, "chat")

        // Новый store с теми же defaults — значение сохранилось
        let store2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(store2.defaultTextMode, "chat")
    }

    func test_set_recording_mode() {
        store.recordingMode = .toggle
        XCTAssertEqual(store.recordingMode, .toggle)
    }

    func test_set_sound_enabled() {
        store.soundEnabled = false
        XCTAssertFalse(store.soundEnabled)
    }

    /// launchAtLogin управляется через SMAppService — не тестируем set
    /// (вызывает реальный системный register/unregister)
    func test_launch_at_login_reads_without_crash() {
        // Только проверяем что getter не крашится
        _ = store.launchAtLogin
    }

    // MARK: - 3. Валидация TextMode

    func test_valid_text_modes() {
        let validModes = ["chat", "email", "document", "note", "code", "universal"]
        for mode in validModes {
            store.defaultTextMode = mode
            XCTAssertEqual(store.defaultTextMode, mode)
        }
    }

    // MARK: - 4. Persistence между экземплярами

    func test_persistence_across_instances() {
        store.defaultTextMode = "email"
        store.recordingMode = .toggle
        store.soundEnabled = false

        let store2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(store2.defaultTextMode, "email")
        XCTAssertEqual(store2.recordingMode, .toggle)
        XCTAssertFalse(store2.soundEnabled)
        // launchAtLogin: SMAppService, не UserDefaults — не проверяем persistence
    }

    // MARK: - 5. Сброс к дефолтам

    func test_reset_to_defaults() {
        store.defaultTextMode = "code"
        store.recordingMode = .toggle
        store.soundEnabled = false

        store.resetToDefaults()

        XCTAssertEqual(store.defaultTextMode, "universal")
        XCTAssertEqual(store.recordingMode, .pushToTalk)
        XCTAssertTrue(store.soundEnabled)
        // launchAtLogin: SMAppService, resetToDefaults не влияет
    }

    // MARK: - 5a. Audio history default (privacy)

    func test_saveAudioHistory_default_false() {
        XCTAssertFalse(store.saveAudioHistory)
    }

    func test_saveAudioHistory_opt_in_works() {
        store.saveAudioHistory = true
        XCTAssertTrue(store.saveAudioHistory)
    }

    func test_saveAudioHistory_reset_to_defaults() {
        store.saveAudioHistory = true
        store.resetToDefaults()
        XCTAssertFalse(store.saveAudioHistory)
    }

    // MARK: - 6. Onboarding

    func test_onboarding_completed_default_false() {
        XCTAssertFalse(store.onboardingCompleted)
    }

    func test_onboarding_completed_persists() {
        store.onboardingCompleted = true
        XCTAssertTrue(store.onboardingCompleted)

        let store2 = SettingsStore(defaults: defaults)
        XCTAssertTrue(store2.onboardingCompleted)
    }

    func test_reset_does_not_clear_onboarding() {
        store.onboardingCompleted = true
        store.resetToDefaults()
        XCTAssertTrue(store.onboardingCompleted)
    }

    // MARK: - 7. ActivationKey

    func test_activationKey_default_is_option() {
        XCTAssertEqual(store.activationKey, .modifier(.maskAlternate))
    }

    func test_activationKey_set_and_get() {
        store.activationKey = .keyCode(96)
        XCTAssertEqual(store.activationKey, .keyCode(96))
    }

    func test_activationKey_persists() {
        store.activationKey = .combo(modifiers: .maskCommand, keyCode: 40)
        let store2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(store2.activationKey, .combo(modifiers: .maskCommand, keyCode: 40))
    }

    func test_activationKey_invalid_json_fallback() {
        defaults.set("not valid json", forKey: "activationKey")
        XCTAssertEqual(store.activationKey, .modifier(.maskAlternate))
    }

    func test_activationKey_reset_to_defaults() {
        store.activationKey = .keyCode(96)
        store.resetToDefaults()
        XCTAssertEqual(store.activationKey, .modifier(.maskAlternate))
    }

    // MARK: - 8. Миграция recordingMode "hold" → pushToTalk

    func test_recordingMode_migrates_hold_to_pushToTalk() {
        defaults.set("hold", forKey: "recordingMode")
        let migrated = SettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.recordingMode, .pushToTalk)
        XCTAssertEqual(defaults.string(forKey: "recordingMode"), "pushToTalk")
    }

    func test_recordingMode_invalid_fallback() {
        defaults.set("unknown_mode", forKey: "recordingMode")
        XCTAssertEqual(store.recordingMode, .pushToTalk)
    }

    // MARK: - 9. terminalPeriodEnabled

    func test_terminalPeriodEnabled_default_false() {
        XCTAssertFalse(store.terminalPeriodEnabled)
    }

    func test_terminalPeriodEnabled_set_and_get() {
        store.terminalPeriodEnabled = false
        XCTAssertFalse(store.terminalPeriodEnabled)
    }

    func test_terminalPeriodEnabled_persists() {
        store.terminalPeriodEnabled = false
        let store2 = SettingsStore(defaults: defaults)
        XCTAssertFalse(store2.terminalPeriodEnabled)
    }

    func test_terminalPeriodEnabled_reset_to_defaults() {
        store.terminalPeriodEnabled = false
        store.resetToDefaults()
        XCTAssertFalse(store.terminalPeriodEnabled)
    }

    // MARK: - 10. Local LLM runtime settings

    func test_localLLMSettings_persist() {
        store.llmBaseURL = "http://127.0.0.1:9090/v1/"
        store.llmModel = "gigachat-q4"
        store.llmRequestTimeout = 18
        store.llmHealthcheckTimeout = 2.5

        let store2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(store2.llmBaseURL, "http://127.0.0.1:9090/v1/")
        XCTAssertEqual(store2.llmModel, "gigachat-q4")
        XCTAssertEqual(store2.llmRequestTimeout, 18)
        XCTAssertEqual(store2.llmHealthcheckTimeout, 2.5)
    }

    func test_localLLMSettings_reset_to_defaults() {
        store.llmBaseURL = "http://127.0.0.1:9090/v1"
        store.llmModel = "custom-model"
        store.llmRequestTimeout = 20
        store.llmHealthcheckTimeout = 3

        store.resetToDefaults()

        XCTAssertEqual(store.llmBaseURL, LocalLLMConfiguration.defaultBaseURLString)
        XCTAssertEqual(store.llmModel, LocalLLMConfiguration.defaultModel)
        XCTAssertEqual(store.llmRequestTimeout, LocalLLMConfiguration.defaultRequestTimeout)
        XCTAssertEqual(store.llmHealthcheckTimeout, LocalLLMConfiguration.defaultHealthcheckTimeout)
    }

    func test_localLLMSettings_invalidTimeoutsFallbackToDefaults() {
        defaults.set(0, forKey: "llmRequestTimeout")
        defaults.set(-1, forKey: "llmHealthcheckTimeout")

        XCTAssertEqual(store.llmRequestTimeout, LocalLLMConfiguration.defaultRequestTimeout)
        XCTAssertEqual(store.llmHealthcheckTimeout, LocalLLMConfiguration.defaultHealthcheckTimeout)
    }
}
