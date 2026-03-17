import SwiftUI

// MARK: - Фирменные цвета (SwiftUI)

extension Color {
    /// Cotton Candy #B36A5E — основной акцент
    static let cottonCandy = Color(red: 179/255, green: 106/255, blue: 94/255)
    /// Sky Aqua #0ACDFF — обработка
    static let skyAqua = Color(red: 10/255, green: 205/255, blue: 255/255)
    /// Ocean Mist #60AB9A — success
    static let oceanMist = Color(red: 96/255, green: 171/255, blue: 154/255)
    /// Petal Frost #FBDCE2 — мягкий фон
    static let petalFrost = Color(red: 251/255, green: 220/255, blue: 226/255)
    /// Alabaster Grey #DEDEE0 — нейтральный
    static let alabasterGrey = Color(red: 222/255, green: 222/255, blue: 224/255)
}

// MARK: - Секции настроек

enum SettingsSection: String, Identifiable {
    case general
    case appModes  // Скрыт до Фазы 5 (LocalLLMClient) — TextMode без LLM не работает
    case dictionary
    case snippets
    case history

    var id: String { rawValue }

    /// Секции видимые в UI (appModes скрыт до Фазы 5)
    static let visibleCases: [SettingsSection] = [.general, .dictionary, .snippets, .history]

    var title: String {
        switch self {
        case .general: "Основные"
        case .appModes: "Приложения"
        case .dictionary: "Словарь"
        case .snippets: "Команды"
        case .history: "История"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Основные настройки Говоруна"
        case .appModes: "Настройка режимов для конкретных приложений"
        case .dictionary: "Слова и термины для точного распознавания"
        case .snippets: "Голосовые команды для быстрой вставки текста"
        case .history: "История ваших записей"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .appModes: "app.badge"
        case .dictionary: "character.book.closed"
        case .snippets: "text.bubble"
        case .history: "clock.arrow.circlepath"
        }
    }
}

// MARK: - Page Header

struct SectionPageHeader: View {
    let section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.cottonCandy)

                Text(section.title)
                    .font(.system(size: 20, weight: .semibold))
            }

            Text(section.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Accent line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.cottonCandy.opacity(0.5), Color.cottonCandy.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.top, 4)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Карточка секции

struct SettingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.background.opacity(0.8))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.alabasterGrey.opacity(0.2), lineWidth: 1)
            )
    }
}

extension View {
    func settingsCard() -> some View {
        modifier(SettingsCardModifier())
    }
}

// MARK: - Карточка со статусной полоской

struct StatusCardModifier: ViewModifier {
    let accentColor: Color

    func body(content: Content) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 12)

            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background.opacity(0.8))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.alabasterGrey.opacity(0.2), lineWidth: 1)
        )
    }
}

extension View {
    func statusCard(accent: Color) -> some View {
        modifier(StatusCardModifier(accentColor: accent))
    }
}

// MARK: - Заголовок секции

struct SectionHeader: View {
    let title: String
    var icon: String?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Branded Empty State

struct BrandedEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 24)

            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Color.cottonCandy.opacity(0.8))

            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.cottonCandy)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer().frame(height: 24)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Branded Button

struct BrandedButton: View {
    let title: String
    let style: Style
    let action: () -> Void

    enum Style {
        case primary
        case secondary
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(style == .primary ? .white : Color.cottonCandy)
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(style == .primary ? Color.cottonCandy : Color.cottonCandy.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Bar

struct SettingsSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Поиск…"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(.tertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.alabasterGrey.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Staggered appear

struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35).delay(min(Double(index) * 0.08, 0.8))) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggeredAppear(index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

// MARK: - Бейдж-счётчик

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.alabasterGrey.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Add Button (with hover)

struct AddButton: View {
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.cottonCandy)
                .font(.title3)
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .opacity(isHovered ? 1.0 : 0.85)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Toggle Row

struct SettingsToggleRow: View {
    let title: String
    let description: String
    let icon: String
    var iconColor: Color = .cottonCandy
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor.opacity(0.7))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
