import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// About pane in the Settings window: app icon over a soft accent glow,
/// name / version / developer info in a glass card.
struct AboutView: View {
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }
    private var accent: Color { appearanceSettings.themeColor }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (Build \(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.30 : 0.22))
                    .frame(width: 110, height: 110)
                    .blur(radius: 24)

                appIcon
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
            }
            .padding(.top, 12)

            VStack(spacing: 4) {
                Text("Snippets")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.text)

                Text(appVersion)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textMuted)
            }

            Divider()
                .frame(width: 160)
                .opacity(0.5)

            Text("Made by Halil Bagosi")
                .font(.system(size: 12))
                .foregroundStyle(theme.textMuted)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSToken.Spacing.lg)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            shadowRadius: 12,
            shadowY: 6
        )
        .frame(minHeight: 440)
    }

    private var appIcon: some View {
        Group {
            #if canImport(AppKit)
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
            #else
            Image(systemName: "app.fill")
                .resizable()
            #endif
        }
        .aspectRatio(contentMode: .fit)
    }
}
