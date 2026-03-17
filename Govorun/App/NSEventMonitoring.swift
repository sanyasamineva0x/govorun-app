import Cocoa

// MARK: - Реализация EventMonitoring через CGEventTap + NSEvent

final class NSEventMonitoring: EventMonitoring {

    func addGlobalFlagsChanged(_ handler: @escaping (Bool) -> Void) -> Any? {
        let tap = FlagsChangedEventTap(handler: handler)
        guard tap.start() else {
            // Fallback: NSEvent monitor (не может подавлять → системный звук сохранится)
            return NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
                handler(event.modifierFlags.contains(.option))
            }
        }
        return tap
    }

    func addGlobalKeyDown(_ handler: @escaping () -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in
            handler()
        }
    }

    func addLocalFlagsChanged(_ handler: @escaping (Bool) -> Void) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let optionDown = event.modifierFlags.contains(.option)
            handler(optionDown)
            return optionDown ? nil : event
        }
    }

    func addLocalKeyDown(_ handler: @escaping () -> Void) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let optionDown = event.modifierFlags.contains(.option)
            handler()
            return optionDown ? nil : event
        }
    }

    func removeMonitor(_ monitor: Any) {
        if let tap = monitor as? FlagsChangedEventTap {
            tap.stop()
        } else {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - CGEventTap: delay-and-replay стратегия

/// Перехватывает flagsChanged на уровне сессии (до доставки в приложения).
///
/// Стратегия delay-and-replay:
/// 1. Option down (один) → подавляем, сохраняем копию, ставим таймер 200ms
/// 2. Option up ДО таймера → re-post down+up (быстрый тап, обычное поведение)
/// 3. Таймер сработал → Говорун активирован, подавляем всё
/// 4. Option up ПОСЛЕ таймера → подавляем (запись закончилась)
///
/// Так Option-click, Option-меню и спецсимволы работают как обычно,
/// а системный звук при долгом удержании для диктовки подавлен.
final class FlagsChangedEventTap {

    private let context: TapContext
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping (Bool) -> Void) {
        self.context = TapContext(handler: handler)
    }

    func start() -> Bool {
        let refcon = Unmanaged.passUnretained(context).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: flagsChangedTapCallback,
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

// MARK: - TapContext

/// Состояние CGEventTap (передаётся в C-callback через refcon)
private final class TapContext {
    let handler: (Bool) -> Void
    var machPort: CFMachPort?

    /// Подавленное Option down событие (ожидает решения: replay или eat)
    var pendingOptionDown: CGEvent?
    /// true → таймер сработал, Говорун активирован, подавляем всё
    var activated = false
    /// Таймер для принятия решения
    private var delayTimer: DispatchWorkItem?

    /// Задержка = OptionKeyMonitor.activationDelay (200ms)
    static let activationDelay: TimeInterval = 0.2

    init(handler: @escaping (Bool) -> Void) {
        self.handler = handler
    }

    func startTimer() {
        cancelTimer()
        let timer = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 200ms прошло, Option всё ещё зажат → активация Говоруна
            self.pendingOptionDown = nil
            self.activated = true
        }
        delayTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationDelay, execute: timer)
    }

    func cancelTimer() {
        delayTimer?.cancel()
        delayTimer = nil
    }

    /// Re-post подавленное событие обратно в систему
    func replayPendingDown() {
        guard let event = pendingOptionDown else { return }
        pendingOptionDown = nil
        event.post(tap: .cgSessionEventTap)
    }
}

// MARK: - C-callback

private func flagsChangedTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(refcon).takeUnretainedValue()

    // Система отключила tap → переактивируем
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = context.machPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    let flags = event.flags
    let optionDown = flags.contains(.maskAlternate)
    let otherModifiers = flags.intersection([.maskCommand, .maskControl, .maskShift])

    // Всегда передаём в Говорун (OptionKeyMonitor обрабатывает параллельно)
    context.handler(optionDown)

    // Комбинация с другими модификаторами — пропускаем, сбрасываем состояние
    if !otherModifiers.isEmpty {
        context.cancelTimer()
        context.replayPendingDown()
        context.activated = false
        return Unmanaged.passUnretained(event)
    }

    if optionDown {
        // Option down (один)
        context.pendingOptionDown = event.copy()
        context.activated = false
        context.startTimer()
        return nil // подавляем, ждём решения
    }

    // Option up
    if context.pendingOptionDown != nil {
        // Быстрый тап (< 200ms) → replay down + пропустить up
        context.cancelTimer()
        context.replayPendingDown()
        context.activated = false
        return Unmanaged.passUnretained(event)
    }

    if context.activated {
        // Отпустил после активации → подавляем up
        context.activated = false
        return nil
    }

    return Unmanaged.passUnretained(event)
}
