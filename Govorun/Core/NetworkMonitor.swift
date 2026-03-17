import Combine
import Network

final class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected = false
    private let monitor = NWPathMonitor()

    /// Синхронная проверка через currentPath (не зависит от callback)
    var isCurrentlyConnected: Bool {
        monitor.currentPath.status == .satisfied
    }

    init() {
        // Синхронный snapshot до первого callback
        isConnected = monitor.currentPath.status == .satisfied

        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "govorun.NetworkMonitor"))
    }

    deinit { monitor.cancel() }
}
