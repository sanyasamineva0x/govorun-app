# Liquid Pill — живой анимированный pill

## Цель

Сделать pill записи «жидким» — он дышит, пульсирует, меняет форму в такт аудио. На macOS 26 glass преломляется при движении.

## Текущее состояние

- `BottomBarView.swift` — SwiftUI view внутри borderless NSPanel
- `BottomBarWindow.swift` — NSPanel с NSVisualEffectView (legacy) или чистый hosting (macOS 26)
- Pill: статичная `Capsule()` 260×44, внутри waveform bars
- Glass: `.glassEffect(.clear, in: .capsule)` через `GlassPillModifier`
- Анимация: только bars внутри pill, сам контур статичен

## 4 эффекта

### 1. Дышащая форма (breathing shape)

Контур pill слегка пульсирует в такт audioLevel. Не bars внутри — сама форма «дышит».

**Реализация:**
- Кастомный `Shape` вместо `Capsule` — `BreathingPillShape`
- Sine-wave perturbations на контуре: `y += amplitude * sin(x * frequency + phase)`
- `amplitude` привязана к `audioLevel` (0 → 0pt, 1 → 2pt)
- `phase` анимируется через `TimelineView(.animation)` для плавного движения волны
- Применяется как `.clipShape(BreathingPillShape(...))` на ZStack pill'а

**Параметры:**
- `amplitude`: `CGFloat(audioLevel) * 2.0` (максимум 2pt отклонения)
- `frequency`: 3.0 (3 волны по длине pill)
- `phase`: непрерывно растёт с `TimelineView`
- `smoothing`: `.spring(duration: 0.15)` на amplitude чтобы не дёргалось

**Файл:** `BottomBarView.swift` — новый `struct BreathingPillShape: Shape`

### 2. Scale breathing

Subtle масштабирование всего pill на пиках аудио. Glass при масштабировании пересемплирует фон — видно как преломление «сдвигается».

**Реализация:**
- `.scaleEffect(scaleFactor)` на ZStack pill'а
- `scaleFactor = 1.0 + CGFloat(audioLevel) * 0.03` (максимум 1.03)
- `.animation(.spring(duration: 0.12, bounce: 0.2), value: audioLevel)`
- Только для `.recording` состояния, для остальных `scaleEffect(1.0)`

**Файл:** `BottomBarView.swift` — модификатор на ZStack

### 3. Glass morphing между состояниями

Pill плавно трансформируется при смене состояния: recording → processing → done. Используем `.glassEffectID` + `@Namespace`.

**Реализация (только macOS 26):**
```swift
@Namespace private var pillNamespace

// В body:
GlassEffectContainer {
    ZStack {
        // content...
    }
    .frame(width: currentWidth, height: BottomBarMetrics.pillHeight)
    .glassEffect(.clear, in: .capsule)
    .glassEffectID("pill", in: pillNamespace)
}
```

- `currentWidth`: recording = 260, processing = 180, error = 280
- Переход между размерами с `.animation(.spring(duration: 0.4, bounce: 0.2))`
- Glass автоматически морфит при изменении frame

**Fallback macOS 14-15:** обычный `.frame` transition без glass morphing

**Файл:** `BottomBarView.swift` — `@Namespace`, `GlassEffectContainer`, `currentWidth` computed property

### 4. Organic blob

Вместо идеальной капсулы — органическая форма с мягкими колебаниями. Metaball-подобная.

**Реализация:**
- `struct OrganicPillShape: Shape` с `func path(in rect:) -> Path`
- Контур строится через cubic Bézier curves с control points
- Control points смещаются на `offset = amplitude * sin(angle * freq + phase + seed[i])`
- `seed[i]` — фиксированные random offsets для каждой control point (чтобы не все двигались синхронно)
- `amplitude` = `audioLevel * 1.5`
- `phase` = `TimelineView` continuous
- При `audioLevel == 0` (не recording) → чистая capsule (amplitude = 0)

