import Combine
import Foundation
import Sparkle

// MARK: - Протокол для тестируемости

protocol UpdateChecking: AnyObject {
    var updateAvailable: Bool { get }
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

// MARK: - Делегат-прокси (создаётся до SPUUpdater, форвардит в UpdaterService)

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    weak var service: UpdaterService?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        service?.handleUpdateFound(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        service?.handleNoUpdate(error)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        service?.handleAbort(error)
    }
}

// MARK: - UpdaterService

@MainActor
final class UpdaterService: NSObject, ObservableObject, UpdateChecking {
    private let updater: SPUUpdater
    private let delegateProxy: UpdaterDelegate
    @Published private(set) var updateAvailable = false
    @Published private(set) var canCheckForUpdates = false

    override init() {
        let proxy = UpdaterDelegate()
        delegateProxy = proxy

        let userDriver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: userDriver,
            delegate: proxy
        )

        super.init()
        proxy.service = self

        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        do {
            try updater.start()
            print("[Govorun] Sparkle запущен")
        } catch {
            print("[Govorun] Sparkle не запустился: \(error)")
        }
    }

    func checkForUpdates() {
        print("[Govorun] Sparkle: проверка обновлений")
        updater.checkForUpdates()
    }

    // MARK: - Обработчики от прокси-делегата

    fileprivate func handleUpdateFound(_ version: String) {
        print("[Govorun] Sparkle: найдено обновление \(version)")
        Task { @MainActor [weak self] in
            self?.updateAvailable = true
        }
    }

    fileprivate func handleNoUpdate(_ error: any Error) {
        print("[Govorun] Sparkle: обновлений нет — \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.updateAvailable = false
        }
    }

    fileprivate func handleAbort(_ error: any Error) {
        print("[Govorun] Sparkle: ошибка — \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.updateAvailable = false
        }
    }
}
