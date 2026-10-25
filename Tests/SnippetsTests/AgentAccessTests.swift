#if !APP_STORE
import XCTest
@testable import Snippets

@MainActor
final class AgentAccessTests: XCTestCase {
    private var dir: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var path: String { dir.appending(path: "mcp.sock").path(percentEncoded: false) }

    override func setUp() async throws {
        // Short: sockaddr_un paths are capped at 104 bytes.
        dir = URL(filePath: NSTemporaryDirectory()).appending(path: String(UUID().uuidString.prefix(8)))
        suiteName = "AgentAccessTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeAccess() -> AgentAccess {
        AgentAccess(defaults: defaults, socketPath: path) { { _ in nil } }
    }

    func testOffByDefaultAndStartDoesNothing() {
        let access = makeAccess()
        access.start()
        XCTAssertFalse(access.isEnabled)
        XCTAssertFalse(access.isServing)
        XCTAssertNil(access.startProblem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testToggleOnStartsAndToggleOffStops() {
        let access = makeAccess()
        access.isEnabled = true
        XCTAssertTrue(access.isServing)
        XCTAssertNil(access.startProblem)
        XCTAssertTrue(defaults.bool(forKey: AgentAccess.enabledDefaultsKey))
        let fd = UnixSocket.connect(path: path)
        XCTAssertNotNil(fd)
        fd.map { _ = close($0) }

        access.isEnabled = false
        XCTAssertFalse(access.isServing)
        XCTAssertNil(UnixSocket.connect(path: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testSocketInUseSetsProblemAndRetrySucceedsOnceFreed() {
        let other = MCPSocketServer(path: path) { _ in nil }
        XCTAssertNoThrow(try other.start())

        let access = makeAccess()
        access.isEnabled = true
        XCTAssertFalse(access.isServing)
        XCTAssertEqual(access.startProblem, "Another copy of Snippets is serving agents")

        // Activating the app retries; still taken, still the same problem.
        access.start()
        XCTAssertFalse(access.isServing)

        other.stop()
        access.start()
        XCTAssertTrue(access.isServing)
        XCTAssertNil(access.startProblem)
        access.stop()
    }

    func testToggleOffClearsProblem() throws {
        let other = MCPSocketServer(path: path) { _ in nil }
        try other.start()
        defer { other.stop() }

        let access = makeAccess()
        access.isEnabled = true
        XCTAssertNotNil(access.startProblem)
        access.isEnabled = false
        XCTAssertNil(access.startProblem)
    }

    func testEnabledPreferenceIsReadAtInit() {
        defaults.set(true, forKey: AgentAccess.enabledDefaultsKey)
        let access = makeAccess()
        XCTAssertTrue(access.isEnabled)
        XCTAssertFalse(access.isServing) // nothing serves until start()
        access.start()
        XCTAssertTrue(access.isServing)
        access.stop()
    }
}
#endif
