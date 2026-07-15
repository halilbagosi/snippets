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
        static let confirmSnippetDeletion = "settings.confirmSnippetDeletion"
        static let collectionDeletionBehavior = "settings.collectionDeletionBehavior"
    }

    // MARK: - Published State

    /// "system", "light", or "dark".
    var preferredColorScheme: String {
        didSet {
            UserDefaults.standard.set(preferredColorScheme, forKey: Key.colorScheme)
            applyAppAppearance()
        }
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

    /// Whether to ask for confirmation when deleting a snippet.
    var confirmSnippetDeletion: Bool {
        didSet { UserDefaults.standard.set(confirmSnippetDeletion, forKey: Key.confirmSnippetDeletion) }
    }

    /// Behavior for deleting collections: "ask", "collectionOnly", "collectionAndContents".
    var collectionDeletionBehavior: String {
        didSet { UserDefaults.standard.set(collectionDeletionBehavior, forKey: Key.collectionDeletionBehavior) }
    }

    // MARK: - Computed Helpers

    var themeColor: Color {
        Color(hex: themeColorHex) ?? Color(red: 0.318, green: 0.761, blue: 0.420)
    }

    #if canImport(AppKit)
    /// AppKit appearance override for a stored preference; nil follows the system.
    nonisolated static func appearanceName(for preference: String) -> NSAppearance.Name? {
        switch preference {
        case "light": return .aqua
        case "dark":  return .darkAqua
        default:      return nil
        }
    }
    #endif

    /// Applies the preference at the AppKit level. SwiftUI's
    /// `preferredColorScheme(nil)` alone doesn't re-read the system appearance
    /// until the window is next activated, so switching to "system" would lag
    /// behind by one click; `NSApp.appearance = nil` takes effect immediately.
    private func applyAppAppearance() {
        #if canImport(AppKit)
        NSApp.appearance = Self.appearanceName(for: preferredColorScheme)
            .flatMap { NSAppearance(named: $0) }
        #endif
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        self.preferredColorScheme = defaults.string(forKey: Key.colorScheme) ?? "system"
        self.focusedMode          = defaults.bool(forKey: Key.focusedMode)
        self.disableHoverEffects  = defaults.bool(forKey: Key.disableHover)
        self.themeColorHex        = defaults.string(forKey: Key.themeColorHex) ?? "#51C278"

        if defaults.object(forKey: Key.confirmSnippetDeletion) == nil {
            self.confirmSnippetDeletion = true
        } else {
            self.confirmSnippetDeletion = defaults.bool(forKey: Key.confirmSnippetDeletion)
        }
        self.collectionDeletionBehavior = defaults.string(forKey: Key.collectionDeletionBehavior) ?? "ask"

        // Apply stored accent and appearance on launch.
        Theme.userAccent = Color(hex: self.themeColorHex)
        applyAppAppearance()
    }
}
