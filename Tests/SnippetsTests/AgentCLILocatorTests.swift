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
        XCTAssertFalse(AgentCLILocator.isSafeName(""))
        XCTAssertFalse(AgentCLILocator.isSafeName("a; rm -rf /"))
        XCTAssertFalse(AgentCLILocator.isSafeName("../x"))
        XCTAssertNil(AgentCLILocator.firstExecutable(named: "../x", in: ["/a"]) { _ in true })
    }
}
#endif
