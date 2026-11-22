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

    /// The version the home screen's update button offers, after `event`.
    /// It appears once a check finds an update and stays through "Remind Me
    /// Later", so the user can come back to it; it goes once they skip or
    /// start installing that version, or a later check finds nothing.
    static func availableVersion(_ current: String?, after event: UpdateEvent) -> String? {
        switch event {
        case .found(let version): version
        case .noneFound, .skipped, .installing: nil
        case .dismissed: current
        }
    }

    /// Sparkle's scheduled check found an update: show its window only when
    /// it would come up in focus (just launched, or back from idle). Otherwise
    /// the home screen's update button is the reminder, instead of a window
    /// opening behind whatever the user is doing.
    static func sparkleShowsScheduledUpdate(immediateFocus: Bool) -> Bool {
        immediateFocus
    }
}

/// What Sparkle reported, without Sparkle's types.
enum UpdateEvent: Equatable {
    case found(version: String)
    case noneFound
    case skipped
    case installing
    case dismissed
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
    /// The version a check found and the user hasn't installed or skipped —
    /// drives the update button on the home screen.
    private(set) var availableVersion: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var delegate: UpdaterDelegate?
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

        let delegate = UpdaterDelegate(
            feed: UpdatePolicy.feedOverride(isDebugBuild: isDebugBuild, environment: environment)
        ) { [weak self] event in
            guard let self else { return }
            availableVersion = UpdatePolicy.availableVersion(availableVersion, after: event)
        }
        self.delegate = delegate
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: delegate
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

/// Reports what Sparkle finds and what the user chooses, opts into gentle
/// scheduled reminders, and points a Debug build at `SNIPPETS_UPDATE_FEED`
/// instead of `SUFeedURL`. Sparkle calls all of these on the main thread;
/// only `SPUUpdaterDelegate` says so in its header, hence `@preconcurrency`.
@MainActor
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    let feed: String?
    let report: (UpdateEvent) -> Void

    init(feed: String?, report: @escaping (UpdateEvent) -> Void) {
        self.feed = feed
        self.report = report
    }

    // MARK: SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? { feed }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        report(.found(version: item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        report(.noneFound)
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        switch choice {
        case .skip: report(.skipped)
        case .install: report(.installing)
        case .dismiss: report(.dismissed)
        @unknown default: break
        }
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        UpdatePolicy.sparkleShowsScheduledUpdate(immediateFocus: immediateFocus)
    }
}
#endif
