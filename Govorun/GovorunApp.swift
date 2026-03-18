import SwiftUI
import SwiftData

enum AppModelContainer {
    @MainActor
    static let shared: ModelContainer = {
        do {
            // Два store в одном контейнере: main (user data) + analytics (отдельный SQLite).
            // Один контейнер = нет конфликта в глобальном реестре SwiftData.
            let mainConfig = ModelConfiguration(
                "main",
                schema: Schema([DictionaryEntry.self, Snippet.self, HistoryItem.self])
            )

            let analyticsURL = analyticsStoreURL
            let analyticsConfig = ModelConfiguration(
                "analytics",
                schema: Schema([AnalyticsEvent.self]),
                url: analyticsURL
            )

            return try ModelContainer(
                for: DictionaryEntry.self, Snippet.self, HistoryItem.self, AnalyticsEvent.self,
                configurations: mainConfig, analyticsConfig
            )
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не удалось запустить Говоруна"
            alert.informativeText = "Ошибка базы данных: \(error.localizedDescription)\n\nПопробуйте удалить ~/Library/Application Support/Govorun и перезапустить."
            alert.alertStyle = .critical
            alert.runModal()
            fatalError("ModelContainer: \(error)")
        }
    }()

    private static var analyticsStoreURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.govorun")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("analytics.store")
    }
}

@main
struct GovorunApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app: настройки открываются через SettingsWindowController.
        // Settings scene с EmptyView не показывает окно, но удовлетворяет SwiftUI.
        // LSUIElement=true в Info.plist скрывает приложение из Dock.
        Settings {
            EmptyView()
                .frame(width: 0, height: 0)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        let soundPlayer = SystemSoundPlayer(enabled: settings.soundEnabled)
        let state = AppState(soundPlayer: soundPlayer)
        let settingsWindowController = SettingsWindowController(
            modelContainer: AppModelContainer.shared,
            appState: state
        )
        self.appState = state
        self.settingsWindowController = settingsWindowController
        self.statusBarController = StatusBarController(
            appState: state,
            settingsWindowController: settingsWindowController
        )

        if settings.onboardingCompleted {
            state.start()
        } else {
            showOnboarding(thenStart: state)
        }
    }

    private func showOnboarding(thenStart state: AppState) {
        let controller = OnboardingWindowController(appState: state) { [weak self] in
            self?.onboardingWindowController = nil
            state.start()
        }
        self.onboardingWindowController = controller
        controller.present()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stop()
    }
}
