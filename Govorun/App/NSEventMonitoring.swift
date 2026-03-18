import Cocoa

// MARK: - Реализация EventMonitoring через CGEventTap + NSEvent

final class NSEventMonitoring: EventMonitoring {

    var activationKey: ActivationKey = .default

    /// Хранилище для keyDown/keyUp хандлеров — tap создаётся в addGlobalFlagsChanged
    /// до регистрации keyDown/keyUp, поэтому вызываем через замыкания
    var onKeyDown: ((UInt16) -> Void)?
    var onKeyUp: ((UInt16) -> Void)?

    func addGlobalFlagsChanged(_ handler: @escaping (CGEventFlags) -> Void) -> Any? {
        let tap = ActivationEventTap(
            activationKey: activationKey,
            flagsHandler: handler,
            keyDownHandler: { [weak self] code in self?.onKeyDown?(code) },
            keyUpHandler: { [weak self] code in self?.onKeyUp?(code) }
        )
        guard tap.start() else {
            print("[Govorun] CGEventTap не создан — нет Accessibility permission, fallback на NSEvent")
            // Fallback: NSEvent monitor (не может подавлять -> системный звук сохранится)
            return NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
                handler(CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
            }
        }
        return tap
    }

    func addGlobalKeyDown(_ handler: @escaping (UInt16) -> Void) -> Any? {
        onKeyDown = handler
        // NSEvent monitor тоже создаём: для не-подавленных событий (tap пропускает нецелевые)
        return NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handler(event.keyCode)
        }
    }

    func addGlobalKeyUp(_ handler: @escaping (UInt16) -> Void) -> Any? {
        onKeyUp = handler
        // NSEvent monitor тоже создаём: для не-подавленных событий
        return NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { event in
            handler(event.keyCode)
        }
    }

    func addLocalFlagsChanged(_ handler: @escaping (CGEventFlags) -> Void) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            handler(flags)
            return event
        }
    }

    func addLocalKeyDown(_ handler: @escaping (UInt16) -> Void) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event.keyCode)
            return event
        }
    }

    func addLocalKeyUp(_ handler: @escaping (UInt16) -> Void) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
            handler(event.keyCode)
            return event
        }
    }

    func removeMonitor(_ monitor: Any) {
        if let tap = monitor as? ActivationEventTap {
            tap.stop()
        } else {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - CGEventTap: обобщённый delay-and-replay для всех типов клавиш

/// Перехватывает события активации на уровне сессии (до доставки в приложения).
///
/// Стратегия delay-and-replay зависит от типа ActivationKey:
///
/// `.modifier` — flagsChanged:
/// 1. Modifier down (один) -> подавляем, сохраняем копию, ставим таймер 200ms
/// 2. Modifier up ДО таймера -> re-post down+up (быстрый тап, обычное поведение)
/// 3. Таймер сработал -> Говорун активирован, подавляем всё
/// 4. Modifier up ПОСЛЕ таймера -> подавляем (запись закончилась)
///
/// `.keyCode` — keyDown + keyUp:
/// 1. keyDown с целевым keyCode -> подавляем, сохраняем копию, ставим таймер 200ms
/// 2. keyUp ДО таймера -> re-post keyDown+keyUp (быстрый тап, обычное поведение)
/// 3. Таймер сработал -> Говорун активирован, подавляем все keyDown (autorepeat)
/// 4. keyUp ПОСЛЕ таймера -> подавляем (запись закончилась)
///
/// `.combo` — flagsChanged + keyDown + keyUp:
/// 1. flagsChanged с целевыми модификаторами -> запоминаем, НЕ подавляем
/// 2. keyDown с целевым keyCode при зажатых модификаторах -> delay-and-replay как keyCode
/// 3. keyUp -> окончание записи
/// 4. Модификатор отпущен до keyDown -> сброс
final class ActivationEventTap {

    private let context: ActivationTapContext
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        activationKey: ActivationKey,
        flagsHandler: @escaping (CGEventFlags) -> Void,
        keyDownHandler: @escaping (UInt16) -> Void,
        keyUpHandler: @escaping (UInt16) -> Void
    ) {
        self.context = ActivationTapContext(
            activationKey: activationKey,
            flagsHandler: flagsHandler,
            keyDownHandler: keyDownHandler,
            keyUpHandler: keyUpHandler
        )
    }

    func start() -> Bool {
        let refcon = Unmanaged.passUnretained(context).toOpaque()

        let eventMask: CGEventMask
        switch context.activationKey {
        case .modifier:
            eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        case .keyCode:
            eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
        case .combo:
            eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
                | CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: activationTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        machPort = port
        context.machPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        context.cancelTimer()
        guard let port = machPort else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        machPort = nil
    }

    deinit {
        stop()
    }
}

// MARK: - ActivationTapContext

/// Состояние CGEventTap (передаётся в C-callback через refcon)
/// Примечание по threading: callback вызывается на main RunLoop (tap добавлен в CFRunLoopGetMain).
/// Все хандлеры должны быть thread-safe или вызываться только с main.
private final class ActivationTapContext {
    let activationKey: ActivationKey
    let flagsHandler: (CGEventFlags) -> Void
    let keyDownHandler: (UInt16) -> Void
    let keyUpHandler: (UInt16) -> Void
    var machPort: CFMachPort?

    /// Подавленное down-событие (ожидает решения: replay или eat)
    var pendingDown: CGEvent?
    /// true -> таймер сработал, Говорун активирован, подавляем всё
    var activated = false
    /// Для combo: целевые модификаторы зажаты
    var comboModifiersHeld = false
    /// Таймер для принятия решения
    private var delayTimer: DispatchWorkItem?

    init(
        activationKey: ActivationKey,
        flagsHandler: @escaping (CGEventFlags) -> Void,
        keyDownHandler: @escaping (UInt16) -> Void,
        keyUpHandler: @escaping (UInt16) -> Void
    ) {
        self.activationKey = activationKey
        self.flagsHandler = flagsHandler
        self.keyDownHandler = keyDownHandler
        self.keyUpHandler = keyUpHandler
    }

    func startTimer() {
        cancelTimer()
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 200ms прошло, клавиша всё ещё зажата -> активация Говоруна
            self.pendingDown = nil
            self.activated = true
        }
        delayTimer = timer
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ActivationKeyConstants.activationDelay,
            execute: timer
        )
    }

    func cancelTimer() {
        delayTimer?.cancel()
        delayTimer = nil
    }

    /// Re-post подавленное событие обратно в систему
    func replayPendingDown() {
        guard let event = pendingDown else { return }
        pendingDown = nil
        event.post(tap: .cgSessionEventTap)
    }
}

