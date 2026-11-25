#if !APP_STORE
import XCTest
import SwiftData
@testable import Snippets

@MainActor
final class EfficiencyRatingCenterTests: XCTestCase {
    private final class FakeRater: EfficiencyRater, @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [EfficiencyRequest] = []
        var requests: [EfficiencyRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
        var models: [String?] = []
        var result: Result<EfficiencyReport, EfficiencyRatingError>
        /// When set, `rate` waits until this is resumed (or cancelled).
        var gate: AsyncStream<Void>?

        private func record(_ request: EfficiencyRequest, _ model: String?) {
            lock.lock(); defer { lock.unlock() }
            _requests.append(request); models.append(model)
        }

        init(_ result: Result<EfficiencyReport, EfficiencyRatingError>) { self.result = result }

        func rate(_ request: EfficiencyRequest, model: String?) async throws -> EfficiencyReport {
            record(request, model)
            if let gate {
                for await _ in gate { break }
                try Task.checkCancellation()
            }
            return try result.get()
        }
    }

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Snippet.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    private func settings() -> EfficiencySettings {
        let suite = "efficiency-center-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return EfficiencySettings(defaults: defaults, locate: { _ in nil })
    }

    private func center(_ rater: FakeRater?, linger: Duration = .seconds(60)) -> EfficiencyRatingCenter {
        EfficiencyRatingCenter(settings: settings(), succeededLinger: linger, makeRater: { _ in rater })
    }

    private func snippet(code: String = "let a = 1") throws -> Snippet {
        let s = Snippet(title: "Demo", language: "Swift", code: code)
        context.insert(s)
        try context.save()
        return s
    }

    private func report(score: Int? = 82) -> EfficiencyReport {
        EfficiencyReport(score: score, notApplicableReason: nil, summary: "ok", suggestions: [])
    }

