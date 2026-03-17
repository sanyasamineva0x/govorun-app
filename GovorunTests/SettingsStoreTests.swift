import XCTest
@testable import Govorun

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
        XCTAssertEqual(store.recordingMode, "hold")
        XCTAssertTrue(store.soundEnabled)
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
        store.recordingMode = "toggle"
        XCTAssertEqual(store.recordingMode, "toggle")
    }

    func test_set_sound_enabled() {
        store.soundEnabled = false
        XCTAssertFalse(store.soundEnabled)
    }

    // launchAtLogin управляется через SMAppService — не тестируем set
    // (вызывает реальный системный register/unregister)
    func test_launch_at_login_reads_without_crash() {
        // Только проверяем что getter не крашится
        let _ = store.launchAtLogin
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
        store.recordingMode = "toggle"
        store.soundEnabled = false

        let store2 = SettingsStore(defaults: defaults)
        XCTAssertEqual(store2.defaultTextMode, "email")
        XCTAssertEqual(store2.recordingMode, "toggle")
        XCTAssertFalse(store2.soundEnabled)
        // launchAtLogin: SMAppService, не UserDefaults — не проверяем persistence
    }

    // MARK: - 5. Сброс к дефолтам

    func test_reset_to_defaults() {
        store.defaultTextMode = "code"
        store.recordingMode = "toggle"
        store.soundEnabled = false

        store.resetToDefaults()

        XCTAssertEqual(store.defaultTextMode, "universal")
        XCTAssertEqual(store.recordingMode, "hold")
        XCTAssertTrue(store.soundEnabled)
        // launchAtLogin: SMAppService, resetToDefaults не влияет
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
}
