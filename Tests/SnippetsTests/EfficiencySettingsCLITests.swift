#if !APP_STORE
import XCTest
@testable import Snippets

@MainActor
final class EfficiencySettingsCLITests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "efficiency-cli-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        addTeardownBlock { d.removePersistentDomain(forName: suite) }
        return d
    }

    func test_forceRefreshUsesTheRelocateClosureNotTheCachedOne() async {
        let s = EfficiencySettings(
            defaults: defaults(),
            locate: { _ in nil },                                   // cached "not found"
            relocate: { name in URL(fileURLWithPath: "/new/\(name)") })
        await s.refreshCLIPath()
        XCTAssertNil(s.cliPath)
        await s.forceRefreshCLIPath()
        XCTAssertEqual(s.cliPath?.path, "/new/claude")
    }

    func test_switchingAgentClearsPathAndDropsLateLookupForOldAgent() async {
        // A locate that suspends until the test resumes it.
        var resume: CheckedContinuation<Void, Never>?
        let s = EfficiencySettings(
            defaults: defaults(),
            locate: { name in
                await withCheckedContinuation { resume = $0 }
                return URL(fileURLWithPath: "/bin/\(name)")
            },
            relocate: { _ in nil })
        XCTAssertEqual(s.agent, .claudeCode)

        let lookup = Task { await s.refreshCLIPath() }
        while resume == nil { await Task.yield() }

        s.agent = .codex                       // no CLI for it: path cleared
        XCTAssertNil(s.cliPath)
        resume?.resume()
        await lookup.value
        XCTAssertNil(s.cliPath, "a result for the old agent must be dropped")
    }

    func test_switchingAgentClearsAnExistingPath() async {
        let s = EfficiencySettings(
            defaults: defaults(), locate: { URL(fileURLWithPath: "/bin/\($0)") }, relocate: { _ in nil })
        await s.refreshCLIPath()
        XCTAssertNotNil(s.cliPath)
        s.agent = .codex
        XCTAssertNil(s.cliPath)
    }
}
#endif
