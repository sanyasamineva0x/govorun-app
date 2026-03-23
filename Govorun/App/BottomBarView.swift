import SwiftUI

// MARK: - BottomBarView

struct BottomBarView: View {
    @ObservedObject var controller: BottomBarController
#if compiler(>=6.2)
    @Namespace private var pillNamespace
#endif

    var body: some View {
        TimelineView(.animation(paused: !isRecording)) { timeline in
            let phase = isRecording ? timeline.date.timeIntervalSinceReferenceDate : 0
            pillContent(phase: phase)
        }
    }

    @ViewBuilder
    private func pillContent(phase: Double) -> some View {
        ZStack {
            // State-specific tint overlay
            stateTint
                .clipShape(OrganicPillShape(
                    amplitude: CGFloat(audioLevel) * 3.0,
                    phase: phase,
                    frequency: 3.0
                ))
                .animation(.easeInOut(duration: 0.5), value: controller.state.tintKey)

            // Content с мягким crossfade
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
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: controller.state.tintKey)
        }
        .frame(width: currentWidth, height: BottomBarMetrics.pillHeight)
        .clipShape(OrganicPillShape(
            amplitude: CGFloat(audioLevel) * 3.0,
            phase: phase,
            frequency: 3.0
        ))
        .scaleEffect(scaleFactor)
        .animation(.spring(duration: 0.5, bounce: 0.15), value: currentWidth)
        .animation(.spring(duration: 0.15, bounce: 0.2), value: audioLevel)
#if compiler(>=6.2)
        .modifier(LiquidGlassPillModifier(namespace: pillNamespace))
#endif
    }

    private var isRecording: Bool {
        if case .recording = controller.state { return true }
        return false
    }

    // Текущий audio level (clamped 0–1, 0 для не-recording)
    private var audioLevel: Float {
        if case .recording(let level) = controller.state {
            return min(max(level, 0), 1)
        }
        return 0
    }

    // #2: scale breathing (заметная пульсация)
    private var scaleFactor: CGFloat {
        1.0 + CGFloat(audioLevel) * 0.06
    }

    // #3: ширина pill зависит от состояния (morphing)
    private var currentWidth: CGFloat {
        switch controller.state {
        case .processing: return 180
        case .error: return 280
        default: return BottomBarMetrics.pillWidth
        }
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

// MARK: - OrganicPillShape

/// Органическая форма pill с мягкими колебаниями контура.
/// Контур: quad Bézier curves с синусоидальными perturbations.
/// Полукруги строятся через Bézier (не arc) для бесшовного соединения.
/// При amplitude ≈ 0 — плавная деградация в capsule (нет threshold snap).
struct OrganicPillShape: Shape {
    var amplitude: CGFloat
    var phase: Double
    var frequency: Double

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(amplitude, CGFloat(phase)) }
        set {
            amplitude = newValue.first
            phase = Double(newValue.second)
        }
    }

    // Фиксированные seed offsets для каждой control point
    private static let seeds: [Double] = [
        0.0, 1.7, 3.2, 0.8, 2.4, 4.1, 1.3, 5.0,
        2.9, 0.5, 3.7, 1.1, 4.6, 2.0, 5.5, 3.4,
        0.3, 4.2, 1.9, 5.8, 2.7, 0.9, 3.6, 4.8,
    ]

    // Множитель аппроксимации дуги кубическим Bézier: (4/3)*tan(π/8)
    private static let arcK: CGFloat = 0.5522847498

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let r = h / 2

        var path = Path()

        // Верхняя линия (слева направо): от (r, 0) до (w-r, 0)
        let topSegments = 6
        let topStep = (w - 2 * r) / CGFloat(topSegments)

        let topStart = CGPoint(x: r, y: perturb(0, base: 0))
        path.move(to: topStart)

        for i in 1...topSegments {
            let x = r + topStep * CGFloat(i)
            let y = perturb(i, base: 0)
            let cpX = r + topStep * (CGFloat(i) - 0.5)
            let cpY = perturb(i + topSegments, base: 0)
            path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cpX, y: cpY))
        }

        // Правый полукруг (Bézier): от (w-r, top) → (w, mid) → (w-r, bottom)
        let rTopY = perturb(topSegments, base: 0)
        let rBotY = h + perturb(12, base: 0)
        let rMidX = w - r + r + perturb(14, base: 0) * 0.3
        let cx = CGPoint(x: w - r, y: h / 2)
        let k = OrganicPillShape.arcK

        path.addCurve(
            to: CGPoint(x: cx.x + r, y: cx.y),
            control1: CGPoint(x: w - r + k * perturb(15, base: r), y: rTopY),
            control2: CGPoint(x: rMidX, y: cx.y - r * k)
        )
        path.addCurve(
            to: CGPoint(x: w - r, y: rBotY),
            control1: CGPoint(x: rMidX, y: cx.y + r * k),
            control2: CGPoint(x: w - r + k * perturb(16, base: r), y: rBotY)
        )

        // Нижняя линия (справа налево): от (w-r, h) до (r, h)
        for i in 1...topSegments {
            let x = w - r - topStep * CGFloat(i)
            let y = h + perturb(i + 12, base: 0)
            let cpX = w - r - topStep * (CGFloat(i) - 0.5)
            let cpY = h + perturb(i + 18, base: 0)
            path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cpX, y: cpY))
        }

        // Левый полукруг (Bézier): от (r, bottom) → (0, mid) → (r, top)
        let lBotY = h + perturb(topSegments + 12, base: 0)
        let lTopY = perturb(0, base: 0) // совпадает с startTop
        let lMidX = r - r - perturb(20, base: 0) * 0.3
        let lc = CGPoint(x: r, y: h / 2)

        path.addCurve(
            to: CGPoint(x: lc.x - r, y: lc.y),
            control1: CGPoint(x: r - k * perturb(21, base: r), y: lBotY),
            control2: CGPoint(x: lMidX, y: lc.y + r * k)
        )
        path.addCurve(
            to: topStart,
            control1: CGPoint(x: lMidX, y: lc.y - r * k),
            control2: CGPoint(x: r - k * perturb(22, base: r), y: lTopY)
        )

        path.closeSubpath()
        return path
    }

    private func perturb(_ index: Int, base: CGFloat) -> CGFloat {
        let seed = OrganicPillShape.seeds[index % OrganicPillShape.seeds.count]
        return base + amplitude * CGFloat(sin(frequency * Double(index) + phase * 2.0 + seed))
    }
}

// MARK: - Liquid Glass pill modifier

#if compiler(>=6.2)
struct LiquidGlassPillModifier: ViewModifier {
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                content
                    .glassEffect(.clear, in: .capsule)
                    .glassEffectID("pill", in: namespace)
            }
        } else {
            content
        }
    }
}
#endif
