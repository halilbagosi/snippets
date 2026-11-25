#if !APP_STORE
import XCTest
@testable import Snippets

final class ClaudeCodeRaterTests: XCTestCase {
    private struct FakeRunner: AgentProcessRunning {
        var outcome: @Sendable () async throws -> AgentProcessResult
        var onRun: @Sendable (URL, [String], Data, [String: String], URL) -> Void = { _, _, _, _, _ in }
        func run(executable: URL, arguments: [String], stdin: Data, environment: [String: String],
                 workingDirectory: URL, timeout: TimeInterval) async throws -> AgentProcessResult {
            onRun(executable, arguments, stdin, environment, workingDirectory)
            return try await outcome()
        }
    }

    private let request = EfficiencyRequest(title: "t", language: .swift, code: "let x = 1\n", dependencies: [])
    private let cli = URL(fileURLWithPath: "/opt/tools/claude")

    private func rater(_ runner: FakeRunner, cli: URL? = URL(fileURLWithPath: "/opt/tools/claude")) -> ClaudeCodeRater {
        ClaudeCodeRater(runner: runner, locate: { cli })
    }

    private static func ok(_ report: String) -> AgentProcessResult {
        AgentProcessResult(exitCode: 0, stdout: Data(#"{"is_error":false,"structured_output":\#(report)}"#.utf8), stderr: Data())
    }

    private func assertThrows(_ expected: EfficiencyRatingError, _ rater: ClaudeCodeRater,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await rater.rate(request, model: nil); XCTFail("expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? EfficiencyRatingError, expected, file: file, line: line) }
    }

    func test_successParsesStructuredOutput() async throws {
        let r = try await rater(FakeRunner(outcome: {
            Self.ok(#"{"applicable":true,"score":88,"summary":"fine","suggestions":[{"title":"T","impact":"low","explanation":"E","before":"let x = 1","after":"let x = 2"}]}"#)
        })).rate(request, model: nil)
        XCTAssertEqual(r.score, 88)
        XCTAssertEqual(r.suggestions.count, 1)
    }

    func test_argumentsEnvironmentAndPromptOnStdin() async throws {
        let seen = Box<(URL, [String], Data, [String: String], URL)?>(nil)
        var runner = FakeRunner(outcome: { ClaudeCodeRaterTests.ok(#"{"applicable":true,"score":1,"summary":"s"}"#) })
        runner.onRun = { seen.value = ($0, $1, $2, $3, $4) }
        _ = try await rater(runner).rate(request, model: " sonnet ")
        let (exe, args, stdin, env, cwd) = try XCTUnwrap(seen.value)
        XCTAssertEqual(exe.path, "/opt/tools/claude")
        XCTAssertEqual(Array(args.prefix(3)), ["-p", "--output-format", "json"])
        XCTAssertEqual(args[args.firstIndex(of: "--tools")! + 1], "")
        XCTAssertTrue(args.contains("--strict-mcp-config"))
        XCTAssertEqual(args[args.firstIndex(of: "--mcp-config")! + 1], #"{"mcpServers":{}}"#)
        XCTAssertTrue(args.contains("--no-session-persistence"))
        XCTAssertEqual(args[args.firstIndex(of: "--setting-sources")! + 1], "")
        XCTAssertTrue(args.contains("--disable-slash-commands"))
        XCTAssertEqual(args[args.firstIndex(of: "--json-schema")! + 1], EfficiencyPrompt.schema)
        XCTAssertEqual(args.suffix(2), ["--model", "sonnet"])  // model stays last
        XCTAssertFalse(String(decoding: stdin, as: UTF8.self).isEmpty)
        XCTAssertFalse(args.contains { $0.contains("let x = 1") }, "code must not travel in argv")
        XCTAssertEqual(Set(env.keys), ["HOME", "USER", "LOGNAME", "PATH", "LANG"])
        XCTAssertEqual(env["PATH"], "/opt/tools:/usr/bin:/bin")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cwd.path), "temp cwd removed afterwards")
        XCTAssertFalse(ClaudeCodeRater.arguments(model: nil).contains("--model"))
    }

    func test_notFound() async {
        await assertThrows(.agentNotFound, rater(FakeRunner(outcome: { fatalError() }), cli: nil))
    }

    func test_notSignedInFromEnvelopeAndStderr() async {
        let env = AgentProcessResult(exitCode: 1, stdout: Data(#"{"is_error":true,"result":"Not logged in · Please run /login"}"#.utf8), stderr: Data())
        await assertThrows(.notSignedIn, rater(FakeRunner(outcome: { env })))
        let err = AgentProcessResult(exitCode: 1, stdout: Data(), stderr: Data("Error: Invalid API key".utf8))
        await assertThrows(.notSignedIn, rater(FakeRunner(outcome: { err })))
    }

    func test_otherCLIErrorIsFailedWithMessage() async {
        let r = AgentProcessResult(exitCode: 1, stdout: Data(#"{"is_error":true,"api_error_status":429,"result":"out of credits"}"#.utf8), stderr: Data())
        await assertThrows(.failed("out of credits"), rater(FakeRunner(outcome: { r })))
        let bare = AgentProcessResult(exitCode: 2, stdout: Data(), stderr: Data())
        await assertThrows(.failed("exit code 2"), rater(FakeRunner(outcome: { bare })))
    }

    func test_invalidEnvelopesAndReports() async {
        let noStructured = AgentProcessResult(exitCode: 0, stdout: Data(#"{"is_error":false,"result":"{}"}"#.utf8), stderr: Data())
        await assertThrows(.invalidResponse("no structured_output in the CLI output"), rater(FakeRunner(outcome: { noStructured })))
        let garbage = AgentProcessResult(exitCode: 0, stdout: Data("nope".utf8), stderr: Data())
        await assertThrows(.invalidResponse("output is not a JSON object"), rater(FakeRunner(outcome: { garbage })))
        let badScore = Self.ok(#"{"applicable":true,"score":500,"summary":"s"}"#)
        do { _ = try await rater(FakeRunner(outcome: { badScore })).rate(request, model: nil); XCTFail() }
        catch { guard case .invalidResponse = error as? EfficiencyRatingError else { return XCTFail("\(error)") } }
    }

    func test_runnerErrorsPropagate() async {
        await assertThrows(.timedOut, rater(FakeRunner(outcome: { throw EfficiencyRatingError.timedOut })))
        await assertThrows(.cancelled, rater(FakeRunner(outcome: { throw EfficiencyRatingError.cancelled })))
    }

    func test_unratableLanguageNeverRuns() async {
        let json = EfficiencyRequest(title: "t", language: .json, code: "{}", dependencies: [])
        do { _ = try await rater(FakeRunner(outcome: { fatalError() })).rate(json, model: nil); XCTFail() }
        catch { guard case .failed = error as? EfficiencyRatingError else { return XCTFail("\(error)") } }
    }

    func test_realRunnerTimeoutCancelAndCapture() async throws {
        let runner = FoundationProcessRunner(killGrace: 0.5)
        let tmp = FileManager.default.temporaryDirectory
        let sh = URL(fileURLWithPath: "/bin/sh")

        let echoed = try await runner.run(executable: sh, arguments: ["-c", "cat; echo err >&2"], stdin: Data("hello".utf8),
                                          environment: [:], workingDirectory: tmp, timeout: 10)
        XCTAssertEqual(String(decoding: echoed.stdout, as: UTF8.self), "hello")
        XCTAssertEqual(String(decoding: echoed.stderr, as: UTF8.self), "err\n")

        do {
            _ = try await runner.run(executable: sh, arguments: ["-c", "sleep 30"], stdin: Data(),
                                     environment: [:], workingDirectory: tmp, timeout: 0.3)
            XCTFail("expected timeout")
        } catch { XCTAssertEqual(error as? EfficiencyRatingError, .timedOut) }

        let task = Task { try await runner.run(executable: sh, arguments: ["-c", "trap '' TERM; sleep 30"], stdin: Data(),
                                               environment: [:], workingDirectory: tmp, timeout: 60) }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancel") }
        catch { XCTAssertEqual(error as? EfficiencyRatingError, .cancelled) }
    }
}

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
#endif