**Path построение:**
```
1. Начало: левый полукруг (8 control points)
2. Верхняя линия (4 control points с perturbation)
3. Правый полукруг (8 control points)
4. Нижняя линия (4 control points с perturbation)
```

Каждая control point: `base + perturbation(phase, seed)`

**Файл:** `BottomBarView.swift` — новый `struct OrganicPillShape: Shape`

## Интеграция в BottomBarView

```swift
struct BottomBarView: View {
    @ObservedObject var controller: BottomBarController
    @Namespace private var pillNamespace

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                stateTint
                    .clipShape(pillShape(phase: phase))

                // Content (recording bars, processing, etc.)
                ...
            }
            .frame(width: currentWidth, height: BottomBarMetrics.pillHeight)
            .scaleEffect(scaleFactor)  // #2 scale breathing
            .animation(.spring(duration: 0.12, bounce: 0.2), value: audioLevel)
            #if compiler(>=6.2)
            .modifier(LiquidGlassPillModifier(namespace: pillNamespace))
            #endif
        }
    }

    // Текущий audio level (0 для не-recording состояний)
    private var audioLevel: Float {
        if case .recording(let level) = controller.state { return level }
        return 0
    }

    // #2: scale breathing
    private var scaleFactor: CGFloat {
        1.0 + CGFloat(audioLevel) * 0.03
    }

    // #3: ширина pill зависит от состояния (morphing)
    private var currentWidth: CGFloat {
        switch controller.state {
        case .processing: return 180
        case .error: return 280
        default: return BottomBarMetrics.pillWidth  // 260
        }
    }

    // #1 + #4: выбор формы
    private func pillShape(phase: Double) -> some Shape {
        OrganicPillShape(
            amplitude: CGFloat(audioLevel) * 1.5,
            phase: phase,
            frequency: 3.0
        )
    }
}
```

## Порядок реализации

1. `OrganicPillShape` — Shape с perturbations (#1 + #4 объединены)
2. `scaleEffect` на pill (#2)
3. `TimelineView(.animation)` обёртка для continuous phase
4. `@Namespace` + `GlassEffectContainer` + `glassEffectID` для morphing (#3, только macOS 26)
5. `currentWidth` computed property для morphing размеров
6. Обновить `GlassPillModifier` для работы с namespace

## Параметры для тюнинга

| Параметр | Значение | Диапазон | Эффект |
|----------|----------|----------|--------|
| Amplitude (shape) | audioLevel × 1.5 | 0–1.5pt | Сила колебаний контура |
| Scale factor | 1 + audioLevel × 0.03 | 1.0–1.03 | Пульсация размера |
| Frequency | 3.0 | 2–5 | Количество волн по контуру |
| Phase speed | realtime (TimelineView) | — | Скорость движения волны |
| Processing width | 180pt | 140–200 | Компактность при обработке |
| Spring duration | 0.4s | 0.2–0.6 | Скорость morphing |
| Spring bounce | 0.2 | 0–0.4 | Упругость morphing |

## Ограничения

- `TimelineView(.animation)` работает на 60fps — следить за CPU usage
- `OrganicPillShape` пересчитывает path каждый frame — должен быть легковесным
- Glass morphing (`glassEffectID`) только macOS 26, fallback — обычный frame transition
- Organic shape не должен мешать читаемости текста внутри pill
- При `audioLevel == 0` (не recording) — все эффекты off, чистая capsule

## Тестирование

- Визуальное: запись 5-30 сек, проверить плавность на M1
- CPU: Activity Monitor во время записи — не должно превышать 5% на анимацию
- States: проверить все 7 состояний pill (hidden, recording, processing, modelLoading, modelDownloading, accessibilityHint, error)
- Morphing: переход recording → processing → idle, проверить плавность
- Fallback: собрать на Xcode 16, проверить что без glass всё работает