// MARK: - C-callback

private func activationTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<ActivationTapContext>.fromOpaque(refcon).takeUnretainedValue()

    // Система отключила tap -> переактивируем
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = context.machPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    switch context.activationKey {
    case .modifier(let targetFlags):
        return handleModifierTap(context: context, type: type, event: event, targetFlags: targetFlags)
    case .keyCode(let targetCode):
        return handleKeyCodeTap(context: context, type: type, event: event, targetCode: targetCode)
    case .combo(let targetModifiers, let targetCode):
        return handleComboTap(
            context: context, type: type, event: event,
            targetModifiers: targetModifiers, targetCode: targetCode
        )
    }
}

// MARK: - Modifier: delay-and-replay (текущее поведение)

private func handleModifierTap(
    context: ActivationTapContext,
    type: CGEventType,
    event: CGEvent,
    targetFlags: CGEventFlags
) -> Unmanaged<CGEvent>? {
    let flags = event.flags
    let targetDown = flags.rawValue & targetFlags.rawValue == targetFlags.rawValue
        && targetFlags.rawValue != 0

    // Проверяем «другие» модификаторы (всё кроме целевого)
    let allModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
    let otherModifiers = CGEventFlags(rawValue: allModifiers.rawValue & ~targetFlags.rawValue)
    let hasOtherModifiers = flags.rawValue & otherModifiers.rawValue != 0

    // Всегда передаём в ActivationKeyMonitor
    context.flagsHandler(flags)

    // Комбинация с другими модификаторами -> пропускаем, сбрасываем состояние
    if hasOtherModifiers {
        context.cancelTimer()
        context.replayPendingDown()
        context.activated = false
        return Unmanaged.passUnretained(event)
    }

    if targetDown {
        // Целевой модификатор down (один)
        context.pendingDown = event.copy()
        context.activated = false
        context.startTimer()
        return nil // подавляем, ждём решения
    }

    // Целевой модификатор up
    if context.pendingDown != nil {
        // Быстрый тап (< 200ms) -> replay down + пропустить up
        context.cancelTimer()
        context.replayPendingDown()
        context.activated = false
        return Unmanaged.passUnretained(event)
    }

    if context.activated {
        // Отпустил после активации -> подавляем up
        context.activated = false
        return nil
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - KeyCode: delay-and-replay

private func handleKeyCodeTap(
    context: ActivationTapContext,
    type: CGEventType,
    event: CGEvent,
    targetCode: UInt16
) -> Unmanaged<CGEvent>? {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

    guard keyCode == targetCode else {
        return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
        if context.pendingDown != nil || context.activated {
            // Авторепит после начала delay или после активации -> подавляем
            return nil
        }

        // Первый keyDown -> delay-and-replay
        context.pendingDown = event.copy()
        context.activated = false
        context.keyDownHandler(keyCode)
        context.startTimer()
        return nil
    }

    if type == .keyUp {
        if context.pendingDown != nil {
            // Быстрый тап (< 200ms) -> replay keyDown + пропустить keyUp
            context.cancelTimer()
            context.keyUpHandler(keyCode)
            context.replayPendingDown()
            context.activated = false
            return Unmanaged.passUnretained(event)
        }

        if context.activated {
            // Отпустил после активации -> подавляем keyUp
            context.activated = false
            context.keyUpHandler(keyCode)
            return nil
        }
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - Combo: delay-and-replay

private func handleComboTap(
    context: ActivationTapContext,
    type: CGEventType,
    event: CGEvent,
    targetModifiers: CGEventFlags,
    targetCode: UInt16
) -> Unmanaged<CGEvent>? {

    if type == .flagsChanged {
        let flags = event.flags
        let modDown = flags.rawValue & targetModifiers.rawValue == targetModifiers.rawValue
            && targetModifiers.rawValue != 0

        // Всегда передаём flags в ActivationKeyMonitor
        context.flagsHandler(flags)

        if modDown {
            context.comboModifiersHeld = true
        } else if context.comboModifiersHeld {
            // Модификатор отпущен
            context.comboModifiersHeld = false

            if context.pendingDown != nil {
                // Модификатор отпущен до таймера -> replay keyDown
                context.cancelTimer()
                context.replayPendingDown()
                context.activated = false
            } else if context.activated {
                // Модификатор отпущен после активации -> сброс
                context.activated = false
            }
        }

        // Модификаторы НЕ подавляем (должны проходить в систему)
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

    guard keyCode == targetCode, context.comboModifiersHeld else {
        return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
        if context.pendingDown != nil || context.activated {
            // Авторепит -> подавляем
            return nil
        }

        // keyDown при зажатых модификаторах -> delay-and-replay
        context.pendingDown = event.copy()
        context.activated = false
        context.keyDownHandler(keyCode)
        context.startTimer()
        return nil
    }

    if type == .keyUp {
        if context.pendingDown != nil {
            // Быстрый тап (< 200ms) -> replay keyDown + пропустить keyUp
            context.cancelTimer()
            context.keyUpHandler(keyCode)
            context.replayPendingDown()
            context.activated = false
            return Unmanaged.passUnretained(event)
        }

        if context.activated {
            // Отпустил после активации -> подавляем keyUp
            context.activated = false
            context.keyUpHandler(keyCode)
            return nil
        }
    }

    return Unmanaged.passUnretained(event)
}
