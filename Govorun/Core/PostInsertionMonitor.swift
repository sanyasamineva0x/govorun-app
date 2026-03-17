import Foundation

// MARK: - Протокол post-insertion мониторинга

@MainActor
protocol PostInsertionMonitoring: AnyObject {
    func startMonitoring(
        sessionId: UUID,
        insertedText: String,
        targetBundleId: String?,
        analytics: AnalyticsEmitting
    )
    func stopMonitoring()
}

// MARK: - Зависимости (для тестируемости)

/// Абстракция над NSWorkspace для отслеживания активного приложения
protocol FrontmostAppProviding: AnyObject {
    func frontmostBundleId() -> String?
    func addActivationObserver(_ handler: @escaping @Sendable () -> Void) -> NSObjectProtocol
    func removeObserver(_ observer: NSObjectProtocol)
}

/// Абстракция над AX для чтения текста из focused element
protocol FocusedTextReading: AnyObject {
    func readFocusedText() -> String?
}

// MARK: - PostInsertionMonitor

/// Мониторит правки пользователя в течение 60 секунд после вставки.
///
/// Zero-edit rate — approximation. Пользователь мог не заметить ошибку.
/// Метрика намеренно завышена для MVP. Коррекция через human evaluation (§10 метрик-спеки).
@MainActor
final class PostInsertionMonitor: PostInsertionMonitoring {

    static let monitoringWindowSeconds: TimeInterval = 60
    static let pollingIntervalSeconds: TimeInterval = 2

    private let focusedTextReader: FocusedTextReading
    private let frontmostAppProvider: FrontmostAppProviding
    private let eventMonitorProvider: GlobalKeyMonitorProviding

    private var pollingTimer: Timer?
    private var windowTimer: Timer?
    private var keyMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?

    private var currentSessionId: UUID?
    private var lastKnownText: String?
    private var targetBundleId: String?
    private var analytics: AnalyticsEmitting?
    private var editAlreadyDetected = false

    init(
        focusedTextReader: FocusedTextReading,
        frontmostAppProvider: FrontmostAppProviding,
        eventMonitorProvider: GlobalKeyMonitorProviding = SystemGlobalKeyMonitorProvider()
    ) {
        self.focusedTextReader = focusedTextReader
        self.frontmostAppProvider = frontmostAppProvider
        self.eventMonitorProvider = eventMonitorProvider
    }

    func startMonitoring(
        sessionId: UUID,
        insertedText: String,
        targetBundleId: String?,
        analytics: AnalyticsEmitting
    ) {
        stopMonitoring()

        self.currentSessionId = sessionId
        // Читаем полное содержимое поля как baseline — не только вставленный фрагмент.
        // Иначе в непустых полях (чаты, письма) первый poll сразу даёт false positive.
        self.lastKnownText = focusedTextReader.readFocusedText() ?? insertedText
        self.targetBundleId = targetBundleId
        self.analytics = analytics
        self.editAlreadyDetected = false

        startPolling()
        startCmdZMonitor()
        startAppActivationObserver()
        startWindowTimer()
    }

    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        windowTimer?.invalidate()
        windowTimer = nil

        if let keyMonitor {
            eventMonitorProvider.removeMonitor(keyMonitor)
        }
        keyMonitor = nil

        if let appActivationObserver {
            frontmostAppProvider.removeObserver(appActivationObserver)
        }
        appActivationObserver = nil

        currentSessionId = nil
        lastKnownText = nil
        targetBundleId = nil
        analytics = nil
    }

    // MARK: - Private: Polling AX value

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: Self.pollingIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForEdit()
            }
        }
    }

    private func checkForEdit() {
        guard !editAlreadyDetected,
              let sessionId = currentSessionId,
              let analytics = analytics else { return }

        guard let currentText = focusedTextReader.readFocusedText() else { return }

        if let lastKnown = lastKnownText, currentText != lastKnown {
            editAlreadyDetected = true
            Task {
                await analytics.emit(.manualEditDetected, sessionId: sessionId, metadata: [:])
            }
        }

        lastKnownText = currentText
    }

    // MARK: - Private: Cmd+Z detection

    private func startCmdZMonitor() {
        keyMonitor = eventMonitorProvider.addGlobalKeyDownMonitor { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyDown(event)
            }
        }
    }

    private func handleKeyDown(_ event: GlobalKeyEvent) {
        guard event.keyCode == 6, // Z
              event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.shift) else { return }

        guard let sessionId = currentSessionId,
              let analytics = analytics else { return }

        // Только если Cmd+Z нажат в целевом приложении
        if let target = targetBundleId,
           let frontmost = frontmostAppProvider.frontmostBundleId(),
           frontmost != target {
            return
        }

        let capturedAnalytics = analytics
        stopMonitoring()
        Task {
            await capturedAnalytics.emit(.undoDetected, sessionId: sessionId, metadata: [:])
        }
    }

    // MARK: - Private: App switch detection

    private func startAppActivationObserver() {
        appActivationObserver = frontmostAppProvider.addActivationObserver { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let target = self.targetBundleId else { return }
                let frontmost = self.frontmostAppProvider.frontmostBundleId()
                if frontmost != target {
                    self.stopMonitoring()
                }
            }
        }
    }

    // MARK: - Private: 60s window timer

    private func startWindowTimer() {
        windowTimer = Timer.scheduledTimer(
            withTimeInterval: Self.monitoringWindowSeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopMonitoring()
            }
        }
    }
}

// MARK: - Global key event abstraction (для тестируемости)

struct GlobalKeyEvent {
    let keyCode: UInt16
    let modifierFlags: ModifierFlags

    struct ModifierFlags: OptionSet {
        let rawValue: UInt
        static let command = ModifierFlags(rawValue: 1 << 0)
        static let shift = ModifierFlags(rawValue: 1 << 1)

        func contains(_ member: ModifierFlags) -> Bool {
            rawValue & member.rawValue == member.rawValue
        }
    }
}

/// Абстракция над NSEvent.addGlobalMonitorForEvents
protocol GlobalKeyMonitorProviding {
    func addGlobalKeyDownMonitor(handler: @escaping (GlobalKeyEvent) -> Void) -> Any?
    func removeMonitor(_ monitor: Any)
}
