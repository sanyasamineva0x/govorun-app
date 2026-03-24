import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var appState: AppState?
    private let settingsWindowController: SettingsWindowController
    private var cancellables = Set<AnyCancellable>()
    private var pulseTimer: Timer?
    private var isPulseOn = true

    // Элементы меню для динамического обновления
    private var statusMenuItem: NSMenuItem?
    private var workerActionMenuItem: NSMenuItem?
    private var accessibilityMenuItem: NSMenuItem?
    private var lastResultMenuItem: NSMenuItem?
    private var copyMenuItem: NSMenuItem?

    init(appState: AppState, settingsWindowController: SettingsWindowController) {
        self.appState = appState
        self.settingsWindowController = settingsWindowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupButton()
        setupMenu()
        observeState()
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        setMenuBarIcon("mic.fill", on: button)
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let titleItem = NSMenuItem(title: "Говорун", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // Статус
        let status = NSMenuItem(title: "Готов", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        // Отменить / Повторить загрузку (динамический, скрыт когда не нужен)
        let workerAction = NSMenuItem(title: "Отменить загрузку", action: #selector(handleWorkerAction), keyEquivalent: "")
        workerAction.target = self
        workerAction.isHidden = true
        menu.addItem(workerAction)
        workerActionMenuItem = workerAction

        // Accessibility статус (показывается когда не включён)
        let axItem = NSMenuItem(title: "Включить Accessibility", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        axItem.target = self
        axItem.isHidden = true
        menu.addItem(axItem)
        accessibilityMenuItem = axItem

        menu.addItem(NSMenuItem.separator())

        // Последний результат
        let lastResult = NSMenuItem(title: "Нет результатов", action: nil, keyEquivalent: "")
        lastResult.isEnabled = false
        menu.addItem(lastResult)
        lastResultMenuItem = lastResult

        // Кнопка копирования
        let copy = NSMenuItem(title: "Копировать последний результат", action: #selector(copyLastResult), keyEquivalent: "c")
        copy.target = self
        copy.isHidden = true
        menu.addItem(copy)
        copyMenuItem = copy

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Настройки", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - State observation

    private func observeState() {
        guard let appState else { return }

        appState.$lastResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.updateLastResult(result)
            }
            .store(in: &cancellables)

        // Worker state → пульсация иконки при загрузке модели
        appState.$workerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleWorkerStateChange(state)
            }
            .store(in: &cancellables)

        // Session state → live menubar icon (recording, processing, inserting, error)
        appState.$sessionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusDisplay()
            }
            .store(in: &cancellables)
    }

    private func updateStatusDisplay() {
        guard let appState else { return }

        // Worker state приоритетнее пока модель не готова
        if appState.workerState != .ready {
            let (title, icon) = workerStatusInfo(for: appState.workerState)
            statusMenuItem?.title = title
            guard let button = statusItem.button else { return }
            setMenuBarIcon(icon, on: button)
            return
        }

        let state = appState.sessionState
        if case .idle = state {
            let key = appState.settings.activationKey.displayName
            statusMenuItem?.title = appState.effectiveRecordingMode.hint(key: key)
            guard let button = statusItem.button else { return }
            setMenuBarIcon("mic.fill", on: button)
            return
        }

        let (title, icon) = statusInfo(for: state)
        statusMenuItem?.title = title

        guard let button = statusItem.button else { return }
        setMenuBarIcon(icon, on: button)
    }

    private func setMenuBarIcon(_ symbolName: String, on button: NSStatusBarButton) {
        // Для idle состояния — иконка приложения, для остальных — SF Symbols
        if symbolName == "mic.fill" {
            setAppIcon(on: button)
        } else {
            let image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "Говорун"
            )
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            button.image = image
        }
    }

    private func setAppIcon(on button: NSStatusBarButton) {
        guard let appIcon = NSImage(named: "AppIcon") else {
            // Fallback на mic.fill если иконка не найдена
            let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Говорун")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            button.image = image
            return
        }
        appIcon.size = NSSize(width: 18, height: 18)
        button.image = appIcon
    }

    private func statusInfo(for state: SessionState) -> (String, String) {
        switch state {
        case .idle:
            return ("Готов", "mic.fill")
        case .recording:
            return ("Записываю…", "mic.circle.fill")
        case .processing:
            return ("Обрабатываю…", "ellipsis.circle")
        case .inserting:
            return ("Вставляю…", "doc.on.clipboard")
        case .error(let msg):
            return ("Ошибка: \(msg)", "exclamationmark.triangle.fill")
        }
    }

    private func updateLastResult(_ result: PipelineResult?) {
        guard let result else {
            lastResultMenuItem?.title = "Нет результатов"
            copyMenuItem?.isHidden = true
            return
        }

        let preview = result.normalizedText.prefix(50)
        let suffix = result.normalizedText.count > 50 ? "…" : ""
        lastResultMenuItem?.title = "Последний: \(preview)\(suffix)"
        copyMenuItem?.isHidden = false
    }

    // MARK: - Worker state

    private func workerStatusInfo(for state: WorkerState) -> (String, String) {
        switch state {
        case .notStarted:
            return ("Запускаюсь…", "circle.dotted")
        case .settingUp:
            return ("Готовлюсь…", "gearshape")
        case .downloadingModel(let progress):
            return ("Качаю модель… \(progress)%", "arrow.down.circle")
        case .loadingModel:
            return ("Загружаю модель…", "arrow.down.circle")
        case .ready:
            return ("Готов", "mic.fill")
        case .error(let msg):
            return ("Ошибка: \(msg)", "exclamationmark.triangle.fill")
        }
    }

    private func handleWorkerStateChange(_ state: WorkerState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .downloadingModel, .loadingModel, .settingUp:
            startPulseAnimation()
            workerActionMenuItem?.title = "Отменить загрузку"
            workerActionMenuItem?.action = #selector(handleWorkerAction)
            workerActionMenuItem?.isHidden = false
        case .ready:
            stopPulseAnimation()
            setMenuBarIcon("mic.fill", on: button)
            let key = appState?.settings.activationKey.displayName ?? "⌥"
            let mode = appState?.effectiveRecordingMode ?? .default
            statusMenuItem?.title = mode.hint(key: key)
            workerActionMenuItem?.isHidden = true
        case .error(let msg):
            stopPulseAnimation()
            setMenuBarIcon("exclamationmark.triangle.fill", on: button)
            statusMenuItem?.title = "Ошибка: \(msg)"
            // Показать "Повторить загрузку" после отмены или ошибки
            workerActionMenuItem?.title = "Повторить загрузку"
            workerActionMenuItem?.action = #selector(handleWorkerAction)
            workerActionMenuItem?.isHidden = false
        case .notStarted:
            stopPulseAnimation()
            setMenuBarIcon("mic.fill", on: button)
            statusMenuItem?.title = "Запускаюсь…"
            workerActionMenuItem?.isHidden = true
        }
    }

    // MARK: - Pulse animation

    private func startPulseAnimation() {
        stopPulseAnimation()
        isPulseOn = true
        updatePulseIcon()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPulseOn.toggle()
                self.updatePulseIcon()
            }
        }
    }

    private func stopPulseAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    private func updatePulseIcon() {
        guard let button = statusItem.button else { return }
        let icon = isPulseOn ? "arrow.down.circle.fill" : "arrow.down.circle"
        setMenuBarIcon(icon, on: button)
    }

    // MARK: - Actions

    @objc private func copyLastResult() {
        guard let text = appState?.lastResult?.normalizedText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func updateAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        accessibilityMenuItem?.isHidden = trusted
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func handleWorkerAction() {
        guard let appState else { return }
        switch appState.workerState {
        case .downloadingModel, .loadingModel, .settingUp:
            appState.cancelWorkerLoading()
        case .error:
            appState.retryWorkerLoading()
        default:
            break
        }
    }

    @objc private func openSettings() {
        settingsWindowController.present()
    }

    @objc private func quit() {
        appState?.stop()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            updateStatusDisplay()
            updateAccessibilityStatus()
        }
    }
}
