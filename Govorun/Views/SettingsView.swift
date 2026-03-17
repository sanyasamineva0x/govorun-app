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

    var body: some View {
        VStack(spacing: 0) {
            // Brand zone
            VStack(spacing: 4) {
                Spacer().frame(height: 28)

                // Монограмма
                Text("Г")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.cottonCandy)
                    .frame(width: 44, height: 44)
                    .background(Color.cottonCandy.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text("Говорун")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("голосовой ввод")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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

            // Версия
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 14)
            }
        }
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Color(.controlBackgroundColor).opacity(0.5)
                // Subtle warm gradient at top
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
    @StateObject private var store = SettingsStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Статус модели
            WorkerStatusCard(workerState: appState.workerState)
                .staggeredAppear(index: 0)

            // Shortcut card
            HStack(spacing: 16) {
                Text("⌥")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.cottonCandy)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Зажмите Option и говорите")
                        .font(.system(size: 13, weight: .medium))
                    Text("Отпустите клавишу — текст появится в поле ввода")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .settingsCard()
            .staggeredAppear(index: 1)

            // Запись
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Поведение", icon: "slider.horizontal.3")

                SettingsToggleRow(
                    title: "Звуки при записи",
                    description: "Сигнал начала и окончания записи",
                    icon: "speaker.wave.2",
                    isOn: $store.soundEnabled
                )

                Divider()

                SettingsToggleRow(
                    title: "Запуск при входе в систему",
                    description: "Говорун запустится автоматически",
                    icon: "power",
                    iconColor: .oceanMist,
                    isOn: $store.launchAtLogin
                )

                Divider()

                SettingsToggleRow(
                    title: "Сохранять аудиозаписи",
                    description: "Записи хранятся локально для истории прослушивания",
                    icon: "waveform",
                    iconColor: .orange,
                    isOn: $store.saveAudioHistory
                )
            }
            .settingsCard()
            .staggeredAppear(index: 2)

            // Сброс
            HStack {
                Spacer()
                Button(action: { store.resetToDefaults() }) {
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
            .staggeredAppear(index: 3)
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
            return Text("Говорун готов к работе")
                .font(.system(size: 13, weight: .medium))
        case .downloadingModel(let progress):
            return Text("Качаю модель… \(progress)%")
                .font(.system(size: 13, weight: .medium))
        case .loadingModel:
            return Text("Загружаю модель…")
                .font(.system(size: 13, weight: .medium))
        case .error(let msg):
            return Text(ErrorMessages.humanReadable(msg))
                .font(.system(size: 13, weight: .medium))
        case .settingUp:
            return Text("Готовлюсь…")
                .font(.system(size: 13, weight: .medium))
        case .notStarted:
            return Text("Запуск…")
                .font(.system(size: 13, weight: .medium))
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch workerState {
        case .ready:
            Text("Зажмите ⌥ и говорите")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloadingModel:
            Text("~892 МБ, один раз")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error:
            VStack(alignment: .leading, spacing: 4) {
                Text("Мы попробуем исправить это автоматически")
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

