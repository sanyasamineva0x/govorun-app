import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private var onDismiss: (() -> Void)?

    init(appState: AppState, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss

        let onboardingView = OnboardingView()
            .environmentObject(appState)
        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Добро пожаловать в Говорун"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 460))
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        hostingController.rootView = OnboardingView { [weak self] in
            self?.handleClose()
        }
        .environmentObject(appState)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        window?.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.handleClose()
        }
    }

    private func handleClose() {
        window?.close()
        onDismiss?()
        onDismiss = nil
    }
}
