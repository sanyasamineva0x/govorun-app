import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Логика записи клавиши (чистая, без UI)

enum KeyRecorderLogic {
    // MARK: - FlagsResult

    /// Результат обработки события изменения модификаторов
    enum FlagsResult {
        /// Модификатор зажат — ждём, добавит ли пользователь обычную клавишу
        case awaitingRelease(CGEventFlags)
        /// Модификатор отпущен без клавиши — это одиночный модификатор
        case finalized
        /// Нет активных модификаторов и нет ожидающего — ничего делать не нужно
        case ignored
    }

    // MARK: - KeyResult

    /// Результат обработки события нажатия клавиши
    enum KeyResult {
        /// Обычная клавиша без модификатора
        case keyCode(UInt16)
        /// Комбинация модификатор + клавиша
        case combo(modifiers: CGEventFlags, keyCode: UInt16)
        /// Нажат Esc — отмена записи
        case cancel
        /// Событие не имеет смысла в текущем контексте
        case ignored
    }

    // MARK: - Обработка флагов модификаторов

    /// Обрабатывает событие flagsChanged и возвращает результат
    static func mapFlagsChanged(flags: CGEventFlags, hasPendingModifier: Bool) -> FlagsResult {
        let meaningful = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if !meaningful.isEmpty {
            return .awaitingRelease(meaningful)
        }
        if hasPendingModifier {
            return .finalized
        }
        return .ignored
    }

    // MARK: - Обработка нажатия клавиши

    /// Обрабатывает событие keyDown и возвращает результат
    static func mapKeyDown(keyCode: UInt16, currentFlags: CGEventFlags, hasPendingModifier: Bool) -> KeyResult {
        // Esc — всегда отмена
        if keyCode == 53 {
            return .cancel
        }
        let meaningful = currentFlags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if hasPendingModifier, !meaningful.isEmpty {
            return .combo(modifiers: meaningful, keyCode: keyCode)
        }
        return .keyCode(keyCode)
    }
}

// MARK: - KeyRecorderView

/// Карточка настроек, которая позволяет пользователю записать новую клавишу активации
struct KeyRecorderView: View {
    @ObservedObject var store: SettingsStore
    var workerState: WorkerState = .ready

    @State private var isRecording = false
    @State private var isHovered = false
    @State private var pendingModifier: CGEventFlags?
    @State private var previewText: String?
    @State private var monitors: [Any] = []

    // MARK: - Body

    var body: some View {
        Button(action: startRecording) {
            content
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    // MARK: - Контент карточки

    @ViewBuilder
    private var content: some View {
        if isRecording {
            recordingContent
        } else {
            normalContent
        }
    }

    private var normalContent: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 36, height: 36)
                .background(Color.mist)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                statusTitle
                    .font(.system(size: 14, weight: .medium))

                HStack(spacing: 4) {
                    Text("Горячая клавиша:")
                        .font(.caption)
                        .foregroundStyle(Color.ink.opacity(0.5))
                    Text(store.activationKey.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sage)
                    Text("· нажмите, чтобы изменить")
                        .font(.caption)
                        .foregroundStyle(isHovered ? Color.ink.opacity(0.5) : Color.ink.opacity(0.3))
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.ink.opacity(0.04) : Color.clear)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch workerState {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.sage)
        case .downloadingModel:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
        case .loadingModel:
            ProgressView()
                .scaleEffect(0.7)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.ember)
        default:
            ProgressView()
                .scaleEffect(0.7)
        }
    }

    private var statusTitle: some View {
        switch workerState {
        case .ready:
            Text("Говорун готов к работе")
        case .downloadingModel(let progress):
            Text("Качаю модель… \(progress)%")
        case .loadingModel:
            Text("Загружаю модель…")
        case .error(let msg):
            Text(ErrorMessages.humanReadable(msg))
        case .settingUp:
            Text("Готовлюсь…")
        case .notStarted:
            Text("Запуск…")
        }
    }

    private var recordingContent: some View {
        HStack(spacing: 12) {
            // Анимированная иконка записи
            Image(systemName: "keyboard")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.sage)
                .frame(width: 40, height: 40)
                .background(Color.mist)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                if let preview = previewText {
                    Text(preview)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sage)
                } else {
                    Text("Нажмите нужную клавишу…")
                        .font(.body)
                }
                Text("Esc — отмена")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .settingsCard()
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.ink.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Запись клавиши

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        pendingModifier = nil
        previewText = nil

        // Монитор событий модификаторов
        let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [self] event in
            handleFlagsChanged(event: event)
            return event
        }

        // Монитор событий нажатия клавиш
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleKeyDown(event: event)
            return nil // поглощаем событие во время записи
        }

        if let f = flagsMonitor {
            monitors.append(f)
        } else {
            print("[Govorun] KeyRecorder: flagsChanged monitor не создан")
        }
        if let k = keyMonitor {
            monitors.append(k)
        } else {
            print("[Govorun] KeyRecorder: keyDown monitor не создан")
        }
    }

    // MARK: - Остановка записи

    private func stopRecording() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        isRecording = false
        pendingModifier = nil
        previewText = nil
    }

    // MARK: - Обработка событий

    private func handleFlagsChanged(event: NSEvent) {
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        let result = KeyRecorderLogic.mapFlagsChanged(
            flags: flags,
            hasPendingModifier: pendingModifier != nil
        )
        switch result {
        case .awaitingRelease(let mods):
            pendingModifier = mods
            previewText = ActivationKey.modifierGlyphs(mods) + "…"
        case .finalized:
            if let mods = pendingModifier {
                store.activationKey = .modifier(mods)
            }
            stopRecording()
        case .ignored:
            break
        }
    }

    private func handleKeyDown(event: NSEvent) {
        let keyCode = event.keyCode
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        let result = KeyRecorderLogic.mapKeyDown(
            keyCode: keyCode,
            currentFlags: flags,
            hasPendingModifier: pendingModifier != nil
        )
        switch result {
        case .keyCode(let code):
            store.activationKey = .keyCode(code)
            stopRecording()
        case .combo(let mods, let code):
            store.activationKey = .combo(modifiers: mods, keyCode: code)
            stopRecording()
        case .cancel:
            stopRecording()
        case .ignored:
            break
        }
    }
}
