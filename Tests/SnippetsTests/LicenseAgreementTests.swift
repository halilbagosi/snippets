import XCTest
@testable import Snippets

/// When the license agreement asks to be accepted, and what accepting records.
@MainActor
final class LicenseAgreementTests: XCTestCase {

    /// A throwaway defaults suite, so running the suite never accepts the
    /// real app's agreement.
    private func makeDefaults() -> UserDefaults {
        let suite = "LicenseAgreementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return defaults
    }

    func test_freshInstall_asksOnLaunch() {
        let agreement = LicenseAgreement(defaults: makeDefaults())
        XCTAssertFalse(agreement.isAccepted)
        XCTAssertFalse(agreement.isPresented, "Nothing presents before the window asks")

        agreement.presentIfNeeded()

        XCTAssertTrue(agreement.isPresented)
    }

    func test_accepting_persistsAcrossLaunches() {
        let defaults = makeDefaults()
        let first = LicenseAgreement(defaults: defaults)
        first.presentIfNeeded()
        first.accept()

        XCTAssertTrue(first.isAccepted)
        XCTAssertFalse(first.isPresented)
        XCTAssertTrue(LicenseAgreement.isAccepted(in: defaults))

        let relaunch = LicenseAgreement(defaults: defaults)
        relaunch.presentIfNeeded()
        XCTAssertTrue(relaunch.isAccepted)
        XCTAssertFalse(relaunch.isPresented, "Accepted terms are not asked again")
    }

    /// New terms (a higher version) are asked for again, even by someone who
    /// accepted the old ones.
    func test_olderAcceptedVersion_asksAgain() {
        let defaults = makeDefaults()
        defaults.set(LicenseAgreement.currentVersion - 1, forKey: LicenseAgreement.acceptedVersionDefaultsKey)

        let agreement = LicenseAgreement(defaults: defaults)
        XCTAssertFalse(agreement.isAccepted)
        XCTAssertFalse(LicenseAgreement.isAccepted(in: defaults))

        agreement.presentIfNeeded()
        XCTAssertTrue(agreement.isPresented)
    }

    /// Without an answer nothing is recorded, so the next launch asks again.
    func test_unanswered_isNotRecorded() {
        let defaults = makeDefaults()
        LicenseAgreement(defaults: defaults).presentIfNeeded()

        XCTAssertNil(defaults.object(forKey: LicenseAgreement.acceptedVersionDefaultsKey))
        XCTAssertTrue(LicenseAgreement(defaults: defaults).needsAnswer)
    }

    /// Hard-wrapped paragraphs become one line each; list items stay apart.
    func test_reflowed_joinsWrappedLinesAndKeepsListItems() {
        let text = """
        1. LICENCE

        The App is provided free of charge. I grant you a
        licence to use it.

        You may not:

          a. copy or redistribute
             the App;
          b. modify it.
        """
        XCTAssertEqual(LicenseAgreement.reflowed(text), """
        1. LICENCE

        The App is provided free of charge. I grant you a licence to use it.

        You may not:

            a. copy or redistribute the App;
            b. modify it.
        """)
    }

    /// The text shown for agreement is the bundled EULA, not a fallback.
    func test_text_isTheBundledEULA() {
        XCTAssertTrue(LicenseAgreement.text.hasPrefix("SNIPPETS END USER LICENSE AGREEMENT"))
    }
}
