@testable import Govorun
import XCTest

final class SuperStyleEngineTests: XCTestCase {
    // MARK: - Авто: мессенджеры -> relaxed

    func test_auto_mode_returns_relaxed_for_telegram() {
        let style = SuperStyleEngine.resolve(
            bundleId: "ru.keepcoder.Telegram",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .relaxed)
    }

    func test_auto_mode_returns_relaxed_for_whatsapp() {
        let style = SuperStyleEngine.resolve(
            bundleId: "net.whatsapp.WhatsApp",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .relaxed)
    }

    func test_auto_mode_returns_relaxed_for_viber() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.viber.osx",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .relaxed)
    }

    func test_auto_mode_returns_relaxed_for_vk_messenger() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.vk.messenger",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .relaxed)
    }

    func test_auto_mode_returns_relaxed_for_imessage() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.apple.MobileSMS",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .relaxed)
    }

    func test_auto_mode_returns_relaxed_for_discord() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.hnc.Discord",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .relaxed)
    }

    // MARK: - Авто: почта -> formal

    func test_auto_mode_returns_formal_for_apple_mail() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.apple.mail",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .formal)
    }

    func test_auto_mode_returns_formal_for_readdle_spark() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.readdle.smartemail-macos",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .formal)
    }

    func test_auto_mode_returns_formal_for_outlook() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.microsoft.Outlook",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .formal)
    }

    // MARK: - Авто: неизвестные -> normal

    func test_auto_mode_returns_normal_for_unknown_bundle() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.unknown.app",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .normal)
    }

    func test_auto_mode_returns_normal_for_empty_bundleId() {
        let style = SuperStyleEngine.resolve(
            bundleId: "",
            mode: .auto,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .normal)
    }

    // MARK: - Ручной: игнорирует bundleId

    func test_manual_mode_returns_formal_for_messenger_bundleId() {
        let style = SuperStyleEngine.resolve(
            bundleId: "ru.keepcoder.Telegram",
            mode: .manual,
            manualStyle: .formal
        )
        XCTAssertEqual(style, .formal)
    }

    func test_manual_mode_returns_relaxed_for_mail_bundleId() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.apple.mail",
            mode: .manual,
            manualStyle: .relaxed
        )
        XCTAssertEqual(style, .relaxed)
    }

    func test_manual_mode_returns_normal_for_unknown_bundleId() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.unknown.app",
            mode: .manual,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .normal)
    }

    func test_manual_mode_returns_relaxed_when_selected() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.some.app",
            mode: .manual,
            manualStyle: .relaxed
        )
        XCTAssertEqual(style, .relaxed)
    }

    func test_manual_mode_returns_normal_when_selected() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.some.app",
            mode: .manual,
            manualStyle: .normal
        )
        XCTAssertEqual(style, .normal)
    }

    func test_manual_mode_returns_formal_when_selected() {
        let style = SuperStyleEngine.resolve(
            bundleId: "com.some.app",
            mode: .manual,
            manualStyle: .formal
        )
        XCTAssertEqual(style, .formal)
    }
}
