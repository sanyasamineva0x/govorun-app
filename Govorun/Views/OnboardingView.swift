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

    private var progress: Double {
        Double(step.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Прогресс-бар в фирменном стиле
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.alabasterGrey.opacity(0.15))
                        .frame(height: 3)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.cottonCandy, Color.cottonCandy.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress, height: 3)
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 24)
            .padding(.top, 16)

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
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()

            // Навигация
            HStack {
                if step != .welcome {
                    Button(action: previousStep) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                            Text("Назад")
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if step != .tryIt {
                    BrandedButton(
                        title: "Далее",
                        style: canAdvance ? .primary : .secondary,
                        action: nextStep
                    )
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.5)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 480, height: 480)
    }

    private func nextStep() {
        let allCases = OnboardingStep.allCases
        guard let idx = allCases.firstIndex(of: step),
              allCases.index(after: idx) < allCases.endIndex else { return }
        var nextIdx = allCases.index(after: idx)
        if allCases[nextIdx] == .model && appState.workerState == .ready {
            nextIdx = allCases.index(after: nextIdx)
            guard nextIdx < allCases.endIndex else { return }
        }
        withAnimation(.easeInOut(duration: 0.3)) { step = allCases[nextIdx] }
    }

    private func previousStep() {
        let allCases = OnboardingStep.allCases
        guard let idx = allCases.firstIndex(of: step), idx > allCases.startIndex else { return }
        withAnimation(.easeInOut(duration: 0.3)) { step = allCases[allCases.index(before: idx)] }
    }

    private func completeOnboarding() {
        settingsStore.onboardingCompleted = true
        onComplete()
    }
}

// MARK: - Шаг 1: Добро пожаловать

private struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .staggeredAppear(index: 0)

            VStack(spacing: 8) {
                Text("Привет, это Говорун!")
                    .font(.system(size: 28, weight: .bold))
                    .staggeredAppear(index: 1)
                Text("Голосовой ввод на русском")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .staggeredAppear(index: 2)
            }

            VStack(alignment: .leading, spacing: 12) {
                OnboardingFeatureRow(icon: "keyboard", text: "Зажмите клавишу и говорите")
                OnboardingFeatureRow(icon: "waveform", text: "Распознавание прямо на Mac")
                OnboardingFeatureRow(icon: "lock.shield", text: "Полностью офлайн — данные не покидают компьютер")
            }
            .settingsCard()
            .staggeredAppear(index: 3)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Шаг 2: Микрофон

private struct MicrophoneStepView: View {
    @Binding var permissionGranted: Bool
    @State private var permissionChecked = false

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .staggeredAppear(index: 0)

            VStack(spacing: 8) {
                Text("Доступ к микрофону")
                    .font(.system(size: 22, weight: .bold))
                    .staggeredAppear(index: 1)
                Text("Я превращаю ваш голос в готовый текст")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .staggeredAppear(index: 2)
            }

