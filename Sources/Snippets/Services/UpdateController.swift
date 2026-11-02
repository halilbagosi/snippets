#if !APP_STORE
import Foundation
import Combine
import Observation
import Sparkle

/// When the updater may run and what Settings says about it. Kept apart from
/// Sparkle so tests can pin it down without starting anything.
enum UpdatePolicy {
    /// Debug builds only: an appcast URL to check instead of the real one, for
    /// trying the update flow against a local feed.
    static let feedOverrideKey = "SNIPPETS_UPDATE_FEED"

    /// Never under XCTest, never before the license is agreed to, and in a
    /// Debug build only against an override feed — a dev build has the
    /// release bundle ID and a low build number, so the real feed would
    /// offer to replace it every day.
    static func shouldStart(isDebugBuild: Bool, environment: [String: String], licenseAccepted: Bool) -> Bool {
        guard licenseAccepted, environment["XCTestConfigurationFilePath"] == nil else { return false }
        return !isDebugBuild || environment[feedOverrideKey] != nil
    }

    static func feedOverride(isDebugBuild: Bool, environment: [String: String]) -> String? {
        isDebugBuild ? environment[feedOverrideKey] : nil
    }

    static func statusLine(version: String, build: String, lastCheck: Date?) -> String {
        let checked = lastCheck.map { "Last checked \($0.formatted(date: .abbreviated, time: .shortened))" }
            ?? "Not checked yet"
        return "Version \(version) (\(build)) · \(checked)"
    }
}

/// Owns Sparkle. Sparkle schedules the daily check and draws its own update
/// window; this mirrors the state the menu item and Settings show.
@MainActor
@Observable
final class UpdateController {
    static let shared = UpdateController()

    private(set) var isRunning = false
    private(set) var canCheckForUpdates = false
    /// Sparkle's own setting, which its second-launch prompt also changes.
    private(set) var automaticallyChecks = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var feedDelegate: FeedOverrideDelegate?
    @ObservationIgnored private var observers: Set<AnyCancellable> = []

    var lastUpdateCheckDate: Date? { controller?.updater.lastUpdateCheckDate }

    func startIfAllowed(
        licenseAccepted: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard controller == nil else { return }
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        guard UpdatePolicy.shouldStart(isDebugBuild: isDebugBuild, environment: environment, licenseAccepted: licenseAccepted) else { return }

        feedDelegate = UpdatePolicy.feedOverride(isDebugBuild: isDebugBuild, environment: environment)
            .map(FeedOverrideDelegate.init(feed:))
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: feedDelegate, userDriverDelegate: nil
        )
        self.controller = controller
        isRunning = true

        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in MainActor.assumeIsolated { self?.canCheckForUpdates = value } }
            .store(in: &observers)
        updater.publisher(for: \.automaticallyChecksForUpdates, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in MainActor.assumeIsolated { self?.automaticallyChecks = value } }
            .store(in: &observers)
    }

    func setAutomaticallyChecks(_ on: Bool) {
        controller?.updater.automaticallyChecksForUpdates = on
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// Points a Debug build at `SNIPPETS_UPDATE_FEED` instead of `SUFeedURL`.
private final class FeedOverrideDelegate: NSObject, SPUUpdaterDelegate {
    let feed: String
    init(feed: String) { self.feed = feed }
    func feedURLString(for updater: SPUUpdater) -> String? { feed }
}
#endif
