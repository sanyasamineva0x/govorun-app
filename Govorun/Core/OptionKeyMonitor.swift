import Foundation

// MARK: - Протокол для тестируемости

protocol EventMonitoring: AnyObject {
    func addGlobalFlagsChanged(_ handler: @escaping (Bool) -> Void) -> Any?
    func addGlobalKeyDown(_ handler: @escaping () -> Void) -> Any?
    func addLocalFlagsChanged(_ handler: @escaping (Bool) -> Void) -> Any?
    func addLocalKeyDown(_ handler: @escaping () -> Void) -> Any?
    func removeMonitor(_ monitor: Any)
}

// MARK: - OptionKeyMonitor

final class OptionKeyMonitor {

    var onActivated: (() -> Void)?
    var onDeactivated: (() -> Void)?
    var onCancelled: (() -> Void)?

    static let activationDelay: TimeInterval = 0.2 // 200ms

    private let eventMonitor: EventMonitoring
    private var monitors: [Any] = []
    private var activationTimer: DispatchWorkItem?
    private var isOptionDown = false
    private var isActivated = false

    init(eventMonitor: EventMonitoring) {
        self.eventMonitor = eventMonitor
    }

    func startMonitoring() {
        // Global monitors (когда Говорун НЕ в фокусе)
        if let m = eventMonitor.addGlobalFlagsChanged({ [weak self] optionDown in
            self?.handleFlagsChanged(optionDown: optionDown)
        }) { monitors.append(m) }

        if let m = eventMonitor.addGlobalKeyDown({ [weak self] in
            self?.handleKeyDown()
        }) { monitors.append(m) }

        // Local monitors (когда Говорун В фокусе)
        if let m = eventMonitor.addLocalFlagsChanged({ [weak self] optionDown in
            self?.handleFlagsChanged(optionDown: optionDown)
        }) { monitors.append(m) }

        if let m = eventMonitor.addLocalKeyDown({ [weak self] in
            self?.handleKeyDown()
        }) { monitors.append(m) }
    }

    func stopMonitoring() {
        for monitor in monitors {
            eventMonitor.removeMonitor(monitor)
        }
        monitors.removeAll()
        cancelActivation()
        isOptionDown = false
        isActivated = false
    }

    // MARK: - Private

    private func handleFlagsChanged(optionDown: Bool) {
        if optionDown && !isOptionDown {
            // ⌥ нажат
            isOptionDown = true
            scheduleActivation()
        } else if !optionDown && isOptionDown {
            // ⌥ отпущен
            isOptionDown = false
            cancelActivation()

            if isActivated {
                isActivated = false
                onDeactivated?()
            }
        }
    }

    private func handleKeyDown() {
        guard isOptionDown, !isActivated else { return }
        // Нажата другая клавиша вместе с ⌥ → это shortcut, отменяем
        cancelActivation()
        onCancelled?()
    }

    private func scheduleActivation() {
        cancelActivation()

        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.isOptionDown else { return }
            self.isActivated = true
            self.onActivated?()
        }
        activationTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationDelay, execute: timer)
    }

    private func cancelActivation() {
        activationTimer?.cancel()
        activationTimer = nil
    }
}
