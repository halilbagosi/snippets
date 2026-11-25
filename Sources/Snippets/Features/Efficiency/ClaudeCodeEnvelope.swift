#if !APP_STORE
import Foundation

/// Pure reading of `claude -p --output-format json` output.
///
/// Observed (claude CLI, signed out, exit code 1): stdout is one JSON object
/// with fields type ("result"), subtype, is_error, api_error_status,
/// duration_ms, duration_api_ms, num_turns, result (a string), stop_reason,
/// session_id, total_cost_usd, usage, modelUsage, permission_denials,
/// terminal_reason ("api_error"), uuid. A signed-out run reports
/// is_error=true with result "Failed to authenticate: OAuth session expired
/// and could not be refreshed". Where the schema-constrained output lands on
/// success has NOT been observed yet.
enum ClaudeCodeEnvelope {
    /// The only string matched so far, because it is the only one observed.
    static let authFailureMarker = "Failed to authenticate"

    static func isNotSignedIn(exitCode: Int32, stdout: Data) -> Bool {
        guard exitCode != 0,
              let root = (try? JSONSerialization.jsonObject(with: stdout)) as? [String: Any],
              root["is_error"] as? Bool == true,
              let result = root["result"] as? String
        else { return false }
        return result.contains(authFailureMarker)
    }
}
#endif