            Group {
                if permissionChecked {
                    if permissionGranted {
                        OnboardingStatusBadge(text: "Доступ разрешён", icon: "checkmark.circle.fill", color: .oceanMist)
                    } else {
                        OnboardingStatusBadge(text: "Откройте Настройки системы → Микрофон", icon: "xmark.circle.fill", color: .red)
                    }
                } else {
                    BrandedButton(title: "Разрешить доступ", style: .primary, action: requestMicrophoneAccess)
                }
            }
            .staggeredAppear(index: 3)
        }
        .padding(.horizontal, 32)
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
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.cottonCandy)
                .staggeredAppear(index: 0)

            VStack(spacing: 8) {
                Text("Вставка текста")
                    .font(.system(size: 22, weight: .bold))
                    .staggeredAppear(index: 1)
                Text("Я вставлю текст прямо в поле ввода.\nБез этого разрешения придётся использовать буфер обмена.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .staggeredAppear(index: 2)
            }

            VStack(spacing: 12) {
                if accessibilityGranted {
                    OnboardingStatusBadge(text: "Доступ разрешён", icon: "checkmark.circle.fill", color: .oceanMist)
                } else {
                    OnboardingStatusBadge(text: "Ожидание разрешения…", icon: "clock", color: .orange)
                }

                BrandedButton(title: "Открыть настройки системы", style: .secondary) {
                    openAccessibilitySettings()
                }
            }
            .staggeredAppear(index: 3)
        }
        .padding(.horizontal, 32)
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
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 44))
                .foregroundStyle(Color.cottonCandy)
                .staggeredAppear(index: 0)

            VStack(spacing: 8) {
                Text("ИИ-модель")
                    .font(.system(size: 22, weight: .bold))
                    .staggeredAppear(index: 1)
                Text("Для работы нужна ИИ-модель (~900 МБ).\nОна работает локально и не отправляет данные в интернет")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .staggeredAppear(index: 2)
            }

            VStack(spacing: 12) {
                switch workerState {
                case .ready:
                    OnboardingStatusBadge(text: "Модель готова", icon: "checkmark.circle.fill", color: .oceanMist)

                case .downloadingModel(let progress):
                    VStack(spacing: 8) {
                        ProgressView(value: Double(progress), total: 100)
                            .progressViewStyle(.linear)
                            .tint(Color.cottonCandy)
                            .frame(width: 240)
                        Text("Качаю модель… \(progress)%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Отменить") {
                            appState.cancelWorkerLoading()
                            downloadStarted = false
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .buttonStyle(.plain)
                    }

                case .loadingModel, .settingUp:
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.cottonCandy)
                        Text(workerState == .settingUp ? "Подготовка…" : "Загружаю модель…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                case .error(let msg):
                    VStack(spacing: 10) {
                        OnboardingStatusBadge(
                            text: ErrorMessages.humanReadable(msg),
                            icon: "exclamationmark.triangle.fill",
                            color: .red
                        )
                        HStack(spacing: 12) {
                            BrandedButton(title: "Повторить", style: .primary) {
                                appState.retryWorkerLoading()
                            }
                            BrandedButton(title: "Отмена", style: .secondary) {
                                appState.cancelWorkerLoading()
                                downloadStarted = false
                            }
                        }
                    }

                case .notStarted:
                    VStack(spacing: 10) {
                        if !networkMonitor.isCurrentlyConnected {
                            OnboardingStatusBadge(
                                text: "Нет интернета",
                                icon: "wifi.slash",
                                color: .orange
                            )
                        }
                        BrandedButton(title: "Скачать (~900 МБ)", style: .primary) {
                            downloadStarted = true
                            appState.retryWorkerLoading()
                        }
                        .disabled(!networkMonitor.isCurrentlyConnected)
                        .opacity(networkMonitor.isCurrentlyConnected ? 1 : 0.5)
                    }
                }
            }
            .settingsCard()
            .staggeredAppear(index: 3)

            if workerState != .ready {
                Button("Настроить позже") {
                    appState.cancelWorkerLoading()
                    modelSkipped = true
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Шаг 5: Попробуйте!

private struct TryItStepView: View {
    @EnvironmentObject private var appState: AppState
    var onComplete: () -> Void

    private var isWorkerReady: Bool { appState.workerState == .ready }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: isWorkerReady ? "sparkles" : "arrow.down.circle")
                .font(.system(size: 44))
                .foregroundStyle(isWorkerReady ? Color.cottonCandy : .orange)
                .staggeredAppear(index: 0)

            VStack(spacing: 8) {
                Text(isWorkerReady ? "Всё готово!" : "Почти готово!")
                    .font(.system(size: 22, weight: .bold))
                    .staggeredAppear(index: 1)

                Group {
                    if isWorkerReady {
                        Text("Зажмите клавишу и скажите что-нибудь. Я вставлю текст в поле ввода.")
                    } else {
                        Text("Скачайте модель в настройках на вкладке «Основные»")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .staggeredAppear(index: 2)
            }

            BrandedButton(title: "Готово", style: .primary, action: onComplete)
                .staggeredAppear(index: 3)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Переиспользуемые компоненты онбординга

private struct OnboardingFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.cottonCandy.opacity(0.8))
                .frame(width: 24, height: 24)
            Text(text)
                .font(.callout)
        }
    }
}

private struct OnboardingStatusBadge: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(color)
    }
}
