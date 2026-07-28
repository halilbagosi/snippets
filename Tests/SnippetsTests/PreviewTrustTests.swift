import XCTest
@testable import Snippets

/// The consent layer's decision logic — what `SnippetPreviewView` consults
/// before it lets any engine execute a snippet.
@MainActor
final class PreviewTrustTests: XCTestCase {
    private var defaultsKeys: [String] {
        ["settings.preview.autoRun", "settings.preview.hasPromptedForPolicy", "settings.preview.cdnGrants"]
    }

    override func setUp() {
        super.setUp()
        defaultsKeys.forEach(UserDefaults.standard.removeObject(forKey:))
    }

    override func tearDown() {
        defaultsKeys.forEach(UserDefaults.standard.removeObject(forKey:))
        super.tearDown()
    }

    // MARK: Running

    /// The default, and the whole point of the feature: an untouched install
    /// runs nothing until asked.
    func test_freshInstall_doesNotRunPreviews() {
        let trust = PreviewTrust()
        XCTAssertFalse(trust.autoRunPreviews)
        XCTAssertFalse(trust.mayRun(UUID()))
    }

    func test_approvingRun_appliesToThatSnippetOnly() {
        let trust = PreviewTrust()
        let approved = UUID()
        let other = UUID()

        trust.approveRun(approved)

        XCTAssertTrue(trust.mayRun(approved))
        XCTAssertFalse(trust.mayRun(other))
    }

    func test_autoRunEnabled_runsEverything() {
        let trust = PreviewTrust()
        trust.autoRunPreviews = true
        XCTAssertTrue(trust.mayRun(UUID()))
    }

    /// Run approval is per launch. A new instance models the next launch, and
    /// must not inherit approvals the user gave the previous one.
    func test_runApproval_doesNotSurviveRelaunch() {
        let id = UUID()
        let first = PreviewTrust()
        first.approveRun(id)
        XCTAssertTrue(first.mayRun(id))

        XCTAssertFalse(PreviewTrust().mayRun(id))
    }

    /// Snippets predating the uuid backfill have no id to key trust on, so
    /// they get the conservative answer rather than a free pass.
    func test_missingSnippetID_neverRunsWithoutAutoRun() {
        let trust = PreviewTrust()
        trust.approveRun(nil)
        XCTAssertFalse(trust.mayRun(nil))
    }

    // MARK: CDN grants

    func test_cdnModules_deniedByDefault() {
        let trust = PreviewTrust()
        XCTAssertFalse(trust.allowsCDNModules(UUID()))
        XCTAssertFalse(trust.policy(for: UUID()).allowsCDNModules)
    }

    func test_cdnGrant_isPerSnippet() {
        let trust = PreviewTrust()
        let granted = UUID()
        let other = UUID()

        trust.setCDNModulesAllowed(true, for: granted)

        XCTAssertTrue(trust.policy(for: granted).allowsCDNModules)
        XCTAssertFalse(trust.policy(for: other).allowsCDNModules)
    }

    /// Unlike run approval, a CDN grant is a deliberate standing decision and
    /// is expected to persist.
    func test_cdnGrant_survivesRelaunch() {
        let id = UUID()
        PreviewTrust().setCDNModulesAllowed(true, for: id)
        XCTAssertTrue(PreviewTrust().allowsCDNModules(id))
    }

    func test_cdnGrant_canBeRevoked() {
        let trust = PreviewTrust()
        let id = UUID()
        trust.setCDNModulesAllowed(true, for: id)
        trust.setCDNModulesAllowed(false, for: id)
        XCTAssertFalse(trust.allowsCDNModules(id))
    }

    /// A deleted snippet's grant must not be inherited by whatever next holds
    /// that id — a restore, or a reused uuid.
    func test_forget_dropsBothGrantAndRunApproval() {
        let trust = PreviewTrust()
        let id = UUID()
        trust.setCDNModulesAllowed(true, for: id)
        trust.approveRun(id)

        trust.forget(id)

        XCTAssertFalse(trust.allowsCDNModules(id))
        XCTAssertFalse(trust.mayRun(id))
    }

    func test_missingSnippetID_isNeverGrantedCDN() {
        let trust = PreviewTrust()
        trust.setCDNModulesAllowed(true, for: nil)
        XCTAssertFalse(trust.allowsCDNModules(nil))
    }
}
