import SwiftUI

// MARK: - Таб: Стиль текста

struct TextStyleSettingsContent: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedSection: SettingsSection

    private func settingsBinding<T>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { appState.settings[keyPath: keyPath] = $0 }
        )
    }

    private var modelAvailable: Bool {
        appState.superAssetsState == .installed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Режим стиля — сегментированный переключатель (всегда активен)
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Режим стиля", icon: "textformat")

                Picker("", selection: settingsBinding(\.superStyleMode)) {
                    ForEach(SuperStyleMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .settingsCard()
            .staggeredAppear(index: 0)

            // Контент с оверлеем при отсутствии модели
            ZStack {
                Group {
                    if appState.settings.superStyleMode == .auto {
                        Text("Стиль определяется автоматически по приложению")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .settingsCard()
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(SuperTextStyle.allCases.enumerated()), id: \.element) { index, style in
                                StyleCard(
                                    style: style,
                                    isSelected: appState.settings.manualSuperStyle == style,
                                    action: { appState.settings.manualSuperStyle = style }
                                )
                                .staggeredAppear(index: index + 1)
                            }
                        }
                    }
                }
                .opacity(modelAvailable ? 1.0 : 0.4)
                .blur(radius: modelAvailable ? 0 : 1)
                .disabled(!modelAvailable)
                .allowsHitTesting(modelAvailable)
                .animation(.easeInOut(duration: 0.2), value: appState.settings.superStyleMode)

                if !modelAvailable {
                    ModelMissingOverlay(
                        assetsState: appState.superAssetsState,
                        onNavigateToGeneral: { selectedSection = .general }
                    )
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: modelAvailable)
                }
            }
            .staggeredAppear(index: 1)
        }
    }
}

// MARK: - Карточка стиля

private struct StyleCard: View {
    let style: SuperTextStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(style.displayName)
                        .font(.callout.weight(.medium))
                    Text(style.cardDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.cottonCandy)
                    .font(.title3)
                    .opacity(isSelected ? 1 : 0)
            }
            .settingsCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Оверлей: модель не установлена

private struct ModelMissingOverlay: View {
    let assetsState: SuperAssetsState
    let onNavigateToGeneral: () -> Void

    private var heading: String {
        switch assetsState {
        case .runtimeMissing:
            "Требуется llama-server"
        case .error:
            "Ошибка загрузки модели"
        default:
            "Для стилей нужна ИИ-модель"
        }
    }

    private var bodyText: String {
        switch assetsState {
        case .runtimeMissing:
            "Перейдите в «Основные» для переустановки"
        case .error:
            "Перейдите в «Основные» для повторной попытки"
        default:
            "Скачайте модель в разделе «Основные»"
        }
    }

    private var ctaText: String {
        switch assetsState {
        case .runtimeMissing, .error:
            "Перейти к настройкам"
        default:
            "Перейти к скачиванию"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(heading)
                .font(.callout.weight(.medium))

            Text(bodyText)
                .font(.caption)
                .foregroundStyle(.secondary)

            BrandedButton(title: ctaText, style: .primary) {
                onNavigateToGeneral()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
