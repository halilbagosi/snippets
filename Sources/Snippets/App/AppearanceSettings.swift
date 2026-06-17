import SwiftUI
import Observation
#if canImport(AppKit)
import AppKit
#endif

/// Stores user appearance preferences, persisted via UserDefaults.
@MainActor
@Observable
final class AppearanceSettings {

    // MARK: - Persisted Keys

    private enum Key {
        static let colorScheme       = "settings.colorScheme"
        static let focusedMode       = "settings.focusedMode"
        static let disableHover      = "settings.disableHoverEffects"
        static let themeColorHex     = "settings.themeColorHex"
    }

    // MARK: - Published State

    /// "system", "light", or "dark".
    var preferredColorScheme: String {
        didSet { UserDefaults.standard.set(preferredColorScheme, forKey: Key.colorScheme) }
    }

    /// When true, the animated gradient background is hidden.
    var focusedMode: Bool {
        didSet { UserDefaults.standard.set(focusedMode, forKey: Key.focusedMode) }
    }

    /// When true, snippet card hover effects are suppressed.
    var disableHoverEffects: Bool {
        didSet { UserDefaults.standard.set(disableHoverEffects, forKey: Key.disableHover) }
    }

    /// Hex string for the user-chosen theme accent colour (e.g. "#51C278").
    var themeColorHex: String {
        didSet {
            UserDefaults.standard.set(themeColorHex, forKey: Key.themeColorHex)
            Theme.userAccent = Color(hex: themeColorHex)
        }
    }

    // MARK: - Computed Helpers

    var resolvedColorScheme: ColorScheme? {
        switch preferredColorScheme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil   // follow system
        }
    }

    var themeColor: Color {
        Color(hex: themeColorHex) ?? Color(red: 0.318, green: 0.761, blue: 0.420)
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        self.preferredColorScheme = defaults.string(forKey: Key.colorScheme) ?? "system"
        self.focusedMode          = defaults.bool(forKey: Key.focusedMode)
        self.disableHoverEffects  = defaults.bool(forKey: Key.disableHover)
        self.themeColorHex        = defaults.string(forKey: Key.themeColorHex) ?? "#51C278"

        // Apply stored accent on launch.
        Theme.userAccent = Color(hex: self.themeColorHex)
    }
}
