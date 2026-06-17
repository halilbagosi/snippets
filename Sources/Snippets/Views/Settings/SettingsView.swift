import SwiftUI

/// Top-level settings view, displayed as the macOS Settings window.
/// Uses a toolbar-style tab view matching native macOS preferences.
struct SettingsView: View {
    @Environment(AppearanceSettings.self) private var appearanceSettings

    var body: some View {
        TabView {
            AppearanceView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 360)
    }
}
