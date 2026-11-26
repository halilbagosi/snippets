#if !APP_STORE
import SwiftData
import XCTest
@testable import Snippets

@MainActor
final class RatingToastModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Snippet.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    private func makeIDs(_ n: Int) throws -> [PersistentIdentifier] {
        let snippets = (0..<n).map { Snippet(title: "S\($0)", language: "Swift", code: "x") }
        snippets.forEach(context.insert)
        try context.save()
        return snippets.map(\.persistentModelID)
    }

    private func job(
        _ title: String, _ state: EfficiencyRatingCenter.Job.State, at offset: TimeInterval = 0
    ) -> EfficiencyRatingCenter.Job {
        var job = EfficiencyRatingCenter.Job(snippetTitle: title, agent: .claudeCode, state: state)
        job.startedAt = Date(timeIntervalSince1970: 1_000 + offset)
        return job
    }

    func test_textPerState() throws {
        let id = try makeIDs(1)[0]
        func text(_ state: EfficiencyRatingCenter.Job.State) -> String {
            RatingToastModel(jobs: [id: job("Sort", state)], hiding: nil).rows[0].text
        }
        XCTAssertEqual(text(.running), "Rating \u{201C}Sort\u{201D}…")
        XCTAssertEqual(text(.succeeded(score: 82, band: .good)), "Rated \u{201C}Sort\u{201D} · 82 Good")
        XCTAssertEqual(text(.succeeded(score: 40, band: nil)), "Rated \u{201C}Sort\u{201D} · 40 Poor")
        XCTAssertEqual(text(.succeeded(score: nil, band: nil)), "Rated \u{201C}Sort\u{201D} · not applicable")
        XCTAssertEqual(text(.failed(.timedOut)), "Couldn\u{2019}t rate \u{201C}Sort\u{201D}")
    }

    func test_kindPerState() throws {
        let ids = try makeIDs(3)
        let model = RatingToastModel(jobs: [
            ids[0]: job("A", .running, at: 0),
            ids[1]: job("B", .succeeded(score: 90, band: .excellent), at: 1),
            ids[2]: job("C", .failed(.notSignedIn), at: 2),
        ], hiding: nil)
        XCTAssertEqual(model.rows.map(\.kind), [.running, .succeeded, .failed])
    }

    func test_hidesPresentedSnippetAndUserCancels() throws {
        let ids = try makeIDs(3)
        let model = RatingToastModel(jobs: [
            ids[0]: job("Open", .running, at: 0),
            ids[1]: job("Cancelled", .failed(.cancelled), at: 1),
            ids[2]: job("Other", .running, at: 2),
        ], hiding: ids[0])
        XCTAssertEqual(model.rows.map(\.id), [ids[2]])
        XCTAssertEqual(model.overflow, 0)
    }

    func test_otherFailuresStayVisible() throws {
        let id = try makeIDs(1)[0]
        let model = RatingToastModel(jobs: [id: job("A", .failed(.invalidResponse("x")))], hiding: nil)
        XCTAssertEqual(model.rows.count, 1)
    }

    func test_capsAtThreeAndCountsTheRest() throws {
        let ids = try makeIDs(5)
        var jobs: [PersistentIdentifier: EfficiencyRatingCenter.Job] = [:]
        for (i, id) in ids.enumerated() { jobs[id] = job("S\(i)", .running, at: Double(i)) }
        let model = RatingToastModel(jobs: jobs, hiding: nil)
        XCTAssertEqual(model.rows.map(\.id), Array(ids.prefix(3)))   // oldest first
        XCTAssertEqual(model.overflow, 2)
        XCTAssertEqual(model.overflowText, "+2 more")
    }

    func test_overflowCountIgnoresHiddenJobs() throws {
        let ids = try makeIDs(5)
        var jobs: [PersistentIdentifier: EfficiencyRatingCenter.Job] = [:]
        for (i, id) in ids.enumerated() { jobs[id] = job("S\(i)", .running, at: Double(i)) }
        let model = RatingToastModel(jobs: jobs, hiding: ids[0])
        XCTAssertEqual(model.rows.count, 3)
        XCTAssertEqual(model.overflow, 1)
    }

    func test_noJobsNoOverflowText() {
        let model = RatingToastModel(jobs: [:], hiding: nil)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.overflowText)
    }

    func test_settingsStatusLine() {
        XCTAssertEqual(
            EfficiencyRatingSettings.statusLine(agent: .claudeCode, path: nil),
            "Claude Code was not found. Install it, then reopen Settings.")
        XCTAssertEqual(
            EfficiencyRatingSettings.statusLine(agent: .claudeCode, path: URL(fileURLWithPath: "/opt/bin/claude")),
            "/opt/bin/claude")
        XCTAssertEqual(EfficiencyRatingSettings.ratableAgents, [.claudeCode])
    }
}
#endif
