#if !APP_STORE
import XCTest
@testable import Snippets

final class AgentCLILocatorTests: XCTestCase {
    func test_candidateOrder() {
        XCTAssertEqual(AgentCLILocator.candidateDirectories(home: "/h"), [
            "/h/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
            "/h/.npm-global/bin", "/h/.bun/bin", "/h/.volta/bin",
        ])
    }

    func test_firstExecutableWinsInOrder() {
        let dirs = ["/a", "/b", "/c"]
        let url = AgentCLILocator.firstExecutable(named: "claude", in: dirs) { $0 == "/b/claude" || $0 == "/c/claude" }
        XCTAssertEqual(url?.path, "/b/claude")
        XCTAssertNil(AgentCLILocator.firstExecutable(named: "claude", in: dirs) { _ in false })
    }

    func test_unsafeNamesRejected() {
        XCTAssertTrue(AgentCLILocator.isSafeName("claude"))
        XCTAssertTrue(AgentCLILocator.isSafeName("my-cli_2.0"))
        for bad in ["", "a; rm -rf /", "../x", ".hidden", "..", "-rf", "-"] {
            XCTAssertFalse(AgentCLILocator.isSafeName(bad), bad)
        }
        XCTAssertNil(AgentCLILocator.firstExecutable(named: "../x", in: ["/a"]) { _ in true })
    }

    func test_regularExecutableRejectsDirectories() {
        XCTAssertFalse(AgentCLILocator.isRegularExecutable("/usr/bin"))
        XCTAssertTrue(AgentCLILocator.isRegularExecutable("/bin/ls"))
        XCTAssertFalse(AgentCLILocator.isRegularExecutable("/nonexistent/zzz"))
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    func test_cacheHitNegativeHitAndRefresh() async {
        let probes = Counter()
        let present = Counter()  // flips the probe from "missing" to "found" once bumped
        let locator = AgentCLILocator(
            directories: [], isExecutable: { _ in false },
            shellProbe: { _ in probes.bump(); return present.value > 0 ? URL(fileURLWithPath: "/x/claude") : nil })

        let first = await locator.locate("claude")
        XCTAssertNil(first)
        let second = await locator.locate("claude")
        XCTAssertNil(second)
        XCTAssertEqual(probes.value, 1, "negative result must be cached")

        present.bump()
        let stillCached = await locator.locate("claude")
        XCTAssertNil(stillCached)
        XCTAssertEqual(probes.value, 1)

        let refreshed = await locator.refresh("claude")
        XCTAssertEqual(refreshed?.path, "/x/claude")
        XCTAssertEqual(probes.value, 2)
        let hit = await locator.locate("claude")
        XCTAssertEqual(hit?.path, "/x/claude")
        XCTAssertEqual(probes.value, 2, "positive result must be cached")
    }

    func test_directoryHitSkipsShell() async {
        let probes = Counter()
        let locator = AgentCLILocator(
            directories: ["/d"], isExecutable: { $0 == "/d/claude" },
            shellProbe: { _ in probes.bump(); return nil })
        let url = await locator.locate("claude")
        XCTAssertEqual(url?.path, "/d/claude")
        XCTAssertEqual(probes.value, 0)
    }

    func test_loginShellProbeFindsRealTool() throws {
        // `ls` always exists; proves the file-backed probe returns a path.
        XCTAssertEqual(AgentCLILocator.loginShellProbe("ls")?.lastPathComponent, "ls")
        XCTAssertNil(AgentCLILocator.loginShellProbe("definitely-not-a-real-tool-zz9"))
    }
}
#endif
