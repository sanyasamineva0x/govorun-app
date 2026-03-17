import SwiftUI

// MARK: - Настройки режимов приложений

struct AppModeSettingsView: View {
    private let modeOverrides: AppModeOverriding

    @State private var overrides: [AppModeEntry] = []

    @State private var newBundleId = ""
    @State private var newMode: TextMode = .universal

    init(modeOverrides: AppModeOverriding = UserDefaultsAppModeOverrides()) {
        self.modeOverrides = modeOverrides
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Список переопределений
            if overrides.isEmpty {
                BrandedEmptyState(
                    icon: "app.badge",
                    title: "Нет переопределений",
                    subtitle: "Говорун сам подберёт режим\nдля каждого приложения"
                )
            } else {
                VStack(spacing: 2) {
                    ForEach($overrides) { $entry in
                        HStack {
                            Image(systemName: "app")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .frame(width: 20)
                            Text(entry.bundleId)
                                .font(.body)
                                .lineLimit(1)
                            Spacer()
                            ModePicker(selection: $entry.mode)
                                .onChange(of: entry.mode) { _, newMode in
                                    modeOverrides.setModeOverride(newMode.rawValue, for: entry.bundleId)
                                }

                            Button(action: {
                                modeOverrides.setModeOverride(nil, for: entry.bundleId)
                                loadOverrides()
                            }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Удалить")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                HStack {
                    Spacer()
                    Button(action: { resetOverrides() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                            Text("Сбросить все")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(overrides.isEmpty)
                }
            }

            // Добавление нового
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Добавить переопределение")

                HStack {
                    TextField("Bundle ID (com.example.app)", text: $newBundleId)
                        .textFieldStyle(.roundedBorder)

                    ModePicker(selection: $newMode)

                    AddButton(help: "Добавить") {
                        addOverride()
                    }
                    .disabled(newBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newBundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
            }
            .settingsCard()
        }
        .onAppear { loadOverrides() }
    }

    // MARK: - Private

    private func loadOverrides() {
        let dict = modeOverrides.allOverrides()
        overrides = dict.compactMap { (bundleId, rawMode) in
            guard let mode = TextMode(rawValue: rawMode) else { return nil }
            return AppModeEntry(bundleId: bundleId, mode: mode)
        }
        .sorted { $0.bundleId < $1.bundleId }
    }

    private func addOverride() {
        let trimmed = newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        modeOverrides.setModeOverride(newMode.rawValue, for: trimmed)
        newBundleId = ""
        newMode = .universal
        loadOverrides()
    }

    private func resetOverrides() {
        for entry in overrides {
            modeOverrides.setModeOverride(nil, for: entry.bundleId)
        }
        loadOverrides()
    }
}

// MARK: - Кастомный Picker режима

private struct ModePicker: View {
    @Binding var selection: TextMode

    var body: some View {
        Menu {
            ForEach(TextMode.allCases, id: \.self) { mode in
                Button(action: { selection = mode }) {
                    HStack {
                        Text(modeName(mode))
                        if selection == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(modeName(selection))
                    .font(.callout)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func modeName(_ mode: TextMode) -> String {
        switch mode {
        case .chat: "Чат"
        case .email: "Почта"
        case .document: "Документ"
        case .note: "Заметки"
        case .code: "Код"
        case .universal: "Универсальный"
        }
    }
}

// MARK: - Модель записи

struct AppModeEntry: Identifiable {
    let id = UUID()
    let bundleId: String
    var mode: TextMode
}
