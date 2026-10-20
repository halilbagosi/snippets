#if !APP_STORE
import Foundation
import Observation

/// The Settings switches for MCP agent access, and the socket server's
/// lifecycle. Opt-in and off by default: nothing listens until the user
/// turns it on.
@MainActor
@Observable
final class AgentAccess {
    static let shared = AgentAccess()

    nonisolated static let enabledDefaultsKey = "agentAccess.enabled"
    nonisolated static let editsDefaultsKey = "agentAccess.allowsEdits"

    /// This build isn't sandboxed, so this is the user's own Application Support.
    nonisolated static var socketPath: String {
        URL.applicationSupportDirectory.appending(path: "Snippets/mcp.sock").path(percentEncoded: false)
    }

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            isEnabled ? start() : stop()
        }
    }

    /// Read on every write call, so flipping it takes effect without reconnecting.
    var allowsEdits: Bool {
        didSet { UserDefaults.standard.set(allowsEdits, forKey: Self.editsDefaultsKey) }
    }

    @ObservationIgnored private var server: MCPSocketServer?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        allowsEdits = UserDefaults.standard.bool(forKey: Self.editsDefaultsKey)
    }

    /// Start serving if enabled. Safe to call repeatedly.
    func start() {
        guard isEnabled, server == nil else { return }
        let tools = SnippetMCPTools(
            context: SnippetsData.sharedModelContainer.mainContext,
            editsAllowed: { AgentAccess.shared.allowsEdits }
        )
        let dispatcher = MCPDispatcher(provider: tools)
        let server = MCPSocketServer(path: Self.socketPath) { dispatcher.handle(line: $0) }
        do {
            try server.start()
            self.server = server
        } catch {
            // Most likely another copy of Snippets (e.g. a debug build) owns the socket.
            NSLog("Snippets: agent access could not start: \(error)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
    }

    /// What Settings' "Copy Setup Command" puts on the clipboard.
    nonisolated static func setupCommand(executablePath: String) -> String {
        "claude mcp add snippets -- '\(executablePath)' \(MCPStdioShim.flag)"
    }
}
#endif
