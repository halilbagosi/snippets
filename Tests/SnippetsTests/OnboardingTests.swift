import AppKit
import XCTest
@testable import Snippets

/// When the welcome tour shows, and the page arithmetic behind its buttons.
@MainActor
final class OnboardingTests: XCTestCase {

    /// A throwaway defaults suite, so running the suite never marks the real
    /// app's tour as seen.
    private func makeDefaults() -> UserDefaults {
        let suite = "OnboardingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return defaults
    }

    // MARK: Presentation

    func test_freshInstall_presentsOnLaunch() {
        let onboarding = Onboarding(defaults: makeDefaults())
        XCTAssertFalse(onboarding.hasCompleted)
        XCTAssertFalse(onboarding.isPresented, "Nothing presents before the window asks")

        onboarding.presentIfNeeded()

        XCTAssertTrue(onboarding.isPresented)
    }

    func test_completing_persistsAcrossLaunches() {
        let defaults = makeDefaults()
        let first = Onboarding(defaults: defaults)
        first.presentIfNeeded()
        first.complete()

        XCTAssertTrue(first.hasCompleted)
        XCTAssertFalse(first.isPresented)

        let relaunch = Onboarding(defaults: defaults)
        relaunch.presentIfNeeded()
        XCTAssertTrue(relaunch.hasCompleted)
        XCTAssertFalse(relaunch.isPresented, "The tour is once per install")
    }

    /// The Help menu reopens the tour whatever has been seen before.
    func test_present_reopensAfterCompletion() {
        let onboarding = Onboarding(defaults: makeDefaults())
        onboarding.complete()

        onboarding.present()

        XCTAssertTrue(onboarding.isPresented)
    }

    // MARK: Pages

    func test_pager_walksForwardAndBack() {
        var pager = OnboardingPager(pageCount: 3)
        XCTAssertTrue(pager.isFirst)
        XCTAssertFalse(pager.goBack(), "Nothing before the first page")

        XCTAssertTrue(pager.advance())
        XCTAssertTrue(pager.advance())
        XCTAssertEqual(pager.index, 2)
        XCTAssertTrue(pager.isLast)
        XCTAssertFalse(pager.advance(), "The last page finishes instead of advancing")
        XCTAssertEqual(pager.index, 2)

        XCTAssertTrue(pager.goBack())
        XCTAssertEqual(pager.index, 1)
    }

    func test_pager_jumpsToAnyPageButNotPastTheEnds() {
        var pager = OnboardingPager(pageCount: 4)
        XCTAssertTrue(pager.go(to: 3))
        XCTAssertTrue(pager.isLast)
        XCTAssertTrue(pager.go(to: 1))
        XCTAssertEqual(pager.index, 1)
        XCTAssertFalse(pager.go(to: 1), "Already there")
        XCTAssertFalse(pager.go(to: 4))
        XCTAssertFalse(pager.go(to: -1))
        XCTAssertEqual(pager.index, 1)
    }

    func test_everyPageHasCopyAndAScreenshotInTheBundle() {
        XCTAssertFalse(OnboardingPage.all.isEmpty)
        XCTAssertEqual(Set(OnboardingPage.all.map(\.id)).count, OnboardingPage.all.count)
        for page in OnboardingPage.all {
            XCTAssertFalse(String(localized: page.title).isEmpty)
            XCTAssertFalse(String(localized: page.subtitle).isEmpty)
            XCTAssertNotNil(NSImage(named: page.windowImage), page.windowImage)
            if let panel = page.panelImage {
                XCTAssertNotNil(NSImage(named: panel), panel)
            }
            if let clip = page.windowClip {
                XCTAssertNotNil(clip.url(for: .light), clip.name)
                XCTAssertNotNil(clip.url(for: .dark), clip.name)
            }
        }
    }

    func test_everyPresetAccentHasAGalleryShot() {
        for preset in AppearanceView.presetColors {
            let image = OnboardingPage.accentWindowImage(forHex: preset.hex)
            XCTAssertEqual(image, "OnboardingAccent\(preset.name)")
            XCTAssertNotNil(NSImage(named: image), image)
        }
    }

    func test_customAccentGetsTheNearestPresetsShot() {
        XCTAssertEqual(OnboardingPage.accentWindowImage(forHex: "#ff0a84ff"), "OnboardingAccentBlue")
        XCTAssertEqual(OnboardingPage.accentWindowImage(forHex: "#0a84ff"), "OnboardingAccentBlue")
        XCTAssertEqual(OnboardingPage.accentWindowImage(forHex: "#E0FF00"), "OnboardingAccentYellow")
        XCTAssertEqual(OnboardingPage.accentWindowImage(forHex: "#B00000"), "OnboardingAccentRed")
        XCTAssertEqual(OnboardingPage.accentWindowImage(forHex: "not a colour"), "OnboardingAccentBlue")
    }
}
