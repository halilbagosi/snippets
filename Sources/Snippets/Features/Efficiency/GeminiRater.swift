#if !APP_STORE
import Foundation

/// Rates a snippet by running the user's Gemini CLI headless.
///
/// Gemini has no `--json-schema`, so the schema rides in the prompt and the
/// report is dug out of the free-text `response`. Containment differs from
/// Claude Code's too — Gemini documents no switch that turns every tool off:
/// - the run happens in an empty temporary directory, so file tools see nothing;
/// - `--approval-mode default` with no TTY denies anything that needs approval
///   (writes, shell);
/// - `--allowed-mcp-server-names` names a server that cannot exist, so none of
///   the user's MCP servers start; `--extensions none` keeps extensions out.
struct GeminiRater: EfficiencyRater {
    static let executableName = "gemini"
    static let timeout: TimeInterval = 180
    /// A server name no real config uses; allow-listing only it allows none.
    static let noMCPServers = "snippets-rating-no-mcp"

    var runner: AgentProcessRunning = FoundationProcessRunner()
    var locate: @Sendable () async -> URL? = { await AgentCLILocator.shared.locate(GeminiRater.executableName) }

    static func arguments(model: String?) -> [String] {
        var args = [
            // The whole prompt arrives on stdin; Gemini appends `-p` to it.
            "-p", "Answer with the JSON object only.",
            "--output-format", "json",
            "--approval-mode", "default",
            "--allowed-mcp-server-names", noMCPServers,
            "--extensions", "none",
        ]
        if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            args += ["--model", model]
        }
        return args
    }

    /// Gemini reads cached credentials and `~/.gemini/.env` from `HOME`; API
    /// keys set in the app's own environment are passed through as well.
    static func environment(
        cliDirectory: String, home: String = NSHomeDirectory(), user: String = NSUserName(),
        inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = ClaudeCodeRater.environment(cliDirectory: cliDirectory, home: home, user: user)
        for key in passthroughKeys { if let value = inherited[key] { env[key] = value } }
        return env
    }

    static let passthroughKeys = [
        "GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_CLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT_ID",
        "GOOGLE_CLOUD_LOCATION", "GOOGLE_APPLICATION_CREDENTIALS", "GOOGLE_GENAI_USE_VERTEXAI",
    ]

    func rate(_ request: EfficiencyRequest, model: String?) async throws -> EfficiencyReport {
        guard let prompt = EfficiencyPrompt.build(for: request, includeSchema: true) else {
            throw EfficiencyRatingError.failed("\(request.language.rawValue) snippets are not rated")
        }
        guard let cli = await locate() else { throw EfficiencyRatingError.agentNotFound }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippets-rating-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true) }
        catch { throw EfficiencyRatingError.failed("could not create a working directory") }
        defer { try? FileManager.default.removeItem(at: workDir) }

        let result = try await runner.run(
            executable: cli, arguments: Self.arguments(model: model), stdin: Data(prompt.utf8),
            environment: Self.environment(cliDirectory: cli.deletingLastPathComponent().path),
            workingDirectory: workDir, timeout: Self.timeout)

        switch GeminiEnvelope.report(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr) {
        case .failure(let error): throw error
        case .success(let data): return try EfficiencyResponseParser.parse(data, ratedCode: request.code)
        }
    }
}

/// Pure reading of `gemini -p … --output-format json` output: one object with
/// `response` (the model's text), `stats`, and on failure `error`. Exit code
/// 41 is Gemini's FatalAuthenticationError.
enum GeminiEnvelope {
    static let authExitCode: Int32 = 41
    static let notSignedInMarkers = [
        "authentication", "not authenticated", "please set an auth method", "api key not valid",
        "gemini_api_key", "login required", "unauthenticated",
    ]

    static func report(exitCode: Int32, stdout: Data, stderr: Data) -> Result<Data, EfficiencyRatingError> {
        let root = (try? JSONSerialization.jsonObject(with: stdout)) as? [String: Any]
        let errorMessage = (root?["error"] as? [String: Any])?["message"] as? String
        let stderrText = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if exitCode == authExitCode { return .failure(.notSignedIn) }
        if exitCode != 0 || errorMessage != nil {
            let detail = errorMessage ?? stderrText
            let lowered = detail.lowercased()
            if notSignedInMarkers.contains(where: { lowered.contains($0) }) { return .failure(.notSignedIn) }
            return .failure(.failed(detail.isEmpty ? "exit code \(exitCode)" : String(detail.prefix(300))))
        }
        guard let root else { return .failure(.invalidResponse("output is not a JSON object")) }
        guard let response = root["response"] as? String else {
            return .failure(.invalidResponse("no response in the CLI output"))
        }
        guard let object = jsonObject(in: response) else {
            return .failure(.invalidResponse("the response holds no JSON object"))
        }
        return .success(Data(object.utf8))
    }

    /// The report object inside the model's text: the text itself, a fenced
    /// block, or the outermost `{…}` span — models wrap JSON despite being asked
    /// not to.
    static func jsonObject(in text: String) -> String? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            if let firstNewline = body.firstIndex(of: "\n") { body = String(body[body.index(after: firstNewline)...]) }
            if let close = body.range(of: "```", options: .backwards) { body = String(body[..<close.lowerBound]) }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}"), start < end else { return nil }
        let candidate = String(body[start...end])
        guard (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) is [String: Any] else { return nil }
        return candidate
    }
}
#endif
