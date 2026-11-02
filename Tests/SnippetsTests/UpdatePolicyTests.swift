#if !APP_STORE
import XCTest
@testable import Snippets

/// When the updater may run, and what Settings says about it. Sparkle itself
/// is never started here: a test run must not contact the feed.
final class UpdatePolicyTests: XCTestCase {

    private let release: [String: String] = [:]
    private let underTest = ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]
    private let withOverride = [UpdatePolicy.feedOverrideKey: "http://localhost:8765/appcast.xml"]

    func test_releaseBuild_startsOnceTheLicenseIsAccepted() {
        XCTAssertTrue(UpdatePolicy.shouldStart(isDebugBuild: false, environment: release, licenseAccepted: true))
        XCTAssertFalse(UpdatePolicy.shouldStart(isDebugBuild: false, environment: release, licenseAccepted: false))
    }

    func test_testRuns_neverStart_evenWithAnOverride() {
        let env = underTest.merging(withOverride) { a, _ in a }
        XCTAssertFalse(UpdatePolicy.shouldStart(isDebugBuild: false, environment: underTest, licenseAccepted: true))
        XCTAssertFalse(UpdatePolicy.shouldStart(isDebugBuild: true, environment: env, licenseAccepted: true))
    }

    /// Debug builds share the release bundle ID and have a low build number,
    /// so without the override every one would be offered the latest release.
    func test_debugBuild_startsOnlyWithAFeedOverride() {
        XCTAssertFalse(UpdatePolicy.shouldStart(isDebugBuild: true, environment: release, licenseAccepted: true))
        XCTAssertTrue(UpdatePolicy.shouldStart(isDebugBuild: true, environment: withOverride, licenseAccepted: true))
    }

    func test_feedOverride_isIgnoredInReleaseBuilds() {
        XCTAssertNil(UpdatePolicy.feedOverride(isDebugBuild: false, environment: withOverride))
        XCTAssertEqual(UpdatePolicy.feedOverride(isDebugBuild: true, environment: withOverride),
                       "http://localhost:8765/appcast.xml")
        XCTAssertNil(UpdatePolicy.feedOverride(isDebugBuild: true, environment: release))
    }

    func test_statusLine_namesTheVersionAndTheLastCheck() {
        XCTAssertEqual(UpdatePolicy.statusLine(version: "1.1", build: "812", lastCheck: nil),
                       "Version 1.1 (812) · Not checked yet")
        let line = UpdatePolicy.statusLine(version: "1.1", build: "812", lastCheck: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(line.hasPrefix("Version 1.1 (812) · Last checked "), line)
    }

    /// The test host is the app, so its Info.plist is the shipped one.
    func test_infoPlist_carriesTheFeedAndARealKey() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(info["SUFeedURL"] as? String, "https://snippets.halilbagosi.com/appcast.xml")
        let key = info["SUPublicEDKey"] as? String ?? ""
        XCTAssertEqual(key.count, 44, "SUPublicEDKey must be the base64 Ed25519 key from generate_keys -p")
        XCTAssertNotNil(Data(base64Encoded: key))
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
        XCTAssertNil(info["SUEnableAutomaticChecks"], "Sparkle must ask before checking automatically")
    }
}
#endif
