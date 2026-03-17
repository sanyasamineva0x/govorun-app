import SwiftUI
import SwiftData
import AVFoundation

struct HistoryView: View {
    @Query(sort: \HistoryItem.createdAt, order: .reverse)
    private var items: [HistoryItem]

    @Environment(\.modelContext) private var modelContext
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if items.isEmpty {
                BrandedEmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "История пуста",
                    subtitle: "Результаты голосового ввода\nпоявятся здесь"
                )
            } else {
                HStack {
                    Text("\(items.count) из \(HistoryStore.maxItems)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button(action: { showClearConfirmation = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.caption)
                            Text("Очистить")
                                .font(.callout.weight(.medium))
                        }
                        .foregroundStyle(Color.cottonCandy)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.cottonCandy.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HistoryRowView(item: item)
                                .settingsCard()
                                .staggeredAppear(index: index)
                        }
                    }
                }
            }
        }
        .alert("Очистить историю?", isPresented: $showClearConfirmation) {
            Button("Отмена", role: .cancel) {}
            Button("Очистить", role: .destructive) {
                clearHistory()
            }
        } message: {
            Text("Все записи и аудиофайлы будут удалены безвозвратно")
        }
    }

    private func clearHistory() {
        for item in items {
            if let fileName = item.audioFileName {
                AudioHistoryStorage.deleteFile(named: fileName)
            }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}

// MARK: - Строка истории

private struct HistoryRowView: View {
    let item: HistoryItem
    @State private var isPlaying = false
    @State private var isHovered = false
    @StateObject private var playbackDelegate = AudioPlaybackDelegate()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if item.audioFileName != nil {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(isPlaying ? Color.oceanMist : Color.cottonCandy)
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Остановить" : "Прослушать")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.normalizedText)
                    .font(.body)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Label(Self.dateFormatter.string(from: item.createdAt), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let appName = item.appName {
                        Label(appName, systemImage: "app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Label("\(item.totalLatencyMs)мс", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.cottonCandy.opacity(isHovered ? 0.06 : 0))
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Копировать") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.normalizedText, forType: .string)
            }
        }
        .onDisappear {
            playbackDelegate.stop()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            playbackDelegate.stop()
            isPlaying = false
            return
        }

        guard let fileName = item.audioFileName else { return }
        let url = AudioHistoryStorage.fileURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        playbackDelegate.play(url: url) {
            isPlaying = false
        }
        isPlaying = true
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f
    }()
}

// MARK: - Per-view делегат воспроизведения

@MainActor
private final class AudioPlaybackDelegate: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var onFinish: (() -> Void)?

    func play(url: URL, onFinish: @escaping () -> Void) {
        stop()
        self.onFinish = onFinish
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
        } catch {
            onFinish()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        onFinish = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.onFinish?()
            self?.player = nil
            self?.onFinish = nil
        }
    }
}
