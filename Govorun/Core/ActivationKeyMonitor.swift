import CoreGraphics
import Foundation

// MARK: - Протокол для тестируемости

protocol EventMonitoring: AnyObject {
    /// Текущая клавиша активации (определяет какие CGEvent types перехватывает tap)
    var activationKey: ActivationKey { get set }
    /// Режим записи (определяет поведение suppression в tap)
    var recordingMode: RecordingMode { get set }
    func addGlobalFlagsChanged(_ handler: @escaping (CGEventFlags) -> Void) -> Any?
    func addGlobalKeyDown(_ handler: @escaping (UInt16) -> Void) -> Any?
    func addGlobalKeyUp(_ handler: @escaping (UInt16) -> Void) -> Any?
    func addLocalFlagsChanged(_ handler: @escaping (CGEventFlags) -> Void) -> Any?
    func addLocalKeyDown(_ handler: @escaping (UInt16) -> Void) -> Any?
    func addLocalKeyUp(_ handler: @escaping (UInt16) -> Void) -> Any?
    func removeMonitor(_ monitor: Any)
}

// MARK: - Константы

enum ActivationKeyConstants {
    static let activationDelay: TimeInterval = 0.2
}

// MARK: - ActivationKeyMonitor

/// Универсальный монитор клавиши активации: поддерживает modifier, keyCode и combo.
/// Работает только на main thread (NSEvent мониторы, таймеры на main queue).
@MainActor
final class ActivationKeyMonitor {

    var onActivated: (() -> Void)?
    var onDeactivated: (() -> Void)?
    var onCancelled: (() -> Void)?

    static let activationDelay = ActivationKeyConstants.activationDelay

    /// Текущая клавиша активации (нужна AppState для recreateMonitor)
    let activationKey: ActivationKey
    /// Режим работы: pushToTalk или toggle
    let recordingMode: RecordingMode

    private let eventMonitor: EventMonitoring
    private var monitors: [Any] = []
    private var activationTimer: DispatchWorkItem?

    // MARK: Состояние

    /// Физически зажата клавиша активации
    private var isKeyDown = false
    /// Таймер сработал — Говорун активен
    private var isActivated = false
    /// Toggle: таймер сработал, ждём keyUp для активации
    private var isArmed = false
    /// Для combo: нужные модификаторы зажаты
    private var comboModifiersDown = false

    // MARK: Init

    init(activationKey: ActivationKey, recordingMode: RecordingMode = .pushToTalk, eventMonitor: EventMonitoring) {
        self.activationKey = activationKey
        self.recordingMode = recordingMode
        self.eventMonitor = eventMonitor
    }

    // MARK: - Публичный интерфейс

    func startMonitoring() {
        // Подписываемся на все 6 типов событий (global + local × flags/keyDown/keyUp)
        if let m = eventMonitor.addGlobalFlagsChanged({ [weak self] flags in
            self?.handleFlagsChanged(flags)
        }) { monitors.append(m) }

        if let m = eventMonitor.addGlobalKeyDown({ [weak self] code in
            self?.handleKeyDown(code)
        }) { monitors.append(m) }

        if let m = eventMonitor.addGlobalKeyUp({ [weak self] code in
            self?.handleKeyUp(code)
        }) { monitors.append(m) }

        if let m = eventMonitor.addLocalFlagsChanged({ [weak self] flags in
            self?.handleFlagsChanged(flags)
        }) { monitors.append(m) }

        if let m = eventMonitor.addLocalKeyDown({ [weak self] code in
            self?.handleKeyDown(code)
        }) { monitors.append(m) }

        if let m = eventMonitor.addLocalKeyUp({ [weak self] code in
            self?.handleKeyUp(code)
        }) { monitors.append(m) }
    }

    func stopMonitoring() {
        for monitor in monitors {
            eventMonitor.removeMonitor(monitor)
        }
        monitors.removeAll()
        cancelActivation()
        isKeyDown = false
        isActivated = false
        isArmed = false
        comboModifiersDown = false
    }

    // MARK: - Обработчики событий

    private func handleFlagsChanged(_ flags: CGEventFlags) {
        switch activationKey {
        case .modifier(let target):
            handleModifierFlagsChanged(flags: flags, target: target)
        case .keyCode:
            break // флаги не используются для keyCode
        case .combo(let targetModifiers, _):
            handleComboFlagsChanged(flags: flags, targetModifiers: targetModifiers)
        }
    }

