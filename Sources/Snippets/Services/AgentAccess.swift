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
            defaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
            isEnabled ? start() : stop()
        }
    }

    /// Read on every write call, so flipping it takes effect without reconnecting.
    var allowsEdits: Bool {
        didSet { defaults.set(allowsEdits, forKey: Self.editsDefaultsKey) }
    }

    /// Whether this process is the one answering agents right now.
    private(set) var isServing = false

    /// Why the last `start()` failed, phrased for Settings; nil once serving or off.
    private(set) var startProblem: String?

    @ObservationIgnored private var server: MCPSocketServer?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let path: String
    @ObservationIgnored private let makeHandler: @MainActor () -> MCPSocketServer.Handler

    /// The app's preview approvals, so an agent's code edit can revoke them.
    /// Set once at launch by `SnippetsApp`.
    @ObservationIgnored var previewTrust: PreviewTrust?

    private convenience init() {
        self.init(defaults: .standard, socketPath: Self.socketPath) {
            let tools = SnippetMCPTools(
                context: SnippetsData.sharedModelContainer.mainContext,
                editsAllowed: { AgentAccess.shared.allowsEdits },
                forgetTrust: { AgentAccess.shared.previewTrust?.forget($0) }
            )
            let dispatcher = MCPDispatcher(provider: tools)
            return { dispatcher.handle(line: $0) }
        }
    }

    /// Tests pass their own defaults, socket path and handler so they never
    /// touch the user's preferences, socket or library.
    init(
        defaults: UserDefaults,
        socketPath: String,
        makeHandler: @escaping @MainActor () -> MCPSocketServer.Handler
    ) {
        self.defaults = defaults
        path = socketPath
        self.makeHandler = makeHandler
        isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        allowsEdits = defaults.bool(forKey: Self.editsDefaultsKey)
    }

    /// Start serving if enabled and not already serving. Safe to call
    /// repeatedly: flipping the switch and activating the app both retry,
    /// so serving resumes once another copy of Snippets lets go.
    func start() {
        guard isEnabled, server == nil else { return }
        let server = MCPSocketServer(path: path, handler: makeHandler())
        do {
            try server.start()
            self.server = server
            isServing = true
            startProblem = nil
        } catch {
            NSLog("Snippets: agent access could not start: \(error)")
            isServing = false
            startProblem = Self.describe(error)
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isServing = false
        startProblem = nil
    }

    nonisolated static func describe(_ error: Error) -> String {
        switch error as? UnixSocket.Failure {
        case .inUse: "Another copy of Snippets is serving agents"
        case .pathTooLong: "The agent socket path is too long"
        default: "Couldn’t start serving agents"
        }
    }

    /// What Settings' "Copy Setup Command" puts on the clipboard.
    nonisolated static func setupCommand(executablePath: String) -> String {
        "claude mcp add snippets -- '\(executablePath)' \(MCPStdioShim.flag)"
    }
}
#endif
