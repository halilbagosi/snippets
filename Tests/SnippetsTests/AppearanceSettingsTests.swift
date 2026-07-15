#if canImport(AppKit)
import AppKit
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
}
#endif
