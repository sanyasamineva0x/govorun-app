import SwiftUI
import AVFoundation
import ApplicationServices

// MARK: - Шаги онбординга

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case microphone
    case accessibility
    case model
    case tryIt
}

// MARK: - OnboardingView

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var step: OnboardingStep = .welcome
    @State private var micPermissionGranted = false
    @State private var accessibilityGranted = false
    @State private var modelSkipped = false
    var onComplete: () -> Void = {}
    var settingsStore: SettingsStore = SettingsStore()

    private var canAdvance: Bool {
        switch step {
        case .welcome:
            return true
        case .microphone:
            return micPermissionGranted
        case .accessibility:
            return accessibilityGranted
        case .model:
            return appState.workerState == .ready || modelSkipped
        case .tryIt:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step.rawValue), total: Double(OnboardingStep.allCases.count - 1))
                .padding(.horizontal)
                .padding(.top, 12)

            Spacer()

            Group {
                switch step {
                case .welcome:
                    WelcomeStepView()
                case .microphone:
                    MicrophoneStepView(permissionGranted: $micPermissionGranted)
                case .accessibility:
                    AccessibilityStepView(accessibilityGranted: $accessibilityGranted)
                case .model:
                    ModelStepView(modelSkipped: $modelSkipped)
                case .tryIt:
                    TryItStepView(onComplete: completeOnboarding)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()

            HStack {
                if step != .welcome {
                    Button("Назад") { previousStep() }
                        .keyboardShortcut(.cancelAction)
                }

                Spacer()

                if step != .tryIt {
                    Button("Далее") { nextStep() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canAdvance)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 460)
    }

    private func nextStep() {
        let allCases = OnboardingStep.allCases
        guard let idx = allCases.firstIndex(of: step),
              allCases.index(after: idx) < allCases.endIndex else { return }
        var nextIdx = allCases.index(after: idx)
        // Пропустить шаг «Модель» если worker уже готов (модель скачана ранее)
        if allCases[nextIdx] == .model && appState.workerState == .ready {
            nextIdx = allCases.index(after: nextIdx)
            guard nextIdx < allCases.endIndex else { return }
        }
        withAnimation { step = allCases[nextIdx] }
    }

    private func previousStep() {
        let allCases = OnboardingStep.allCases
        guard let idx = allCases.firstIndex(of: step), idx > allCases.startIndex else { return }
        withAnimation { step = allCases[allCases.index(before: idx)] }
    }

    private func completeOnboarding() {
        settingsStore.onboardingCompleted = true
        onComplete()
    }
}

// MARK: - Шаг 1: Добро пожаловать

private struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Добро пожаловать в Говорун")
                .font(.title)
                .fontWeight(.bold)

            Text("Голосовой ввод на русском языке для macOS")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Зажмите клавишу и говорите", systemImage: "keyboard")
                Label("Скажите что-нибудь", systemImage: "waveform")
                Label("Отпустите — текст готов", systemImage: "doc.text")
            }
            .font(.body)
            .padding(.top, 8)
        }
        .padding()
    }
}

// MARK: - Шаг 2: Микрофон

private struct MicrophoneStepView: View {
    @Binding var permissionGranted: Bool
    @State private var permissionChecked = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Доступ к микрофону")
                .font(.title2)
                .fontWeight(.bold)

            Text("Говорун превращает ваш голос в готовый к отправке текст. Все данные остаются на вашем компьютере.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if permissionChecked {
                if permissionGranted {
                    Label("Доступ разрешён", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Зайти не получится. Сначала откройте Настройки системы.", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            } else {
                Button("Разрешить доступ") { requestMicrophoneAccess() }
                    .controlSize(.large)
            }
        }
        .padding()
        .onAppear { checkMicrophonePermission() }
    }

    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionGranted = true
            permissionChecked = true
        case .denied, .restricted:
            permissionGranted = false
            permissionChecked = true
        default:
            break
        }
    }

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                self.permissionGranted = granted
                self.permissionChecked = true
            }
        }
    }
}

// MARK: - Шаг 3: Accessibility

private struct AccessibilityStepView: View {
    @Binding var accessibilityGranted: Bool
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private static let accessibilityURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Разрешение на вставку текста")
                .font(.title2)
                .fontWeight(.bold)

            Text("Говорун вставляет текст напрямую в поле ввода. Без этого разрешения текст копируется через ⌘V.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if accessibilityGranted {
                Label("Доступ разрешён", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Ожидание разрешения…", systemImage: "clock")
                    .foregroundStyle(.orange)
            }

            Button("Открыть настройки системы") {
                openAccessibilitySettings()
            }
            .controlSize(.large)
        }
        .padding()
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
        }
        .onReceive(timer) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    private func openAccessibilitySettings() {
        guard let url = Self.accessibilityURL else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Шаг 4: Модель распознавания

private struct ModelStepView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var modelSkipped: Bool
    @State private var downloadStarted = false

    private var workerState: WorkerState { appState.workerState }
    private var networkMonitor: NetworkMonitor { appState.networkMonitor }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Модель распознавания")
                .font(.title2)
                .fontWeight(.bold)

            Text("Для работы Говоруна скачайте ИИ-модель (~900 МБ). Она работает на вашем компьютере и не отправляет данные в интернет.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Group {
                switch workerState {
                case .ready:
                    Label("Модель готова", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                case .downloadingModel(let progress):
                    VStack(spacing: 8) {
                        ProgressView(value: Double(progress), total: 100)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                        Text("Качаю модель… \(progress)%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Отменить") {
                            appState.cancelWorkerLoading()
                            downloadStarted = false
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                case .loadingModel:
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Загружаю модель…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .settingUp:
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Подготовка…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .error(let msg):
                    VStack(spacing: 8) {
                        Label(ErrorMessages.humanReadable(msg), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        HStack(spacing: 8) {
                            Button("Повторить") {
                                appState.retryWorkerLoading()
                            }
                            .controlSize(.small)
                            Button("Отменить") {
                                appState.cancelWorkerLoading()
                                downloadStarted = false
                            }
                            .controlSize(.small)
                            .foregroundStyle(.secondary)
                        }
                    }

                case .notStarted:
                    if !networkMonitor.isCurrentlyConnected {
                        Label("Подключитесь к интернету, чтобы скачать модель", systemImage: "wifi.slash")
                            .foregroundStyle(.orange)
                    }

                    Button("Скачать и установить") {
                        downloadStarted = true
                        appState.retryWorkerLoading()
                    }
                    .controlSize(.large)
                    .disabled(!networkMonitor.isCurrentlyConnected)
                }
            }

            // Пропустить — для пользователей без интернета или с проблемами
            if workerState != .ready {
                Button("Настроить позже") {
                    appState.cancelWorkerLoading()
                    modelSkipped = true
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Шаг 5: Попробуйте!

private struct TryItStepView: View {
    @EnvironmentObject private var appState: AppState
    var onComplete: () -> Void

    private var isWorkerReady: Bool { appState.workerState == .ready }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isWorkerReady ? "sparkles" : "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(isWorkerReady ? Color.accentColor : .orange)

            Text(isWorkerReady ? "Всё готово!" : "Почти готово!")
                .font(.title2)
                .fontWeight(.bold)

            if isWorkerReady {
                Text("Зажмите клавишу активации, скажите что-нибудь и отпустите. Говорун вставит текст в активное поле.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Text("Попробуйте прямо сейчас в любом приложении")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Для распознавания речи нужна модель. Скачайте её в настройках на вкладке «Основные».")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button("Готово") { onComplete() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}
