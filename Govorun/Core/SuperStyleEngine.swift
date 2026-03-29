import Foundation

// MARK: - Движок выбора стиля

enum SuperStyleEngine {
    private static let messengerBundleIds: Set<String> = [
        "ru.keepcoder.Telegram",
        "net.whatsapp.WhatsApp",
        "com.viber.osx",
        "com.vk.messenger",
        "com.apple.MobileSMS",
        "com.hnc.Discord",
    ]

    private static let mailBundleIds: Set<String> = [
        "com.apple.mail",
        "com.readdle.smartemail-macos",
        "com.microsoft.Outlook",
    ]

    static func resolve(
        bundleId: String,
        mode: SuperStyleMode,
        manualStyle: SuperTextStyle
    ) -> SuperTextStyle {
        switch mode {
        case .manual:
            return manualStyle
        case .auto:
            if messengerBundleIds.contains(bundleId) {
                return .relaxed
            }
            if mailBundleIds.contains(bundleId) {
                return .formal
            }
            return .normal
        }
    }
}
