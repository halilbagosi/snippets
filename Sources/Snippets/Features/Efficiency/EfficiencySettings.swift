#if !APP_STORE
import Foundation
import Observation

/// The Efficiency Rating settings: on/off, which agent, its model override,
/// per-agent consent, and where the agent's CLI was found. Plain `UserDefaults`
/// keys prefixed `efficiency.`; the store is injected so tests never touch
/// `.standard`.
@MainActor @Observable
final class EfficiencySettings {
    private enum Key {
        static let enabled = "efficiency.enabled"
        static let agent = "efficiency.agent"
        static func model(_ agent: AgentClient) -> String { "efficiency.model.\(agent.rawValue)" }
        static func consented(_ agent: AgentClient) -> String { "efficiency.consented.\(agent.rawValue)" }
        static func effort(_ agent: AgentClient) -> String { "efficiency.effort.\(agent.rawValue)" }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locate: (String) async -> URL?
    @ObservationIgnored private let relocate: (String) async -> URL?

    /// On by default; the panel still needs the CLI to be found.
    var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled) } }
    var agent: AgentClient {
        didSet {
            defaults.set(agent.rawValue, forKey: Key.agent)
            // The old agent's path must not make the panel look available.
            guard agent != oldValue else { return }
            cliPath = nil
            Task { await refreshCLIPath() }
        }
    }
    /// Where the chosen agent's CLI was last found; nil until `refreshCLIPath`
    /// finds it.
    private(set) var cliPath: URL?

    // Read-through to UserDefaults; `access` / `withMutation` keep SwiftUI informed.
    private var modelVersion = 0
    private var consentVersion = 0

    init(
        defaults: UserDefaults = .standard,
        locate: @escaping (String) async -> URL? = { await AgentCLILocator.shared.locate($0) },
        relocate: @escaping (String) async -> URL? = { await AgentCLILocator.shared.refresh($0) }
    ) {
        self.defaults = defaults
        self.locate = locate
        self.relocate = relocate
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        agent = defaults.string(forKey: Key.agent).flatMap(AgentClient.init(rawValue:)) ?? .claudeCode
    }

    /// Empty = the agent's default model.
    func model(for agent: AgentClient) -> String {
        _ = modelVersion
        return defaults.string(forKey: Key.model(agent)) ?? ""
    }

    func setModel(_ model: String, for agent: AgentClient) {
        defaults.set(model, forKey: Key.model(agent))
        modelVersion += 1
    }

    /// The override to pass to the rater; nil when empty.
    func modelOverride(for agent: AgentClient) -> String? {
        let trimmed = model(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Empty = the agent's default effort.
    func effort(for agent: AgentClient) -> String {
        _ = modelVersion
        return defaults.string(forKey: Key.effort(agent)) ?? ""
    }

    func setEffort(_ effort: String, for agent: AgentClient) {
        defaults.set(effort, forKey: Key.effort(agent))
        modelVersion += 1
    }

    /// The effort to pass to the rater; nil when empty.
    func effortOverride(for agent: AgentClient) -> String? {
        let trimmed = effort(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func isConsented(_ agent: AgentClient) -> Bool {
        _ = consentVersion
        return defaults.bool(forKey: Key.consented(agent))
    }

    func grantConsent(for agent: AgentClient) {
        defaults.set(true, forKey: Key.consented(agent))
        consentVersion += 1
    }

    /// The executable the agent is found by.
    static func executableName(for agent: AgentClient) -> String? {
        switch agent {
        case .claudeCode: ClaudeCodeRater.executableName
        case .gemini: GeminiRater.executableName
        default: nil
        }
    }

    /// Resolves the chosen agent's CLI (cached by the locator).
    func refreshCLIPath() async { await resolveCLIPath(using: locate) }

    /// Like `refreshCLIPath`, but bypasses the locator's cache (including a
    /// cached "not found"). For Settings, where the user may have just
    /// installed the CLI.
    func forceRefreshCLIPath() async { await resolveCLIPath(using: relocate) }

    private func resolveCLIPath(using find: (String) async -> URL?) async {
        let requested = agent
        guard let name = Self.executableName(for: requested) else { cliPath = nil; return }
        let found = await find(name)
        // The agent may have been switched while the lookup ran.
        if agent == requested { cliPath = found }
    }
}
#endif
