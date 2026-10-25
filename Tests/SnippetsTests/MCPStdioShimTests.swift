#if !APP_STORE
import XCTest
@testable import Snippets

final class MCPStdioShimTests: XCTestCase {
    func test_errorReply_answersRequestsWithTheMessage() throws {
        let line = try XCTUnwrap(MCPStdioShim.errorReply(
            to: #"{"jsonrpc":"2.0","id":7,"method":"initialize"}"#, message: MCPStdioShim.accessOffMessage
        ))
        let reply = try JSONValue.parse(line)
        XCTAssertEqual(reply["id"], 7)
        XCTAssertEqual(reply["error"]?["code"], .number(Double(JSONRPCErrorCode.serverUnavailable)))
        XCTAssertEqual(reply["error"]?["message"]?.stringValue, MCPStdioShim.accessOffMessage)
    }

    func test_errorReply_ignoresNotificationsAndGarbage() {
        XCTAssertNil(MCPStdioShim.errorReply(to: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, message: "x"))
        XCTAssertNil(MCPStdioShim.errorReply(to: "not json", message: "x"))
    }

    func test_messagesMatchTheSpec() {
        XCTAssertEqual(MCPStdioShim.accessOffMessage, "Agent access is off — enable it in Snippets ▸ Settings ▸ Agents.")
        XCTAssertEqual(MCPStdioShim.unreachableMessage, "Couldn't reach Snippets. Open the app and try again.")
    }

    func test_setupCommand_quotesThePathAndPassesTheFlag() {
        XCTAssertEqual(
            AgentAccess.setupCommand(executablePath: "/Applications/Snippets.app/Contents/MacOS/Snippets"),
            "claude mcp add snippets -- '/Applications/Snippets.app/Contents/MacOS/Snippets' --mcp-stdio"
        )
    }

    func test_launchArguments_backgroundTheAppAndMarkTheLaunch() {
        let args = MCPStdioShim.launchArguments(bundlePath: "/A/Snippets.app")
        XCTAssertEqual(args.prefix(3), ["-g", "-a", "/A/Snippets.app"])
        XCTAssertEqual(args.suffix(2), ["--args", MCPStdioShim.launchedByAgentFlag])
    }

    func test_socketPathFitsInSockaddr() {
        XCTAssertNoThrow(try UnixSocket.address(path: AgentAccess.socketPath))
        XCTAssertTrue(AgentAccess.socketPath.hasSuffix("/Application Support/Snippets/mcp.sock"))
    }
}
#endif
