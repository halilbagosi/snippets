import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Top-level settings view, displayed as the macOS Settings window.
///
/// De-chromed Liquid Glass window matching the app's modal family: transparent
/// titlebar, dot-grid backdrop, a centered glass tab switcher instead of the
/// stock preferences toolbar, and glass-card panes instead of grouped forms.
struct SettingsView: View {
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(\.colorScheme) private var colorScheme

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case appearance = "Appearance"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .appearance: return "paintbrush.fill"
            case .about: return "info.circle.fill"
            }
        }
    }

    @Namespace private var tabNamespace
    @State private var selectedTab: SettingsTab = .appearance

    private var theme: Theme { Theme.current(colorScheme) }
    private var accent: Color { appearanceSettings.themeColor }

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            ScrollView {
                DSGlassContainer(spacing: 20) {
                    Group {
                        switch selectedTab {
                        case .appearance:
                            AppearanceView()
                        case .about:
                            AboutView()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
        }
        .background {
            ZStack {
                Color.clear.ignoresSafeArea()
                DotGridBackground(gradientPalette: [accent], lightModeStrength: 0.5)
                    .opacity(colorScheme == .dark ? 0.12 : 0.10)
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(appearanceSettings.resolvedColorScheme)
        .frame(width: 520, height: 600)
        #if canImport(AppKit)
        .background(SettingsWindowConfigurator())
        #endif
    }

    // MARK: - Glass Tab Switcher

    private var settingsHeader: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(4)
            .liquidGlassSurface(
                in: Capsule(style: .continuous),
                shadowRadius: 6,
                shadowY: 3
            )
            Spacer()
        }
        // Clears the (transparent) titlebar strip and its traffic lights.
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.safeAccentText(accent) : theme.textMuted)
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? theme.text : theme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Capsule(style: .continuous))
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(colorScheme == .dark ? 0.26 : 0.18))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.35), lineWidth: 1)
                        }
                        .matchedGeometryEffect(id: "selectedSettingsTab", in: tabNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window Chrome

#if canImport(AppKit)
/// De-chromes the hosting Settings window: hidden title, transparent titlebar,
/// content extending under it — same treatment as the main window.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ nsView: ChromeView, context: Context) {}

    @MainActor
    final class ChromeView: NSView {
        private weak var configuredWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== configuredWindow else { return }
            configuredWindow = window

            applyChrome()

            // SwiftUI reasserts some window properties on scene updates.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applyChrome),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
        }

        @objc private func applyChrome() {
            guard let window = configuredWindow else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
#endif
