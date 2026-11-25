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
}
#endif