    private func handleKeyDown(_ code: UInt16) {
        switch activationKey {
        case .modifier:
            handleModifierKeyDown()
        case .keyCode(let target):
            handleKeyCodeDown(code: code, target: target)
        case .combo(_, let targetCode):
            handleComboKeyDown(code: code, targetCode: targetCode)
        }
    }

    private func handleKeyUp(_ code: UInt16) {
        switch activationKey {
        case .modifier:
            break // keyUp не используется для modifier (используется flagsChanged)
        case .keyCode(let target):
            handleKeyCodeUp(code: code, target: target)
        case .combo(_, let targetCode):
            handleComboKeyUp(code: code, targetCode: targetCode)
        }
    }

    // MARK: - Modifier логика

    private func handleModifierFlagsChanged(flags: CGEventFlags, target: CGEventFlags) {
        let isDown = flags.rawValue & target.rawValue == target.rawValue && target.rawValue != 0

        if isDown && !isKeyDown {
            // Модификатор нажат
            isKeyDown = true
            if !isActivated {
                scheduleActivation()
            }
        } else if !isDown && isKeyDown {
            // Модификатор отпущен
            isKeyDown = false
            cancelActivation()
            handleRelease()
        }
    }

    private func handleModifierKeyDown() {
        // Другая клавиша нажата пока модификатор зажат (до активации) → это шорткат
        guard isKeyDown, !isActivated else { return }
        cancelActivation()
        isArmed = false
        onCancelled?()
    }

    // MARK: - KeyCode логика

    private func handleKeyCodeDown(code: UInt16, target: UInt16) {
        guard code == target else { return }
        guard !isKeyDown else { return } // игнорируем авторепит

        isKeyDown = true
        if !isActivated {
            scheduleActivation()
        }
    }

    private func handleKeyCodeUp(code: UInt16, target: UInt16) {
        guard code == target, isKeyDown else { return }

        isKeyDown = false
        cancelActivation()
        handleRelease()
    }

    // MARK: - Combo логика

    private func handleComboFlagsChanged(flags: CGEventFlags, targetModifiers: CGEventFlags) {
        let modDown = flags.rawValue & targetModifiers.rawValue == targetModifiers.rawValue
            && targetModifiers.rawValue != 0

        if !modDown && comboModifiersDown {
            // Модификатор отпущен
            comboModifiersDown = false

            if isKeyDown {
                // Клавиша всё ещё зажата — деактивируем
                isKeyDown = false
                cancelActivation()
                handleRelease()
            }
        } else {
            comboModifiersDown = modDown
        }
    }

    private func handleComboKeyDown(code: UInt16, targetCode: UInt16) {
        guard code == targetCode else { return }
        guard comboModifiersDown else { return } // модификатор должен быть зажат
        guard !isKeyDown else { return }          // игнорируем авторепит

        isKeyDown = true
        if !isActivated {
            scheduleActivation()
        }
    }

    private func handleComboKeyUp(code: UInt16, targetCode: UInt16) {
        guard code == targetCode, isKeyDown else { return }

        isKeyDown = false
        cancelActivation()
        handleRelease()
    }

    // MARK: - Общая логика отпускания клавиши

    /// Вызывается при отпускании клавиши активации (после cancelActivation)
    private func handleRelease() {
        if recordingMode == .toggle && isArmed {
            // Toggle: первое отпускание после armed → активация
            isArmed = false
            isActivated = true
            onActivated?()
        } else if isActivated {
            // PTT: отпускание → деактивация
            // Toggle: повторное отпускание → деактивация
            isActivated = false
            onDeactivated?()
        }
    }

    // MARK: - Таймер

    private func scheduleActivation() {
        cancelActivation()

        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.isKeyDown else { return }
            if self.recordingMode == .toggle {
                self.isArmed = true
            } else {
                self.isActivated = true
                self.onActivated?()
            }
        }
        activationTimer = timer
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ActivationKeyConstants.activationDelay,
            execute: timer
        )
    }

    private func cancelActivation() {
        activationTimer?.cancel()
        activationTimer = nil
    }
}
