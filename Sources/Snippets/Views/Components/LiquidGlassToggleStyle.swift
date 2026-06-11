import SwiftUI

struct LiquidGlassToggleStyle: ToggleStyle {
    var tint: Color = .accentColor
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack {
                // Background track
                Capsule()
                    .fill(configuration.isOn ? tint.opacity(0.9) : Color.gray.opacity(0.2))
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                    )
                    .frame(width: 38, height: 22)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.4), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .overlay(
                        Circle().strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                    )
                    .offset(x: configuration.isOn ? 8 : -8)
            }
            .frame(width: 38, height: 22)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

extension ToggleStyle where Self == LiquidGlassToggleStyle {
    static func liquidGlass(tint: Color = .accentColor) -> LiquidGlassToggleStyle {
        LiquidGlassToggleStyle(tint: tint)
    }
}

#Preview("LiquidGlassToggleStyle") {
    struct PreviewWrapper: View {
        @State private var isOn = true
        var body: some View {
            Toggle("Toggle", isOn: $isOn)
                .toggleStyle(.liquidGlass(tint: .blue))
                .padding()
        }
    }
    return PreviewWrapper()
}
