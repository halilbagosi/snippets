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
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locate: (String) async -> URL?

    /// On by default; the panel still needs the CLI to be found.
    var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled) } }
    var agent: AgentClient { didSet { defaults.set(agent.rawValue, forKey: Key.agent) } }
    /// Where the chosen agent's CLI was last found; nil until `refreshCLIPath`
    /// finds it.
    private(set) var cliPath: URL?

    // Read-through to UserDefaults; `access` / `withMutation` keep SwiftUI informed.
    private var modelVersion = 0
    private var consentVersion = 0

    init(
        defaults: UserDefaults = .standard,
        locate: @escaping (String) async -> URL? = { await AgentCLILocator.shared.locate($0) }
    ) {
        self.defaults = defaults
        self.locate = locate
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
        agent == .claudeCode ? ClaudeCodeRater.executableName : nil
    }

    /// Resolves the chosen agent's CLI (cached by the locator).
    func refreshCLIPath() async {
        guard let name = Self.executableName(for: agent) else { cliPath = nil; return }
        cliPath = await locate(name)
    }
}
#endif
