import Foundation

// MARK: - Состояния сессии

enum SessionState: Equatable {
    case idle
    case recording
    case processing
    case inserting
    case error(String)
}

// MARK: - Протокол делегата

@MainActor
protocol SessionManagerDelegate: AnyObject {
    func sessionManager(_ manager: SessionManager, didChangeState state: SessionState)
}

// MARK: - SessionManager

@MainActor
final class SessionManager {

    private(set) var state: SessionState = .idle {
        didSet {
            guard state != oldValue else { return }
            delegate?.sessionManager(self, didChangeState: state)
        }
    }

    weak var delegate: SessionManagerDelegate?

    // MARK: - Transitions

    /// ⌥ зажат 200ms+ → начинаем запись
    func handleActivated() {
        guard state == .idle else { return }
        state = .recording
    }

    /// ⌥ отпущен → переходим в обработку
    func handleDeactivated() {
        guard state == .recording else { return }
        state = .processing
    }

    /// Esc или ⌥+shortcut → отмена
    func handleCancelled() {
        guard state == .recording || state == .processing else { return }
        state = .idle
    }

    /// Pipeline завершил → вставляем текст
    func handleProcessingComplete() {
        guard state == .processing else { return }
        state = .inserting
    }

    /// Вставка завершена → idle
    func handleInsertionComplete() {
        guard state == .inserting else { return }
        state = .idle
    }

    /// Ошибка pipeline
    func handleError(_ message: String) {
        state = .error(message)
    }

    /// Сброс ошибки → idle
    func handleErrorDismissed() {
        guard case .error = state else { return }
        state = .idle
    }
}
