#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest
@testable import Snippets

final class AppearanceSettingsTests: XCTestCase {
    func test_appearanceName_lightPreference_isAqua() {
        XCTAssertEqual(AppearanceSettings.appearanceName(for: "light"), .aqua)
    }

    func test_appearanceName_darkPreference_isDarkAqua() {
        XCTAssertEqual(AppearanceSettings.appearanceName(for: "dark"), .darkAqua)
    }

    func test_appearanceName_systemPreference_isNilSoAppKitFollowsSystem() {
        XCTAssertNil(AppearanceSettings.appearanceName(for: "system"))
    }

    func test_appearanceName_unknownPreference_fallsBackToSystem() {
        XCTAssertNil(AppearanceSettings.appearanceName(for: "someFutureValue"))
    }

    // MARK: Accent

    /// A throwaway defaults suite, so the suite never touches the real app's settings.
    private func makeDefaults() -> UserDefaults {
        let suite = "AppearanceSettingsTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    @MainActor
    func test_freshInstall_accentIsBlue() {
        let settings = AppearanceSettings(defaults: makeDefaults())
        XCTAssertEqual(settings.themeColorHex, "#0A84FF")
        XCTAssertEqual(AppearanceSettings.defaultThemeColorHex, "#0A84FF")
    }

    @MainActor
    func test_chosenAccent_persistsAcrossLaunches() {
        let defaults = makeDefaults()
        AppearanceSettings(defaults: defaults).themeColorHex = "#51C278"
        XCTAssertEqual(AppearanceSettings(defaults: defaults).themeColorHex, "#51C278")
    }

    func test_presets_includeIconYellowAndPink() {
        let presets = Dictionary(uniqueKeysWithValues: AppearanceView.presetColors.map { ($0.name, $0.hex) })
        XCTAssertEqual(presets["Yellow"], "#FFCA00")
        XCTAssertEqual(presets["Pink"], "#FF6583")
        XCTAssertEqual(AppearanceView.presetColors.count, 8,
                       "The icon colours replace two presets rather than widening the row")
        XCTAssertEqual(presets["Blue"], AppearanceSettings.defaultThemeColorHex,
                       "The default accent must be selectable as a preset")
    }

    /// Light-mode accent text reaches 4.5:1 on the canvas for every preset,
    /// bright ones like yellow included.
    func test_safeAccentText_lightMode_meetsContrastForEveryPreset() throws {
        let theme = Theme.current(.light)
        let canvas = try XCTUnwrap(theme.canvas.relativeLuminance)
        for preset in AppearanceView.presetColors {
            let accent = try XCTUnwrap(Color(hex: preset.hex))
            let text = try XCTUnwrap(theme.safeAccentText(accent).relativeLuminance)
            let contrast = (canvas + 0.05) / (text + 0.05)
            XCTAssertGreaterThanOrEqual(contrast, 4.5, "\(preset.name) text is too faint in light mode")
        }
    }

    /// Accents that were already dark enough keep the original 35% darkening.
    func test_safeAccentText_lightMode_leavesDarkAccentsAtBaseDarkening() throws {
        let blue = try XCTUnwrap(Color(hex: "#0A84FF"))
        let expected = try XCTUnwrap(blue.blended(with: .black, ratio: 0.35).relativeLuminance)
        let actual = try XCTUnwrap(Theme.current(.light).safeAccentText(blue).relativeLuminance)
        XCTAssertEqual(actual, expected, accuracy: 0.0001)
    }

    func test_safeAccentText_darkMode_isTheAccentItself() throws {
        let yellow = try XCTUnwrap(Color(hex: "#FFCA00"))
        XCTAssertEqual(Theme.current(.dark).safeAccentText(yellow).relativeLuminance,
                       yellow.relativeLuminance)
    }
}
#endif
