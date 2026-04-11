import SwiftUI

// MARK: - Adaptive Color Helper

extension Color {
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(dark)
            }
            return NSColor(light)
        })
    }
}

// MARK: - Фирменные цвета v2

extension Color {
    /// Snow #FEFEFE — основной фон
    static let snow = Color(red: 254/255, green: 254/255, blue: 254/255)
    /// Mist — разделители, бордеры (адаптивный)
    static let mist = Color(light: Color(red: 240/255, green: 238/255, blue: 236/255),
                            dark: Color.white.opacity(0.08))
    /// Ink #1B1917 — текст, кнопки
    static let ink = Color(red: 27/255, green: 25/255, blue: 23/255)
    /// Sage #3D7B6E — waveform, статус
    static let sage = Color(red: 61/255, green: 123/255, blue: 110/255)
    /// Ember #C85046 — ошибки
    static let ember = Color(red: 200/255, green: 80/255, blue: 70/255)
}

// MARK: - Типографика

extension Font {
    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        switch weight {
        case .semibold:
            .custom("SourceSerif4Variable-Roman", size: size).weight(.semibold)
        default:
            .custom("SourceSerif4Variable-Roman", size: size).weight(.bold)
        }
    }
}

// MARK: - Секции настроек

enum SettingsSection: String, Identifiable {
    case general
    case dictionary
    case snippets
    case history
    case textStyle

    var id: String {
        rawValue
    }

    /// Секции видимые в UI
    static let visibleCases: [SettingsSection] = [.general, .textStyle, .dictionary, .snippets, .history]

    var title: String {
        switch self {
        case .general: "Основные"
        case .dictionary: "Словарь"
        case .snippets: "Команды"
        case .history: "История"
        case .textStyle: "Стиль текста"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Основные настройки Говоруна"
        case .dictionary: "Слова для точного распознавания"
        case .snippets: "Голосовые команды для быстрой вставки текста"
        case .history: "История ваших записей"
        case .textStyle: "Настройка стиля для Супер-режима"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .dictionary: "character.book.closed"
        case .snippets: "text.bubble"
        case .history: "clock.arrow.circlepath"
        case .textStyle: "textformat"
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
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.sage.opacity(0.7))

                Text(section.title)
                    .font(.serif(28))
                    .tracking(-0.8)
            }

            Text(section.subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.ink.opacity(0.38))

            // Accent line
            Rectangle()
                .fill(Color.mist)
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
    }
}

extension View {
    func settingsCard() -> some View {
        modifier(SettingsCardModifier())
    }
}

// MARK: - StatusDot

struct StatusDot: View {
    let title: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Color.sage : Color.mist)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.ink.opacity(0.5))
        }
    }
}

// MARK: - Заголовок секции

struct SectionHeader: View {
    let title: String
    var icon: String?

    var body: some View {
        Text(title)
            .font(.serif(18, weight: .semibold))
            .tracking(-0.2)
            .padding(.top, 16)
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
                .font(.system(size: 26))
                .foregroundStyle(Color.ink.opacity(0.12))

            Text(title)
                .font(.serif(17, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(.secondary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.ink.opacity(0.38))
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .foregroundStyle(style == .primary ? .white : Color.ink.opacity(0.5))
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(style == .primary ? Color.ink : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Group {
                        if style == .secondary {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.mist, lineWidth: 1)
                        }
                    }
                )
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
                .foregroundStyle(Color.ink.opacity(0.25))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.ink.opacity(0.25))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.mist)
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
            .foregroundStyle(Color.ink.opacity(0.38))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.mist)
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
                .foregroundStyle(Color.ink.opacity(isHovered ? 0.8 : 0.5))
                .font(.title3)
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
    var iconColor: Color = .sage
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
                    .foregroundStyle(Color.ink.opacity(0.5))
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Color.ink)
        }
    }
}
