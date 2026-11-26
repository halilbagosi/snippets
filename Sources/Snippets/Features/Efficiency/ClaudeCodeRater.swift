#if !APP_STORE
import Foundation

/// Rates a snippet by running the user's Claude Code CLI headless with every
/// tool, MCP server and saved session switched off (verified by hand: with
/// `--tools ""` the only tool the model sees is the internal StructuredOutput).
struct ClaudeCodeRater: EfficiencyRater {
    static let executableName = "claude"
    static let timeout: TimeInterval = 120

    var runner: AgentProcessRunning = FoundationProcessRunner()
    /// Resolves the CLI; injectable for tests.
    var locate: @Sendable () async -> URL? = { await AgentCLILocator.shared.locate(ClaudeCodeRater.executableName) }

    static func arguments(model: String?, effort: String? = nil) -> [String] {
        var args = [
            "-p", "--output-format", "json", "--json-schema", EfficiencyPrompt.schema,
            "--tools", "", "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
            "--no-session-persistence",
            // Keep the user's hooks, plugins and skills out of a run that handles untrusted code.
            "--setting-sources", "", "--disable-slash-commands",
        ]
        if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            args += ["--model", model]
        }
        if let effort = effort?.trimmingCharacters(in: .whitespacesAndNewlines), !effort.isEmpty {
            args += ["--effort", effort]
        }
        return args
    }

    /// `USER` is required: the CLI finds its keychain credentials through it
    /// and otherwise reports "Not logged in".
    static func environment(cliDirectory: String, home: String = NSHomeDirectory(), user: String = NSUserName()) -> [String: String] {
        ["HOME": home, "USER": user, "LOGNAME": user, "PATH": "\(cliDirectory):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "LANG": "en_US.UTF-8"]
    }

    func rate(_ request: EfficiencyRequest, model: String?) async throws -> EfficiencyReport {
        try await rate(request, model: model, effort: nil)
    }

    func rate(_ request: EfficiencyRequest, model: String?, effort: String?) async throws -> EfficiencyReport {
        guard let prompt = EfficiencyPrompt.build(for: request) else {
            throw EfficiencyRatingError.failed("\(request.language.rawValue) snippets are not rated")
        }
        guard let cli = await locate() else { throw EfficiencyRatingError.agentNotFound }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippets-rating-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true) }
        catch { throw EfficiencyRatingError.failed("could not create a working directory") }
        defer { try? FileManager.default.removeItem(at: workDir) }

        let result = try await runner.run(
            executable: cli, arguments: Self.arguments(model: model, effort: effort), stdin: Data(prompt.utf8),
            environment: Self.environment(cliDirectory: cli.deletingLastPathComponent().path),
            workingDirectory: workDir, timeout: Self.timeout)

        switch ClaudeCodeEnvelope.report(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr) {
        case .failure(let error): throw error
        case .success(let data): return try EfficiencyResponseParser.parse(data, ratedCode: request.code)
        }
    }
}
#endif
