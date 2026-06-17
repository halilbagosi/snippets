import SwiftUI

/// Appearance tab in the Settings window.
/// Controls colour scheme, focused mode, hover effects, and theme accent colour.
struct AppearanceView: View {
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }

    /// Preset accent colour palette.
    private static let presetColors: [(name: String, hex: String)] = [
        ("Green",  "#51C278"),
        ("Blue",   "#0A84FF"),
        ("Indigo", "#5E5CE6"),
        ("Purple", "#BF5AF2"),
        ("Pink",   "#FF375F"),
        ("Orange", "#FF9F0A"),
        ("Teal",   "#64D2FF"),
        ("Red",    "#FF453A"),
    ]

    var body: some View {
        @Bindable var settings = appearanceSettings

        Form {
            // MARK: - Color Scheme
            Section {
                Picker("Color Scheme", selection: $settings.preferredColorScheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Color Scheme")
            }

            // MARK: - Behavior
            Section {
                Toggle("Focused Mode", isOn: $settings.focusedMode)
                    .help("Remove the animated color gradient from the background")

                Toggle("Disable Hover Effects", isOn: $settings.disableHoverEffects)
                    .help("Remove hover animations from snippet cards")
            } header: {
                Text("Behavior")
            }

            // MARK: - Theme Color
            Section {
                themeColorPicker
            } header: {
                Text("Theme Color")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Theme Color Picker

    @ViewBuilder
    private var themeColorPicker: some View {
        @Bindable var settings = appearanceSettings

        HStack(spacing: 10) {
            ForEach(Self.presetColors, id: \.hex) { preset in
                let isActive = settings.themeColorHex.lowercased() == preset.hex.lowercased()
                Button {
                    settings.themeColorHex = preset.hex
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex) ?? .gray)
                        .frame(width: 22, height: 22)
                        .overlay {
                            if isActive {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 2)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .shadow(color: (Color(hex: preset.hex) ?? .gray).opacity(isActive ? 0.5 : 0.0), radius: 4)
                }
                .buttonStyle(.plain)
                .help(preset.name)
                .accessibilityLabel("Theme color: \(preset.name)")
            }

            Divider()
                .frame(height: 22)

            ColorPicker("", selection: Binding(
                get: { settings.themeColor },
                set: { newColor in
                    settings.themeColorHex = newColor.hexString(fallback: "#51C278")
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .help("Custom color")
        }
    }
}
