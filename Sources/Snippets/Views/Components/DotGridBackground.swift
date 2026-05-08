import SwiftUI

struct DotGridBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var spacing: CGFloat = 22
    var dotSize: CGFloat = 1.4
    var gradientPalette: [Color] = []
    var lightModeStrength: Double = 1.0

    private var resolvedPalette: [Color] {
        return Array(gradientPalette.prefix(8))
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
        ZStack {
            theme.canvas

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
            .allowsHitTesting(false)

            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.clear, theme.canvasDeep.opacity(0.6)]
                    : [Color.clear, theme.canvasDeep.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let isLight = colorScheme == .light
                let tunedLightStrength = min(max(lightModeStrength, 0.2), 1.5)
                let lightBoost = isLight ? (1.95 * tunedLightStrength) : 1.0
                let haloOpacity = (isLight ? 0.34 : 0.19) * lightBoost
                let coreOpacity = (isLight ? 0.22 : 0.08) * lightBoost

                ZStack {
                    ForEach(Array(resolvedPalette.enumerated()), id: \.offset) { index, color in
                        let idx = Double(index)
                        let phase = idx * (.pi / 2.7)
                        // Lower frequencies + broader gradients produce smoother mesh-like flow.
                        let x = 0.5 + 0.34 * sin(elapsed * (0.072 + idx * 0.011) + phase)
                        let y = 0.5 + 0.28 * cos(elapsed * (0.081 + idx * 0.010) + phase * 1.21)

                        RadialGradient(
                            colors: [
                                color.opacity(haloOpacity),
                                color.opacity(coreOpacity),
                                .clear
                            ],
                            center: UnitPoint(x: x, y: y),
                            startRadius: 18,
                            endRadius: isLight ? 440 : 420
                        )
                    }

                    // Secondary soft pass to remove hard transitions and add liquid depth.
                    ForEach(Array(resolvedPalette.enumerated()), id: \.offset) { index, color in
                        let idx = Double(index)
                        let phase = idx * (.pi / 3.1) + .pi / 5
                        let x = 0.5 + 0.30 * sin(elapsed * (0.058 + idx * 0.009) + phase)
                        let y = 0.5 + 0.25 * cos(elapsed * (0.066 + idx * 0.008) + phase * 1.33)

                        RadialGradient(
                            colors: [
                                color.opacity((isLight ? 0.16 : 0.09) * lightBoost),
                                .clear
                            ],
                            center: UnitPoint(x: x, y: y),
                            startRadius: 40,
                            endRadius: isLight ? 540 : 500
                        )
                    }
                }
                .saturation(isLight ? (1.0 + 0.75 * tunedLightStrength) : 1.05)
                .contrast(isLight ? (1.0 + 0.08 * tunedLightStrength) : 1.0)
                .blur(radius: isLight ? (34 - 8 * tunedLightStrength) : 34)
                .opacity(isLight ? (0.50 + 0.38 * tunedLightStrength) : 1.0)
                .blendMode(isLight ? .multiply : .plusLighter)
                .allowsHitTesting(false)
            }
        }
    }
}
