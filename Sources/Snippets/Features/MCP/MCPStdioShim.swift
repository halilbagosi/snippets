#if !APP_STORE
import Darwin
import Foundation

/// `Snippets --mcp-stdio`: the process an agent launches. It serves nothing
/// itself. It relays stdin/stdout to the running app's socket, starting the
/// app first if needed, so every tool runs on the app's one model context and
/// the gallery updates live.
enum MCPStdioShim {
    static let flag = "--mcp-stdio"
    static let accessOffMessage = "Agent access is off — enable it in Snippets ▸ Settings ▸ Agents."
    static let unreachableMessage = "Couldn't reach Snippets. Open the app and try again."
    /// Passed to an app the shim launches, so it stays in the background.
    static let launchedByAgentFlag = "--launched-by-agent"
    private static let launchTimeout: TimeInterval = 5

    @MainActor
    static func run() -> Never {
        // A client that closes its read end should end us cleanly, not by signal.
        signal(SIGPIPE, SIG_IGN)
        guard UserDefaults.standard.bool(forKey: AgentAccess.enabledDefaultsKey) else {
            answerWithError(accessOffMessage)
        }
        let path = AgentAccess.socketPath
        if let fd = UnixSocket.connect(path: path) ?? launchAppAndConnect(path: path) {
            relay(fd)
        }
        answerWithError(unreachableMessage)
    }

    /// The reply to one client line when there's no app to relay to, or nil
    /// for notifications and garbage, which get no reply.
    static func errorReply(to line: String, message: String) -> String? {
        guard let request = try? JSONValue.parse(line), request["method"] != nil, let id = request["id"] else {
            return nil
        }
        return MCPDispatcher.errorResponse(id: id, code: JSONRPCErrorCode.serverUnavailable, message: message).serialized()
    }

    static func launchArguments(bundlePath: String) -> [String] {
        ["-g", "-a", bundlePath, "--args", launchedByAgentFlag]
    }

    private static func launchAppAndConnect(path: String) -> Int32? {
        let open = Process()
        open.executableURL = URL(filePath: "/usr/bin/open")
        open.arguments = launchArguments(bundlePath: Bundle.main.bundleURL.path(percentEncoded: false))
        // stdout belongs to the MCP client; open must not write to it.
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.nullDevice
        guard (try? open.run()) != nil else { return nil }

        let deadline = Date.now.addingTimeInterval(launchTimeout)
        while Date.now < deadline {
            if let fd = UnixSocket.connect(path: path) { return fd }
            usleep(200_000)
        }
        return nil
    }

    private static func relay(_ fd: Int32) -> Never {
        let upstream = Thread {
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = read(STDIN_FILENO, &chunk, chunk.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0, UnixSocket.writeAll(fd, Data(chunk[0..<count])) else { break }
            }
            // The client is done sending. Half-close so the app still answers
            // what's in flight, then closes its end, which ends the loop below.
            shutdown(fd, SHUT_WR)
        }
        upstream.start()

        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0, UnixSocket.writeAll(STDOUT_FILENO, Data(chunk[0..<count])) else { break }
        }
        exit(0)
    }

    /// Answer every request with `message` until the client hangs up, so it
    /// shows the user why instead of timing out.
    private static func answerWithError(_ message: String) -> Never {
        while let line = readLine() {
            if let reply = errorReply(to: line, message: message) {
                print(reply)
                fflush(stdout)
            }
        }
        exit(0)
    }
}
#endif
