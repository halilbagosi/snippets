import SwiftUI

struct DotGridBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var spacing: CGFloat = 22
    var dotSize: CGFloat = 1.4
    var gradientPalette: [Color] = []
    var lightModeStrength: Double = 1.0
    var focusedMode: Bool = false

    private var resolvedPalette: [Color] {
        return Array(gradientPalette.prefix(8))
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
        let palette = resolvedPalette
        let isPaused = !isVisible || scenePhase != .active

        ZStack {
            if focusedMode && colorScheme == .light {
                theme.canvas.blended(with: .black, ratio: 0.03)
            } else {
                theme.canvas
            }

            DotGridLayer(spacing: spacing, dotSize: dotSize, colorScheme: colorScheme)
                .drawingGroup(opaque: false, colorMode: .linear)
                .allowsHitTesting(false)

            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.clear, theme.canvasDeep.opacity(0.6)]
                    : [Color.clear, theme.canvasDeep.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            if !focusedMode, !palette.isEmpty {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: isPaused)) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let isLight = colorScheme == .light
                    let tunedLightStrength = min(max(lightModeStrength, 0.2), 1.5)
                    let lightBoost = isLight ? (1.6 * tunedLightStrength) : 1.0
                    let haloOpacity = (isLight ? 0.25 : 0.15) * lightBoost
                    let coreOpacity = (isLight ? 0.15 : 0.08) * lightBoost

                    ZStack {
                        ForEach(palette.indices, id: \.self) { index in
                            let color = palette[index]
                            let idx = Double(index)
                            let phase = idx * (.pi / 2.7)
                            // Bias Y center downward into the card area (0.55–0.85 range).
                            let x = 0.5 + 0.34 * sin(elapsed * (0.072 + idx * 0.011) + phase)
                            let y = 0.62 + 0.22 * cos(elapsed * (0.081 + idx * 0.010) + phase * 1.21)

                            RadialGradient(
                                colors: [
                                    color.opacity(haloOpacity),
                                    color.opacity(coreOpacity),
                                    .clear
                                ],
                                center: UnitPoint(x: x, y: y),
                                startRadius: 40,
                                endRadius: isLight ? 520 : 500
                            )
                        }

                        // Secondary soft pass to remove hard transitions and add liquid depth.
                        ForEach(palette.indices, id: \.self) { index in
                            let color = palette[index]
                            let idx = Double(index)
                            let phase = idx * (.pi / 3.1) + .pi / 5
                            let x = 0.5 + 0.30 * sin(elapsed * (0.058 + idx * 0.009) + phase)
                            let y = 0.65 + 0.20 * cos(elapsed * (0.066 + idx * 0.008) + phase * 1.33)

                            RadialGradient(
                                colors: [
                                    color.opacity((isLight ? 0.12 : 0.10) * lightBoost),
                                    .clear
                                ],
                                center: UnitPoint(x: x, y: y),
                                startRadius: 80,
                                endRadius: isLight ? 640 : 600
                            )
                        }
                    }
                    .saturation(isLight ? (1.3 + 0.4 * tunedLightStrength) : 1.35)
                    .contrast(isLight ? (1.05 + 0.08 * tunedLightStrength) : 1.05)
                    .blur(radius: isLight ? (60 - 8 * tunedLightStrength) : 55)
                    .opacity(isLight ? (0.45 + 0.20 * tunedLightStrength) : 0.70)
                    .blendMode(isLight ? .overlay : .screen)
                    // Vertical mask: fades from subtle at top to full vibrancy in card area.
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.08), location: 0.0),
                                .init(color: .white.opacity(0.25), location: 0.15),
                                .init(color: .white.opacity(0.60), location: 0.30),
                                .init(color: .white, location: 0.45),
                                .init(color: .white, location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

private struct DotGridLayer: View {
    let spacing: CGFloat
    let dotSize: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
        Canvas { context, size in
            let dotColor = colorScheme == .dark
                ? Color.white.opacity(0.06)
                : Color.black.opacity(0.07)
            let cols = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            for x in 0..<cols {
                for y in 0..<rows {
                    let px = CGFloat(x) * spacing
                    let py = CGFloat(y) * spacing
                    let rect = CGRect(
                        x: px - dotSize / 2,
                        y: py - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                }
            }
        }
    }
}

#Preview("DotGridBackground") {
    DotGridBackground(
        gradientPalette: [.red, .blue, .green],
        lightModeStrength: 1.0
    )
}
