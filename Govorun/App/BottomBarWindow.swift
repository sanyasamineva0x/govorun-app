import Cocoa
import SwiftUI

// MARK: - Состояние pill-панели

enum BottomBarState: Equatable {
    case hidden
    case recording(audioLevel: Float)
    case processing
    case modelLoading
    case modelDownloading(progress: Int)
    case accessibilityHint
    case error(String)

    var isVisible: Bool {
        if case .hidden = self { return false }
        return true
    }
}

// MARK: - Бренд-цвета

@MainActor
enum BrandColors {
    /// Cotton Candy #B36A5E — recording waveform
    static let cottonCandy = NSColor(red: 179/255, green: 106/255, blue: 94/255, alpha: 1)
    /// Sky Aqua #0acdff — processing индикатор
    static let skyAqua = NSColor(red: 10/255, green: 205/255, blue: 255/255, alpha: 1)
    /// Ocean Mist #60ab9a — success
    static let oceanMist = NSColor(red: 96/255, green: 171/255, blue: 154/255, alpha: 1)
    /// Petal Frost #fbdce2 — мягкий фон
    static let petalFrost = NSColor(red: 251/255, green: 220/255, blue: 226/255, alpha: 1)
    /// Alabaster Grey #dedee0 — нейтральный фон
    static let alabasterGrey = NSColor(red: 222/255, green: 222/255, blue: 224/255, alpha: 1)
}

// MARK: - Размеры pill

enum BottomBarMetrics {
    static let pillWidth: CGFloat = 260
    static let pillHeight: CGFloat = 44
    static let bottomOffset: CGFloat = 12
    static let showDuration: TimeInterval = 0.18
    static let dismissDuration: TimeInterval = 0.12
    static let errorAutoDismissDelay: TimeInterval = 3.0
    static let modelLoadingAutoDismissDelay: TimeInterval = 3.0
    static let barCount: Int = 12
    static let barWidth: CGFloat = 2
    static let barSpacing: CGFloat = 2.5
    static let maxBarHeight: CGFloat = 18
}

// MARK: - BottomBarController

@MainActor
final class BottomBarController: ObservableObject {

    @Published private(set) var state: BottomBarState = .hidden

    private var panel: BottomBarWindow?
    private var autoDismissTimer: DispatchWorkItem?

    // MARK: - Public API

    func show() {
        state = .recording(audioLevel: 0)
        ensurePanel()
        showPanel()
    }

    func showRecording(audioLevel: Float) {
        state = .recording(audioLevel: audioLevel)
    }

    func showProcessing() {
        state = .processing
    }

    func showModelLoading() {
        state = .modelLoading
        ensurePanel()
        showPanel()
        scheduleAutoDismiss(after: BottomBarMetrics.modelLoadingAutoDismissDelay)
    }

    func showModelDownloading(progress: Int) {
        state = .modelDownloading(progress: progress)
        ensurePanel()
        showPanel()
        scheduleAutoDismiss(after: 5.0)
    }

    func showAccessibilityHint() {
        state = .accessibilityHint
        ensurePanel()
        showPanel()
        scheduleAutoDismiss(after: 4.0)
    }

    func showError(_ message: String) {
        state = .error(message)
        ensurePanel()
        showPanel()
        scheduleAutoDismiss(after: BottomBarMetrics.errorAutoDismissDelay)
    }

    func dismiss() {
        cancelAutoDismiss()
        hidePanel { [weak self] in
            self?.state = .hidden
        }
    }

    // MARK: - Panel lifecycle

    private func ensurePanel() {
        guard panel == nil else { return }
        let window = BottomBarWindow(controller: self)
        self.panel = window
    }

    private func showPanel() {
        guard let panel else { return }
        panel.positionAtBottom()
        panel.alphaValue = 0

        // Начальная позиция ниже на 12pt
        var startFrame = panel.frame
        startFrame.origin.y -= 12
        panel.setFrame(startFrame, display: false)

        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = BottomBarMetrics.showDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            var endFrame = startFrame
            endFrame.origin.y += 12
            panel.animator().setFrame(endFrame, display: true)
        }
    }

    private func hidePanel(completion: @escaping () -> Void) {
        guard let panel else {
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = BottomBarMetrics.dismissDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
            completion()
        })
    }

    // MARK: - Auto-dismiss

    private func scheduleAutoDismiss(after delay: TimeInterval) {
        cancelAutoDismiss()
        let timer = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        autoDismissTimer = timer
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: timer
        )
    }

    private func cancelAutoDismiss() {
        autoDismissTimer?.cancel()
        autoDismissTimer = nil
    }
}

// MARK: - BottomBarWindow (NSPanel)

final class BottomBarWindow: NSPanel {

    init(controller: BottomBarController) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: BottomBarMetrics.pillWidth,
                height: BottomBarMetrics.pillHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        // NSVisualEffectView как фон
        guard let contentView else { return }
        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = BottomBarMetrics.pillHeight / 2
        visualEffect.layer?.masksToBounds = true

        // SwiftUI view
        let barView = BottomBarView(controller: controller)
        let hostingView = NSHostingView(rootView: barView)
        hostingView.frame = visualEffect.bounds
        hostingView.autoresizingMask = [.width, .height]

        // Фон hosting view прозрачный
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        visualEffect.addSubview(hostingView)
        contentView.addSubview(visualEffect)

        // Скруглённые углы окна
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = BottomBarMetrics.pillHeight / 2
        contentView.layer?.masksToBounds = true
    }

    func positionAtBottom() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - BottomBarMetrics.pillWidth / 2
        let y = screenFrame.origin.y + BottomBarMetrics.bottomOffset
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    // NSPanel не перехватывает фокус
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