    private func settle(_ center: EfficiencyRatingCenter, _ id: PersistentIdentifier) async {
        for _ in 0..<200 {
            if center.jobs[id]?.state != .running { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func test_successAppendsReviewAndPrunes() async throws {
        let s = try snippet()
        let stale = EfficiencyReview(
            id: UUID(), codeHash: "old", ratedCode: "old", rubricVersion: 1, score: 10,
            notApplicableReason: nil, summary: "", suggestions: [], agent: "claudeCode", model: nil,
            date: .distantPast)
        s.efficiencyReviews = [stale]
        let rater = FakeRater(.success(report()))
        let c = center(rater)
        c.start(for: s)
        await settle(c, s.persistentModelID)

        XCTAssertEqual(c.jobs[s.persistentModelID]?.state, .succeeded(score: 82, band: .good))
        XCTAssertEqual(s.efficiencyReviews.count, 1)
        let review = try XCTUnwrap(s.efficiencyReviews.first)
        XCTAssertEqual(review.codeHash, EfficiencyReviewStore.hash(of: "let a = 1"))
        XCTAssertEqual(review.ratedCode, "let a = 1")
        XCTAssertEqual(review.rubricVersion, EfficiencyRubric.version)
        XCTAssertEqual(review.agent, "claudeCode")
        XCTAssertNil(review.model)
        XCTAssertFalse(context.hasChanges)
    }

    func test_failureLeavesReviewsUntouchedAndStays() async throws {
        let s = try snippet()
        let existing = EfficiencyReview(
            id: UUID(), codeHash: "h", ratedCode: "x", rubricVersion: 1, score: 50,
            notApplicableReason: nil, summary: "", suggestions: [], agent: "claudeCode", model: nil,
            date: .now)
        s.efficiencyReviews = [existing]
        let c = center(FakeRater(.failure(.timedOut)))
        c.start(for: s)
        await settle(c, s.persistentModelID)
        XCTAssertEqual(c.jobs[s.persistentModelID]?.state, .failed(.timedOut))
        XCTAssertEqual(s.efficiencyReviews, [existing])

        c.dismiss(s.persistentModelID)
        XCTAssertNil(c.jobs[s.persistentModelID])
    }

    func test_secondStartWhileRunningIsIgnored() async throws {
        let s = try snippet()
        let rater = FakeRater(.success(report()))
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        rater.gate = stream
        let c = center(rater)
        c.start(for: s)
        c.start(for: s)
        continuation.yield()
        await settle(c, s.persistentModelID)
        XCTAssertEqual(rater.requests.count, 1)
    }

    func test_cancelEndsJobWithoutSaving() async throws {
        let s = try snippet()
        let rater = FakeRater(.success(report()))
        let (stream, _) = AsyncStream<Void>.makeStream()
        rater.gate = stream
        let c = center(rater)
        c.start(for: s)
        XCTAssertTrue(c.isRunning(s.persistentModelID))
        c.cancel(s.persistentModelID)
        XCTAssertNil(c.jobs[s.persistentModelID])
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(s.efficiencyReviews.isEmpty)
    }

    func test_cancelAllClearsEveryJob() async throws {
        let s = try snippet()
        let rater = FakeRater(.success(report()))
        let (stream, _) = AsyncStream<Void>.makeStream()
        rater.gate = stream
        let c = center(rater)
        c.start(for: s)
        c.cancelAll()
        XCTAssertTrue(c.jobs.isEmpty)
    }

    func test_deletingSnippetMidRunDropsResult() async throws {
        let s = try snippet()
        let id = s.persistentModelID
        let rater = FakeRater(.success(report()))
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        rater.gate = stream
        let c = center(rater)
        c.start(for: s)
        context.delete(s)
        try context.save()
        continuation.yield()
        for _ in 0..<200 where c.jobs[id] != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(c.jobs[id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<Snippet>()).isEmpty)
    }

    func test_succeededJobRemovesItselfAfterLinger() async throws {
        let s = try snippet()
        let c = center(FakeRater(.success(report())), linger: .milliseconds(20))
        c.start(for: s)
        for _ in 0..<200 where c.jobs[s.persistentModelID] != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(c.jobs[s.persistentModelID])
        XCTAssertEqual(s.efficiencyReviews.count, 1)
    }

    func test_requestCarriesCurrentCodeAndDependencies() async throws {
        let dep = Snippet(title: "Helper", language: "Swift", code: "func helper() {}")
        context.insert(dep)
        let s = try snippet(code: "OPTIMIZED")
        s.dependencies = [dep]
        let defaultConfig = PreviewParamConfig(id: UUID(), name: "Default", values: [:], isDefault: true, code: "ORIGINAL")
        s.paramConfigs = [defaultConfig]
        s.activeParamConfigID = defaultConfig.id
        let rater = FakeRater(.success(report()))
        let c = center(rater)
        c.start(for: s)
        await settle(c, s.persistentModelID)

        let request = try XCTUnwrap(rater.requests.first)
        XCTAssertEqual(request.code, "OPTIMIZED")
        XCTAssertEqual(request.dependencies.map(\.code), ["func helper() {}"])
        XCTAssertEqual(request.dependencies.map(\.title), ["Helper"])
        // The flush rule refreshed the active config's stored code.
        XCTAssertEqual(s.paramConfigs.first?.code, "OPTIMIZED")
    }

    func test_modelOverrideReachesRater() async throws {
        let s = try snippet()
        let rater = FakeRater(.success(report()))
        let c = center(rater)
        c.settings.setModel("  sonnet ", for: .claudeCode)
        c.start(for: s)
        await settle(c, s.persistentModelID)
        XCTAssertEqual(rater.models, ["sonnet"])
        XCTAssertEqual(s.efficiencyReviews.first?.model, "sonnet")
    }

    func test_retryRerunsAFailedJob() async throws {
        let s = try snippet()
        let rater = FakeRater(.failure(.timedOut))
        let c = center(rater)
        c.start(for: s)
        await settle(c, s.persistentModelID)
        rater.result = .success(report())
        c.retry(s.persistentModelID)
        await settle(c, s.persistentModelID)
        XCTAssertEqual(c.jobs[s.persistentModelID]?.state, .succeeded(score: 82, band: .good))
    }

    func test_settingsDefaultsAndPersistence() {
        let suite = "efficiency-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = EfficiencySettings(defaults: defaults, locate: { _ in nil })
        XCTAssertTrue(first.enabled)
        XCTAssertEqual(first.agent, .claudeCode)
        XCTAssertEqual(first.model(for: .claudeCode), "")
        XCTAssertNil(first.modelOverride(for: .claudeCode))
        XCTAssertFalse(first.isConsented(.claudeCode))
        first.enabled = false
        first.setModel("opus", for: .claudeCode)
        first.grantConsent(for: .claudeCode)

        let second = EfficiencySettings(defaults: defaults, locate: { _ in nil })
        XCTAssertFalse(second.enabled)
        XCTAssertEqual(second.model(for: .claudeCode), "opus")
        XCTAssertTrue(second.isConsented(.claudeCode))
        XCTAssertFalse(second.isConsented(.codex))
    }

    func test_consentHelpers() {
        let c = center(nil)
        XCTAssertTrue(c.needsConsent(for: .claudeCode))
        c.grantConsent(for: .claudeCode)
        XCTAssertFalse(c.needsConsent(for: .claudeCode))
    }

    func test_cliPathComesFromLocator() async {
        let suite = "efficiency-cli-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let s = EfficiencySettings(defaults: defaults, locate: { name in URL(fileURLWithPath: "/x/\(name)") })
        await s.refreshCLIPath()
        XCTAssertEqual(s.cliPath?.path, "/x/claude")
    }
}
#endif
