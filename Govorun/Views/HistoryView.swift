import AVFoundation
import SwiftData
import SwiftUI

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
                    title: "Истории пока нет",
                    subtitle: "Ваши записи появятся здесь"
                )
            } else {
                HStack {
                    Text("\(items.count) из \(HistoryStore.maxItems)")
                        .font(.body)
                        .foregroundStyle(Color.ink.opacity(0.5))

                    Spacer()

                    Button(action: { showClearConfirmation = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.caption)
                            Text("Очистить")
                                .font(.callout.weight(.medium))
                        }
                        .foregroundStyle(Color.ink.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.mist)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HistoryRowView(item: item)
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
            Text("Ваши записи будут удалены навсегда")
        }
    }

    private func clearHistory() {
        for item in items {
            if let fileName = item.audioFileName {
                AudioHistoryStorage.deleteFile(named: fileName)
            }
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            print("Ошибка очистки истории: \(error)")
        }
    }
}

// MARK: - Строка истории

private struct HistoryRowView: View {
    let item: HistoryItem
    @State private var isPlaying = false
    @State private var isHovered = false
    @StateObject private var playbackDelegate = AudioPlaybackDelegate()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.normalizedText)
                    .font(.body)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Text(Self.dateFormatter.string(from: item.createdAt))
                        .font(.caption)
                        .foregroundStyle(Color.ink.opacity(0.4))

                    Text("\(item.totalLatencyMs)мс")
                        .font(.caption)
                        .foregroundStyle(Color.ink.opacity(0.25))
                }
            }

            Spacer()

            if item.audioFileName != nil {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(isPlaying ? Color.sage : Color.ink.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Остановить" : "Прослушать")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ink.opacity(isHovered ? 0.04 : 0))
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
            print("Ошибка воспроизведения: \(error)")
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
