import SwiftUI

// MARK: - BottomBarView

struct BottomBarView: View {
    @ObservedObject var controller: BottomBarController
    @State private var frozenPhase: Double = 0
#if compiler(>=6.2)
    @Namespace private var pillNamespace
#endif

    private var supportsLiquid: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    var body: some View {
        if supportsLiquid {
            liquidBody
        } else {
            legacyBody
        }
    }

    // MARK: - macOS 26+: liquid pill с organic shape, morphing, breathing

    private var liquidBody: some View {
        TimelineView(.animation(paused: !isRecording)) { timeline in
            let phase = isRecording
                ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: .pi * 2)
                : frozenPhase
            liquidPill(phase: phase)
        }
        .onChange(of: isRecording) { _, nowRecording in
            if !nowRecording {
                frozenPhase = Date().timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: .pi * 2)
            }
        }
    }

    @ViewBuilder
    private func liquidPill(phase: Double) -> some View {
        let shape = OrganicPillShape(
            amplitude: wobbleAmplitude,
            phase: phase,
            frequency: 3.0
        )

        ZStack {
            stateTint
                .clipShape(shape)
                .animation(.easeInOut(duration: 0.35), value: controller.state.tintKey)

            stateContent
        }
        .frame(width: currentWidth, height: BottomBarMetrics.pillHeight)
        .clipShape(shape)
        .scaleEffect(scaleFactor)
        // Shell breathing: spring на audioLevel для плавности между metering updates
        .animation(.spring(duration: 0.12, bounce: 0.15), value: audioLevel)
        // State transitions: width + scale + amplitude при смене состояния
        .animation(.spring(duration: 0.4, bounce: 0.1), value: controller.state.tintKey)
#if compiler(>=6.2)
        .modifier(LiquidGlassPillModifier(namespace: pillNamespace))
#endif
    }

    // MARK: - macOS 14-15: статичная capsule без timeline

    private var legacyBody: some View {
        ZStack {
            stateTint
                .clipShape(Capsule())
                .animation(.easeInOut(duration: 0.35), value: controller.state.tintKey)

            stateContent
        }
        .frame(width: BottomBarMetrics.pillWidth, height: BottomBarMetrics.pillHeight)
        .clipShape(Capsule())
    }

    // MARK: - Контент (общий для обоих путей)

    @ViewBuilder
    private var stateContent: some View {
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

    // MARK: - Derived state

    private var isRecording: Bool {
        if case .recording = controller.state { return true }
        return false
    }

    private var audioLevel: Float {
        if case .recording(let level) = controller.state {
            return min(max(level, 0), 1)
        }
        return 0
    }

    // Амплитуда колебаний контура
    private var wobbleAmplitude: CGFloat {
        CGFloat(audioLevel) * 3.0
    }

    // Пульсация размера: 0.03 по спеке
    private var scaleFactor: CGFloat {
        1.0 + CGFloat(audioLevel) * 0.03
    }

    // Morphing ширины
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

// MARK: - Ключ tint (для анимации)

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
        guard totalBars > 1 else {
            return max(2.5, CGFloat(audioLevel) * BottomBarMetrics.maxBarHeight)
        }
        let center = Double(totalBars - 1) / 2.0
        let distance = abs(Double(index) - center) / center
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

// MARK: - Processing: пульсирующие бары

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

// MARK: - Появление контента (общий модификатор)

struct PillContentAppearModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
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

// MARK: - Model Loading: информационный

struct ModelLoadingView: View {
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
        .modifier(PillContentAppearModifier())
    }
}

// MARK: - Model Downloading: прогресс скачивания

struct ModelDownloadingView: View {
    let progress: Int

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
        .modifier(PillContentAppearModifier())
    }
}

// MARK: - Accessibility Hint: мягкое напоминание

struct AccessibilityHintView: View {
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
        .modifier(PillContentAppearModifier())
    }
}

// MARK: - Error: мягкий, фирменный

struct ErrorView: View {
    let message: String

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
        .modifier(PillContentAppearModifier())
    }
}

// MARK: - OrganicPillShape

/// Органическая форма pill с мягкими колебаниями контура.
/// Контур: quad Bézier (прямые участки) + cubic Bézier (полукруги) с синусоидальными perturbations.
/// Полукруги строятся через Bézier (не arc) для бесшовного соединения.
/// При amplitude ≈ 0 — плавная деградация в capsule (нет threshold snap).
struct OrganicPillShape: Shape {
    var amplitude: CGFloat
    var phase: Double
    var frequency: Double

    // Только amplitude анимируется SwiftUI.
    // Phase управляется TimelineView (frozen при паузе) — не через animatableData.
    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
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

        guard w >= h, h > 0 else {
            return Path(roundedRect: rect, cornerRadius: min(w, h) / 2)
        }

        let r = h / 2

        var path = Path()

        // Верхняя линия (слева направо)
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

        // Правый полукруг (cubic Bézier)
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

        // Нижняя линия (справа налево)
        for i in 1...topSegments {
            let x = w - r - topStep * CGFloat(i)
            let y = h + perturb(i + 12, base: 0)
            let cpX = w - r - topStep * (CGFloat(i) - 0.5)
            let cpY = h + perturb(i + 18, base: 0)
            path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cpX, y: cpY))
        }

        // Левый полукруг (cubic Bézier)
        let lBotY = h + perturb(topSegments + 12, base: 0)
        let lTopY = perturb(0, base: 0)
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

// MARK: - Liquid Glass модификатор

#if compiler(>=6.2)
struct LiquidGlassPillModifier: ViewModifier {
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                content
                    .glassEffect(.clear, in: .capsule)
                    .glassEffectID("pill", in: namespace)
                    .clipShape(Capsule())
            }
        } else {
            content
        }
    }
}
#endif
