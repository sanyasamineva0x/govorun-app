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
                VStack(alignment: .leading, spacing: 32) {
                    SectionPageHeader(section: selectedSection)

                    switch selectedSection {
                    case .general:
                        GeneralSettingsContent()
                    case .dictionary:
                        DictionaryView()
                    case .snippets:
                        SnippetListView()
                    case .history:
                        HistoryView()
                    case .textStyle:
                        TextStyleSettingsContent(selectedSection: $selectedSection)
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
                    .foregroundStyle(Color.sage)
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
                    colors: [Color.sage.opacity(0.04), Color.clear],
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
        if isSelected { return Color.ink.opacity(0.06) }
        if isHovered { return Color.primary.opacity(0.06) }
        return Color.clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Accent bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.ink)
                    .frame(width: 3, height: 16)
                    .opacity(isSelected ? 1 : 0)
                    .padding(.trailing, 8)

                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.ink : .secondary)
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
            // Статус worker
            WorkerStatusLine(workerState: appState.workerState)
                .staggeredAppear(index: 0)

            // Горячая клавиша
            KeyRecorderView(store: appState.settings)
                .staggeredAppear(index: 1)

            ProductModeCard(selection: settingsBinding(\.productMode))
                .staggeredAppear(index: 2)

            Divider().foregroundStyle(Color.mist)

            // Поведение
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Поведение")
                    .padding(.bottom, 12)

                // Режим работы
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.and.hand.point.up.left")
                        .font(.body)
                        .foregroundStyle(Color.sage.opacity(0.7))
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Режим работы")
                            .font(.body)
                        Text(appState.settings.recordingMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.ink.opacity(0.5))
                    }

                    Spacer()

                    Picker("", selection: settingsBinding(\.recordingMode)) {
                        ForEach(RecordingMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(.vertical, 6)

                SettingsToggleRow(
                    title: "Точка в конце фразы",
                    description: "Ставить точку в конце фразы",
                    icon: "smallcircle.filled.circle",
                    isOn: settingsBinding(\.terminalPeriodEnabled)
                )
                .padding(.vertical, 6)

                SettingsToggleRow(
                    title: "Звуки",
                    description: "Звуковой сигнал начала и конца записи",
                    icon: "speaker.wave.2",
                    isOn: settingsBinding(\.soundEnabled)
                )
                .padding(.vertical, 6)

                SettingsToggleRow(
                    title: "Автозапуск",
                    description: "Запуск Говоруна при включении компьютера",
                    icon: "power",
                    iconColor: .sage,
                    isOn: settingsBinding(\.launchAtLogin)
                )
                .padding(.vertical, 6)

                SettingsToggleRow(
                    title: "История записей",
                    description: "Хранить аудио на компьютере",
                    icon: "waveform",
                    iconColor: .sage,
                    isOn: settingsBinding(\.saveAudioHistory)
                )
                .padding(.vertical, 6)
            }
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
        case .installed, .unknown, .checking, .modelMissing, .error:
            true
        case .runtimeMissing:
            false
        }
    }

    private var assetsStatusText: String? {
        switch appState.superAssetsState {
        case .unknown, .checking:
            "Проверяю готовность Super..."
        case .installed, .modelMissing:
            nil
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

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes)/1_000_000_000
        return String(format: "%.1f ГБ", gb)
    }

    @ViewBuilder
    private var downloadStatusView: some View {
        switch appState.superAssetsState {
        case .runtimeMissing:
            EmptyView()

        case .installed:
            Label("Я готов к работе в Супер-режиме", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.sage)

        case .error(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Label("Не могу запустить Супер-режим", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Проверить снова") {
                        Task { await appState.handleSuperAssetsChanged() }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    if appState.superModelFileExists {
                        Button("Удалить и скачать заново") {
                            Task { await appState.deleteCorruptedModelAndRedownload() }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }

        case .unknown, .checking:
            EmptyView()

        case .modelMissing:
            switch appState.superModelDownloadState {
            case .idle:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Мне нужна ИИ-модель", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Чтобы я мог работать в Супер-режиме, скачайте ИИ-модель (5.8 ГБ). Это может занять 5–30 минут.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Скачать ИИ-модель") {
                        Task { await appState.startSuperModelDownload() }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }

            case .checkingExisting:
                Label("Проверяю...", systemImage: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .downloading(let progress, let downloadedBytes, let totalBytes):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Скачиваю ИИ-модель... \(formatBytes(downloadedBytes)) из \(formatBytes(totalBytes)) (\(Int(progress * 100))%)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Button("Отменить") {
                        appState.cancelSuperModelDownload()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

            case .verifying:
                Label("Проверяю целостность файла...", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .completed:
                Label("Я готов к работе в Супер-режиме", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.sage)

            case .failed(let error):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Не удалось скачать", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    if let desc = error.errorDescription {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if case .integrityCheckFailed = error {
                        Button("Скачать заново") {
                            appState.clearPartialSuperModelDownload()
                            Task { await appState.startSuperModelDownload() }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    } else {
                        Button("Продолжить скачивание") {
                            Task { await appState.startSuperModelDownload() }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }

            case .cancelled:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Скачивание отменено", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Продолжить") {
                            Task { await appState.startSuperModelDownload() }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        Button("Удалить") {
                            appState.clearPartialSuperModelDownload()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }

            case .partialReady(let downloadedBytes, let totalBytes):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Скачано \(formatBytes(downloadedBytes)) из \(formatBytes(totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Продолжить") {
                            Task { await appState.startSuperModelDownload() }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        Button("Удалить") {
                            appState.clearPartialSuperModelDownload()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Режим Говоруна")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let assetsText = assetsStatusText {
                        Label(assetsText, systemImage: assetsStatusIcon)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(descriptionText)
                            .font(.caption)
                            .foregroundStyle(Color.ink.opacity(0.5))
                    }
                }

                Spacer()

                Picker("", selection: $selection) {
                    ForEach(ProductMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .onChange(of: selection) { _, newValue in
                    if newValue == .superMode, !superAvailable {
                        selection = .standard
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                // ВАЖНО: settings.productMode (выбранный в picker), НЕ effectiveProductMode
                if appState.settings.productMode == .superMode {
                    downloadStatusView
                }
            }
        }
        .onAppear {
            Task {
                await appState.refreshSuperAssetsReadiness()
            }
        }
    }

    private var descriptionText: String {
        let base = selection.subtitle
        if appState.effectiveProductMode != selection {
            return "\(base). \(appState.effectiveProductMode.title) активен сейчас."
        }
        return base
    }
}

// MARK: - Строка статуса

private struct WorkerStatusLine: View {
    @EnvironmentObject private var appState: AppState
    let workerState: WorkerState

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            statusText
                .font(.system(size: 13, weight: .medium))

            Spacer()

            if case .downloadingModel(let progress) = workerState {
                ProgressView(value: Double(progress), total: 100)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Button("Отменить") {
                    appState.cancelWorkerLoading()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }

            if case .error = workerState {
                Button("Перезапустить") {
                    appState.retryWorkerLoading()
                }
                .font(.caption)
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch workerState {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.sage)
        case .downloadingModel:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14))
                .foregroundStyle(Color.sage)
        case .loadingModel, .settingUp, .notStarted:
            ProgressView()
                .scaleEffect(0.6)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.ember)
        }
    }

    private var statusText: some View {
        switch workerState {
        case .ready:
            Text("Говорун готов к работе")
                .foregroundStyle(Color.ink.opacity(0.5))
        case .downloadingModel(let progress):
            Text("Качаю модель… \(progress)%")
                .foregroundStyle(Color.ink.opacity(0.5))
        case .loadingModel:
            Text("Загружаю модель…")
                .foregroundStyle(Color.ink.opacity(0.5))
        case .error(let msg):
            Text(ErrorMessages.humanReadable(msg))
                .foregroundStyle(Color.ember)
        case .settingUp:
            Text("Готовлюсь…")
                .foregroundStyle(Color.ink.opacity(0.5))
        case .notStarted:
            Text("Запуск…")
                .foregroundStyle(Color.ink.opacity(0.5))
        }
    }
}
