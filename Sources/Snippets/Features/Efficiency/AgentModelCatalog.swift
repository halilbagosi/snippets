#if !APP_STORE
import Foundation

/// The models and effort levels Settings offers for a rating agent.
///
/// Each agent starts from a built-in list. For Claude Code the effort levels
/// and model aliases are then read from the installed CLI's own `--help`, so
/// the menus follow whatever version the user has. Gemini has no effort flag,
/// so it offers none.
struct AgentModelCatalog: Equatable {
    struct Option: Equatable, Hashable, Identifiable {
        /// What is passed to the CLI; empty = the agent's default.
        let value: String
        let label: String
        var id: String { value }
    }

    var models: [Option]
    var efforts: [Option]

    static let defaultOption = Option(value: "", label: "Default")

    static func builtIn(for agent: AgentClient) -> AgentModelCatalog {
        switch agent {
        case .claudeCode:
            return AgentModelCatalog(
                models: [defaultOption] + claudeModels(aliases: ["fable", "opus", "sonnet", "haiku"]),
                efforts: [defaultOption] + ["low", "medium", "high", "xhigh", "max"].map(effortOption)
            )
        case .gemini:
            return AgentModelCatalog(
                models: [
                    Option(value: "", label: "Default (auto)"),
                    Option(value: "pro", label: "Pro (latest)"),
                    Option(value: "flash", label: "Flash (latest)"),
                    Option(value: "flash-lite", label: "Flash-Lite (latest)"),
                    Option(value: "gemini-3-pro-preview", label: "gemini-3-pro-preview"),
                    Option(value: "gemini-2.5-pro", label: "gemini-2.5-pro"),
                    Option(value: "gemini-2.5-flash", label: "gemini-2.5-flash"),
                    Option(value: "gemini-2.5-flash-lite", label: "gemini-2.5-flash-lite"),
                ],
                efforts: []
            )
        default:
            return AgentModelCatalog(models: [defaultOption], efforts: [])
        }
    }

    /// Claude aliases first ("Opus (latest)"), then the current full names.
    static func claudeModels(aliases: [String]) -> [Option] {
        let full = ["claude-fable-5-2", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
        return aliases.map { Option(value: $0, label: "\($0.prefix(1).uppercased())\($0.dropFirst()) (latest)") }
            + full.map { Option(value: $0, label: $0) }
    }

    static func effortOption(_ level: String) -> Option {
        Option(value: level, label: level.prefix(1).uppercased() + level.dropFirst())
    }

    /// The catalog with Claude Code's `--help` folded in: the effort levels
    /// listed under `--effort <level>` and the aliases quoted under
    /// `--model <model>`. Anything the text does not yield keeps the built-in.
    static func claude(fromHelp help: String) -> AgentModelCatalog {
        var catalog = builtIn(for: .claudeCode)
        if let levels = effortLevels(inHelp: help), !levels.isEmpty {
            catalog.efforts = [defaultOption] + levels.map(effortOption)
        }
        let aliases = modelAliases(inHelp: help)
        if !aliases.isEmpty {
            // Keep haiku: the help text only quotes examples.
            let merged = aliases + ["fable", "opus", "sonnet", "haiku"].filter { !aliases.contains($0) }
            catalog.models = [defaultOption] + claudeModels(aliases: merged)
        }
        return catalog
    }

    /// The parenthesised list after `--effort`, e.g. "(low, medium, high)".
    static func effortLevels(inHelp help: String) -> [String]? {
        guard let flag = help.range(of: "--effort") else { return nil }
        let rest = help[flag.upperBound...].prefix(400)
        guard let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") else { return nil }
        let levels = rest[rest.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard levels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter } }) else { return nil }
        return levels
    }

    /// Single-quoted bare words in the `--model` description that are not
    /// full model names, e.g. 'fable', 'opus', 'sonnet'.
    static func modelAliases(inHelp help: String) -> [String] {
        guard let flag = help.range(of: "--model ") else { return [] }
        let section = help[flag.upperBound...].prefix(500)
        var aliases: [String] = []
        var remainder = section[...]
        while let open = remainder.firstIndex(of: "'") {
            let after = remainder.index(after: open)
            guard let close = remainder[after...].firstIndex(of: "'") else { break }
            let word = String(remainder[after..<close])
            if !word.isEmpty, !word.hasPrefix("claude-"), word.allSatisfy({ $0.isLetter }), !aliases.contains(word) {
                aliases.append(word.lowercased())
            }
            remainder = remainder[remainder.index(after: close)...]
        }
        return aliases
    }

    /// `options` plus `current` when it is set but not listed — a model typed
    /// in an older version must stay selectable rather than vanish.
    static func including(_ current: String, in options: [Option]) -> [Option] {
        guard !current.isEmpty, !options.contains(where: { $0.value == current }) else { return options }
        return options + [Option(value: current, label: current)]
    }
}

/// Reads `claude --help` from the located CLI, off the main thread. Nil when
/// it cannot run in time.
enum AgentHelpReader {
    static func help(executable: URL, runner: AgentProcessRunning = FoundationProcessRunner()) async -> String? {
        let result = try? await runner.run(
            executable: executable, arguments: ["--help"], stdin: Data(),
            environment: ClaudeCodeRater.environment(cliDirectory: executable.deletingLastPathComponent().path),
            workingDirectory: FileManager.default.temporaryDirectory, timeout: 10)
        guard let result, result.exitCode == 0 else { return nil }
        return String(decoding: result.stdout, as: UTF8.self)
    }
}
#endif
