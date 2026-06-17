import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// About tab in the Settings window.
/// Mirrors the macOS "About" pane style: app icon on the left,
/// name / version / developer info stacked on the right.
struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (Build \(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack(spacing: 20) {
                // App Icon
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
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Snippets")
                        .font(.system(size: 24, weight: .bold, design: .default))
                        .foregroundStyle(theme.text)

                    Text(appVersion)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(theme.textMuted)

                    Text("Made by Developer Name")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(theme.textMuted)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
