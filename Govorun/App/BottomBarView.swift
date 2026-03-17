import SwiftUI

// MARK: - BottomBarView

struct BottomBarView: View {
    @ObservedObject var controller: BottomBarController

    var body: some View {
        ZStack {
            // State-specific tint overlay
            stateTint
                .clipShape(Capsule())
                .animation(.easeInOut(duration: 0.4), value: controller.state.tintKey)

            // Content
            Group {
                switch controller.state {
                case .hidden:
                    EmptyView()

                case .recording(let audioLevel):
                    RecordingView(audioLevel: audioLevel)

                case .processing:
                    ProcessingView()

                case .modelLoading:
                    ModelLoadingView()

                case .modelDownloading(let progress):
                    ModelDownloadingView(progress: progress)

                case .accessibilityHint:
                    AccessibilityHintView()

                case .error(let message):
                    ErrorView(message: message)
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.15), value: controller.state.tintKey)
        }
        .frame(
            width: BottomBarMetrics.pillWidth,
            height: BottomBarMetrics.pillHeight
        )
    }

    @ViewBuilder
    private var stateTint: some View {
        switch controller.state {
        case .hidden:
            Color.clear
        case .recording:
            Color(nsColor: BrandColors.cottonCandy).opacity(0.06)
        case .processing:
            Color(nsColor: BrandColors.skyAqua).opacity(0.04)
        case .modelLoading, .modelDownloading:
            Color(nsColor: BrandColors.skyAqua).opacity(0.04)
        case .accessibilityHint:
            Color(nsColor: BrandColors.oceanMist).opacity(0.06)
        case .error:
            Color(nsColor: BrandColors.cottonCandy).opacity(0.08)
        }
    }
}

// MARK: - State tint key (для анимации)

private extension BottomBarState {
    var tintKey: String {
        switch self {
        case .hidden: "hidden"
        case .recording: "recording"
        case .processing: "processing"
        case .modelLoading: "modelLoading"
        case .modelDownloading: "modelDownloading"
        case .accessibilityHint: "accessibilityHint"
        case .error: "error"
        }
    }
}

// MARK: - Recording: тёплая waveform

struct RecordingView: View {
    let audioLevel: Float

    var body: some View {
        HStack(spacing: BottomBarMetrics.barSpacing) {
            ForEach(0..<BottomBarMetrics.barCount, id: \.self) { index in
                WaveformBar(
                    audioLevel: audioLevel,
                    index: index,
                    totalBars: BottomBarMetrics.barCount
                )
            }
        }
        .frame(height: BottomBarMetrics.maxBarHeight)
    }
}

// MARK: - Waveform bar (плавный, с тёплым glow)

struct WaveformBar: View {
    let audioLevel: Float
    let index: Int
    let totalBars: Int

    var body: some View {
        RoundedRectangle(cornerRadius: BottomBarMetrics.barWidth / 2)
            .fill(Color(nsColor: BrandColors.cottonCandy))
            .frame(width: BottomBarMetrics.barWidth, height: barHeight)
            .shadow(
                color: Color(nsColor: BrandColors.cottonCandy)
                    .opacity(glowOpacity),
                radius: glowRadius
            )
            .animation(
                .spring(duration: 0.12, bounce: 0.2),
                value: audioLevel
            )
    }

    private var barHeight: CGFloat {
        let center = Double(totalBars - 1) / 2.0
        let distance = abs(Double(index) - center) / center
        // Мягкая арка: cos-envelope вместо линейной
        let envelope = cos(distance * .pi / 2)
        let level = max(0.06, Double(audioLevel))
        let height = level * envelope * BottomBarMetrics.maxBarHeight
        return max(2.5, CGFloat(height))
    }

    private var glowOpacity: Double {
        Double(max(0, audioLevel)) * 0.5
    }

    private var glowRadius: CGFloat {
        CGFloat(max(0, audioLevel)) * 3.5
    }
}

// MARK: - Processing: sequential pulsing bars

struct ProcessingView: View {
    private let barCount = 4
    @State private var activeIndex = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(nsColor: BrandColors.skyAqua))
                    .frame(width: 2.5, height: barHeight(for: index))
                    .opacity(barOpacity(for: index))
                    .shadow(
                        color: Color(nsColor: BrandColors.skyAqua)
                            .opacity(index == activeIndex ? 0.4 : 0),
                        radius: 3
                    )
                    .animation(
                        .easeInOut(duration: 0.3),
                        value: activeIndex
                    )
            }
        }
        .frame(height: 14)
        .onReceive(timer) { _ in
            activeIndex = (activeIndex + 1) % barCount
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        if index == activeIndex { return 14 }
        let distance = min(
            abs(index - activeIndex),
            barCount - abs(index - activeIndex)
        )
        return distance == 1 ? 9 : 5
    }

    private func barOpacity(for index: Int) -> Double {
        index == activeIndex ? 1.0 : 0.35
    }
}

// MARK: - Model Loading: информационный

struct ModelLoadingView: View {
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .scaleEffect(0.65)
                .tint(Color(nsColor: BrandColors.skyAqua))

            Text("Загружаю модель…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 3)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
        }
    }
}

// MARK: - Model Downloading: прогресс скачивания

struct ModelDownloadingView: View {
    let progress: Int

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 7) {
            ProgressView()
                .scaleEffect(0.65)
                .tint(Color(nsColor: BrandColors.skyAqua))

            Text("Качаю модель… \(progress)%")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 3)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
        }
    }
}

// MARK: - Accessibility Hint: мягкое напоминание

struct AccessibilityHintView: View {
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(Color(nsColor: BrandColors.oceanMist))
                .font(.system(size: 12, weight: .medium))

            Text("Включите Accessibility для точной вставки")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 3)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
        }
    }
}

// MARK: - Error: мягкий, фирменный

struct ErrorView: View {
    let message: String

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: BrandColors.cottonCandy))
                .font(.system(size: 12, weight: .medium))

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 3)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                appeared = true
            }
        }
    }
}
