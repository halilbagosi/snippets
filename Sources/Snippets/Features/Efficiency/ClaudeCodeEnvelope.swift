#if !APP_STORE
import Foundation

/// Pure reading of `claude -p --output-format json` output.
///
/// Observed envelope (one JSON object on stdout; exit 0 on success, 1 on error):
///   type "result", subtype, is_error, api_error_status, duration_ms,
///   duration_api_ms, num_turns, result (string), stop_reason, session_id,
///   total_cost_usd, usage, modelUsage, permission_denials, terminal_reason,
///   uuid, and on success `structured_output` — the schema-constrained report
///   as a JSON *object*. `result` also holds the same JSON as a string; it is
///   not used. The CLI accepted the schema (maxLength / maxItems / min / max)
///   and produced conforming output; the parser still re-validates everything.
///
/// Observed failures (all `is_error: true`, exit 1, empty stderr):
///   signed out, expired session: result "Failed to authenticate: OAuth session expired and could not be refreshed"
///   signed out, no credentials found: result "Not logged in · Please run /login"
///   out of credits: api_error_status 429, result "You're out of usage credits. …"
/// Credentials are found through the keychain via the `USER` environment
/// variable; without it a spawned CLI reports "Not logged in".
enum ClaudeCodeEnvelope {
    /// Matched case-insensitively against the envelope's `result` and against
    /// stderr: the first two were observed in the envelope; the rest are
    /// heuristics for stderr (decision 13) that were not observed.
    static let notSignedInMarkers = [
        "failed to authenticate", "not logged in", "please run /login",
        "invalid api key", "no api key", "authentication_error", "please log in",
    ]

    static func isNotSignedIn(exitCode: Int32, stdout: Data, stderr: Data = Data()) -> Bool {
        guard exitCode != 0 else { return false }
        if matches(String(decoding: stderr, as: UTF8.self)) { return true }
        guard let root = object(stdout), root["is_error"] as? Bool == true,
              let result = root["result"] as? String else { return false }
        return matches(result)
    }

    /// The report object as JSON data, or the error the run maps to.
    static func report(exitCode: Int32, stdout: Data, stderr: Data) -> Result<Data, EfficiencyRatingError> {
        if isNotSignedIn(exitCode: exitCode, stdout: stdout, stderr: stderr) { return .failure(.notSignedIn) }
        let root = object(stdout)
        if exitCode != 0 || root?["is_error"] as? Bool == true {
            let detail = (root?["result"] as? String)
                ?? String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.failed(detail.isEmpty ? "exit code \(exitCode)" : String(detail.prefix(300))))
        }
        guard let root else { return .failure(.invalidResponse("output is not a JSON object")) }
        guard let report = root["structured_output"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: report)
        else { return .failure(.invalidResponse("no structured_output in the CLI output")) }
        return .success(data)
    }

    private static func matches(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return notSignedInMarkers.contains { lowered.contains($0) }
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
#endif
