import SwiftUI

// MARK: - Главный экран настроек

struct SettingsView: View {
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedSection)
                .frame(width: 200)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionPageHeader(section: selectedSection)

                    switch selectedSection {
                    case .general:
                        GeneralSettingsContent()
                    case .appModes:
                        AppModeSettingsView()
                    case .dictionary:
                        DictionaryView()
                    case .snippets:
                        SnippetListView()
                    case .history:
                        HistoryView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .id(selectedSection)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .animation(.easeOut(duration: 0.25), value: selectedSection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor))
        }
    }
}

// MARK: - Сайдбар

private struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Brand zone
            VStack(spacing: 4) {
                Spacer().frame(height: 28)

                // Логотип
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)

            // Навигация
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsSection.visibleCases) { section in
                    SidebarItem(
                        title: section.title,
                        icon: section.icon,
                        isSelected: selection == section
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = section
                        }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Версия + обновление
            VStack(spacing: 6) {
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }

                if let updater = appState.updaterService, updater.updateAvailable {
                    Button("Обновить") {
                        updater.checkForUpdates()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.skyAqua)
                    .buttonStyle(.plain)
                    .disabled(!updater.canCheckForUpdates)
                }
            }
            .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Color(.controlBackgroundColor).opacity(0.5)
                LinearGradient(
                    colors: [Color.cottonCandy.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
    }
}

private struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var backgroundColor: Color {
        if isSelected { return Color.cottonCandy.opacity(0.14) }
        if isHovered { return Color.primary.opacity(0.06) }
        return Color.clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Accent bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.cottonCandy)
                    .frame(width: 3, height: 16)
                    .opacity(isSelected ? 1 : 0)
                    .padding(.trailing, 8)

                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.cottonCandy : .secondary)
                    .frame(width: 22)
                    .padding(.trailing, 8)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(backgroundColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Таб: Основные

private struct GeneralSettingsContent: View {
    @EnvironmentObject private var appState: AppState

    private func settingsBinding<T>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { appState.settings[keyPath: keyPath] = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Статус модели
            WorkerStatusCard(workerState: appState.workerState)
                .staggeredAppear(index: 0)

            ProductModeCard(selection: settingsBinding(\.productMode))
                .staggeredAppear(index: 1)

            // Клавиша активации
            KeyRecorderView(store: appState.settings)
                .staggeredAppear(index: 2)

            // Поведение
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Поведение", icon: "slider.horizontal.3")

                // Режим работы
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.and.hand.point.up.left")
                        .font(.body)
                        .foregroundStyle(Color.cottonCandy.opacity(0.7))
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Режим работы")
                            .font(.body)

                        Picker("", selection: settingsBinding(\.recordingMode)) {
                            ForEach(RecordingMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(appState.settings.recordingMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .animation(.easeInOut, value: appState.settings.recordingMode)
                    }
                }

                Divider()

                SettingsToggleRow(
                    title: "Точка в конце фразы",
                    description: "Ставить точку в конце фразы",
                    icon: "period",
                    isOn: settingsBinding(\.terminalPeriodEnabled)
                )

                Divider()

                SettingsToggleRow(
                    title: "Звуки",
                    description: "Звуковой сигнал начала и конца записи",
                    icon: "speaker.wave.2",
                    isOn: settingsBinding(\.soundEnabled)
                )

                Divider()

                SettingsToggleRow(
                    title: "Автозапуск",
                    description: "Запуск Говоруна при включении компьютера",
                    icon: "power",
                    iconColor: .oceanMist,
                    isOn: settingsBinding(\.launchAtLogin)
                )

                Divider()

                SettingsToggleRow(
                    title: "История записей",
                    description: "Хранить аудио на компьютере",
                    icon: "waveform",
                    iconColor: .orange,
                    isOn: settingsBinding(\.saveAudioHistory)
                )
            }
            .settingsCard()
            .staggeredAppear(index: 3)

            // Сброс

            HStack {
                Spacer()
                Button(action: {
                    appState.settings.resetToDefaults()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                        Text("Сбросить настройки")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .staggeredAppear(index: 4)
        }
    }
}

private struct ProductModeCard: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selection: ProductMode

    private var superAvailable: Bool {
        switch appState.superAssetsState {
        case .installed, .unknown, .checking:
            true
        case .modelMissing, .runtimeMissing, .error:
            false
        }
    }

    private var assetsStatusText: String? {
        switch appState.superAssetsState {
        case .unknown, .checking:
            "Проверяю готовность Super..."
        case .installed:
            nil
        case .modelMissing:
            "Модель не найдена. Скопируйте GGUF в ~/.govorun/models/"
        case .runtimeMissing:
            "Компонент llama-server отсутствует в приложении"
        case .error(let msg):
            "Ошибка: \(msg)"
        }
    }

    private var assetsStatusIcon: String {
        switch appState.superAssetsState {
        case .unknown, .checking: "hourglass"
        case .installed: "checkmark.circle"
        case .modelMissing: "exclamationmark.triangle"
        case .runtimeMissing, .error: "xmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Режим Говоруна", icon: "switch.2")

            HStack(spacing: 12) {
                Image(systemName: selection.usesLLM ? "sparkles" : "waveform")
                    .font(.body)
                    .foregroundStyle(Color.cottonCandy.opacity(0.75))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text(selection.title)
                        .font(.body)

                    Picker("", selection: $selection) {
                        ForEach(ProductMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selection) { _, newValue in
                        if newValue == .superMode, !superAvailable {
                            selection = .standard
                        }
                    }

                    Text(selection.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let assetsText = assetsStatusText {
                        Label(assetsText, systemImage: assetsStatusIcon)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(runtimeStatusText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .settingsCard()
        .onAppear {
            Task {
                await appState.refreshSuperAssetsReadiness()
            }
        }
    }

    private var runtimeStatusText: String {
        if appState.effectiveProductMode != selection {
            return "\(appState.effectiveProductMode.title) активен сейчас. Переключение применится после завершения сессии."
        }

        if !selection.usesLLM {
            return "LLM отключён. Используются GigaAM, словарь и deterministic-нормализация."
        }

        switch appState.llmRuntimeState {
        case .disabled:
            return "Super включён, но локальный LLM runtime выключен."
        case .notStarted:
            return "Super включён. Локальный LLM runtime ещё не стартовал."
        case .starting:
            return "Super включён. Поднимаю локальный LLM runtime."
        case .ready:
            return "Super включён. Локальный LLM runtime готов."
        case .error(let message):
            return "Super включён, но runtime недоступен: \(message)"
        }
    }
}

// MARK: - Статус модели

private struct WorkerStatusCard: View {
    @EnvironmentObject private var appState: AppState
    let workerState: WorkerState

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                statusTitle
                statusDetail
            }

            Spacer()

            if case .downloadingModel(let progress) = workerState {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: Double(progress), total: 100)
                        .progressViewStyle(.linear)
                        .frame(width: 100)
                    Button("Отменить") {
                        appState.cancelWorkerLoading()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }
        }
        .settingsCard()
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch workerState {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.green)
        case .downloadingModel:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
        case .loadingModel:
            ProgressView()
                .scaleEffect(0.8)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.red)
        default:
            ProgressView()
                .scaleEffect(0.8)
        }
    }

    private var statusTitle: some View {
        switch workerState {
        case .ready:
            Text("Говорун готов к работе")
                .font(.system(size: 13, weight: .medium))
        case .downloadingModel(let progress):
            Text("Качаю модель… \(progress)%")
                .font(.system(size: 13, weight: .medium))
        case .loadingModel:
            Text("Загружаю модель…")
                .font(.system(size: 13, weight: .medium))
        case .error(let msg):
            Text(ErrorMessages.humanReadable(msg))
                .font(.system(size: 13, weight: .medium))
        case .settingUp:
            Text("Готовлюсь…")
                .font(.system(size: 13, weight: .medium))
        case .notStarted:
            Text("Запуск…")
                .font(.system(size: 13, weight: .medium))
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch workerState {
        case .ready:
            let effective = appState.effectiveRecordingMode
            let selected = appState.settings.recordingMode
            if effective != selected {
                Text("\(effective.hint(key: appState.settings.activationKey.displayName)) (режим сменится после завершения сессии)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(effective.hint(key: appState.settings.activationKey.displayName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .downloadingModel:
            Text("~892 МБ, один раз")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error:
            VStack(alignment: .leading, spacing: 4) {
                Text("Попробую исправить")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Перезапустить") {
                        appState.retryWorkerLoading()
                    }
                    .font(.caption)
                    Button("Отменить") {
                        appState.cancelWorkerLoading()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        default:
            EmptyView()
        }
    }
}
