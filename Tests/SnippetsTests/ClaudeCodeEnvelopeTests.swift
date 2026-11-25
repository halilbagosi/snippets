#if !APP_STORE
import XCTest
@testable import Snippets

final class ClaudeCodeEnvelopeTests: XCTestCase {
    func test_envelopeNotSignedIn() {
        let out = Data(#"{"type":"result","is_error":true,"result":"Failed to authenticate: OAuth session expired"}"#.utf8)
        XCTAssertTrue(ClaudeCodeEnvelope.isNotSignedIn(exitCode: 1, stdout: out))
        XCTAssertFalse(ClaudeCodeEnvelope.isNotSignedIn(exitCode: 0, stdout: out))
        XCTAssertFalse(ClaudeCodeEnvelope.isNotSignedIn(exitCode: 1, stdout: Data(#"{"is_error":true,"result":"boom"}"#.utf8)))
        XCTAssertFalse(ClaudeCodeEnvelope.isNotSignedIn(exitCode: 1, stdout: Data("garbage".utf8)))
    }

    func test_notLoggedInVariantAndStderr() {
        let out = Data(#"{"is_error":true,"result":"Not logged in · Please run /login"}"#.utf8)
        XCTAssertTrue(ClaudeCodeEnvelope.isNotSignedIn(exitCode: 1, stdout: out))
        XCTAssertTrue(ClaudeCodeEnvelope.isNotSignedIn(exitCode: 1, stdout: Data(), stderr: Data("Invalid API key".utf8)))
        XCTAssertFalse(ClaudeCodeEnvelope.isNotSignedIn(exitCode: 0, stdout: Data(), stderr: Data("Invalid API key".utf8)))
    }

    func test_reportExtractsStructuredOutput() throws {
        let out = Data(#"{"is_error":false,"result":"ignored","structured_output":{"applicable":true,"score":3,"summary":"s"}}"#.utf8)
        let data = try ClaudeCodeEnvelope.report(exitCode: 0, stdout: out, stderr: Data()).get()
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["score"] as? Int, 3)
    }
}
#endif
