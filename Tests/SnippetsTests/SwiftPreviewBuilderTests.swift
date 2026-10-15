#if !APP_STORE
import XCTest
@testable import Snippets

final class SwiftPreviewBuilderTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftPreviewBuilderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func test_promoteArtifact_movesTempToFinal() throws {
        let dir = try makeTempDirectory()
        let temp = dir.appendingPathComponent("a.dylib.tmp-x")
        let final = dir.appendingPathComponent("a.dylib")
        try Data("built".utf8).write(to: temp)

        try SwiftPreviewBuilder.promoteArtifact(at: temp, to: final)

        XCTAssertEqual(try String(contentsOf: final, encoding: .utf8), "built")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
    }

    func test_promoteArtifact_whenDestinationExists_discardsTempAndKeepsExisting() throws {
        let dir = try makeTempDirectory()
        let temp = dir.appendingPathComponent("a.dylib.tmp-x")
        let final = dir.appendingPathComponent("a.dylib")
        try Data("loser".utf8).write(to: temp)
        try Data("winner".utf8).write(to: final)

        try SwiftPreviewBuilder.promoteArtifact(at: temp, to: final)

        XCTAssertEqual(try String(contentsOf: final, encoding: .utf8), "winner")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
    }

    /// Regression for the poisoned-cache bug: a corrupt dylib at the cache
    /// path used to fail dlopen forever; the builder must now delete it and
    /// recompile. Integration test — invokes swiftc once on a tiny snippet.
    func test_build_recoversFromCorruptCachedDylib() async throws {
        try XCTSkipUnless(SwiftToolchain.isAvailable, "Swift toolchain not available")

        // Unique source so the hash has never been compiled or dlopen'd
        // before in this process or cache directory.
        let marker = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let code = "struct P\(marker): View { var body: some View { Text(\"hi\") } }"
        let harness = try SwiftPreviewHarness.make(entry: code, helpers: [])
        let cacheDirectory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SnippetPreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let dylibURL = cacheDirectory.appendingPathComponent("\(harness.hash).dylib")
        try Data("not a dylib".utf8).write(to: dylibURL)
        addTeardownBlock {
            SwiftPreviewCacheIntegrity.discard(dylibURL) // the dylib and its tag
            try? FileManager.default.removeItem(
                at: cacheDirectory.appendingPathComponent("\(harness.hash).swift")
            )
        }

        _ = try await SwiftPreviewBuilder.shared.build(code: code)

        let recovered = try Data(contentsOf: dylibURL)
        XCTAssertNotEqual(recovered, Data("not a dylib".utf8))
    }

    // MARK: Builds end to end (invoke swiftc)

    /// A builder whose cache is a temp directory, so these runs don't leave
    /// artifacts in the real preview cache.
    private func makeBuilder() throws -> SwiftPreviewBuilder {
        SwiftPreviewBuilder(cacheDirectory: try makeTempDirectory())
    }

    func test_build_consoleSnippet_runsAndCapturesOutput() async throws {
        try XCTSkipUnless(SwiftToolchain.isAvailable, "Swift toolchain not available")
        let marker = UUID().uuidString
        let output = try await makeBuilder().build(code: """
        extension Comparable {
            func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
        }
        print(1.4.clamped(to: 0...1), "\(marker)")
        """)
        guard case .console(let run) = output else { return XCTFail("expected a console run") }
        XCTAssertEqual(run.output, "1.0 \(marker)\n")
        XCTAssertEqual(run.exitStatus, 0)
        XCTAssertFalse(run.timedOut)
    }

    func test_build_previewBlockView_loadsAHostingView() async throws {
        try XCTSkipUnless(SwiftToolchain.isAvailable, "Swift toolchain not available")
        let marker = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let output = try await makeBuilder().build(code: """
        struct Counter\(marker): View {
            @Binding var value: Int
            var body: some View { Stepper("\\(value)", value: $value) }
        }
        #Preview {
            @Previewable @State var value = 3
            Counter\(marker)(value: $value)
        }
        """)
        guard case .view(let makeView) = output else { return XCTFail("expected a view") }
        let view = await MainActor.run { makeView() }
        XCTAssertNotNil(view)
    }

    /// Regression: diagnostics were read only after swiftc exited, so a
    /// snippet with enough errors to fill the 64 KB pipe hung "compiling…"
    /// forever.
    func test_build_withHugeDiagnostics_failsInsteadOfHanging() async throws {
        try XCTSkipUnless(SwiftToolchain.isAvailable, "Swift toolchain not available")
        let lines = (1...1500).map { "        Text(undefined\($0))" }.joined(separator: "\n")
        let code = """
        struct ContentView: View {
            var body: some View {
                VStack {
        \(lines)
                }
            }
        }
        // \(UUID().uuidString)
        """
        let start = Date()
        do {
            _ = try await makeBuilder().build(code: code)
            XCTFail("expected a compile failure")
        } catch SwiftPreviewBuilder.BuildError.compileFailed(let message) {
            XCTAssertTrue(message.contains("snippet:4:"), "diagnostics should point at snippet lines")
            XCTAssertTrue(message.contains("more lines"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 60)
    }

    func test_compileArguments_libraryForViews_executableForConsole() throws {
        let source = URL(fileURLWithPath: "/tmp/s.swift"), output = URL(fileURLWithPath: "/tmp/o")
        let view = SwiftPreviewBuilder.compileArguments(
            for: try SwiftPreviewHarness.make(code: "struct A: View { var body: some View { Text(\"a\") } }"),
            source: source, output: output
        )
        XCTAssertTrue(view.contains("-emit-library"))
        XCTAssertTrue(view.contains("-parse-as-library"))
        XCTAssertTrue(view.contains("-diagnostic-style=llvm"))

        let console = SwiftPreviewBuilder.compileArguments(
            for: try SwiftPreviewHarness.make(code: "print(1)"), source: source, output: output
        )
        XCTAssertFalse(console.contains("-emit-library"))
        XCTAssertFalse(console.contains("-parse-as-library"), "top-level code needs a main file")
    }

    // MARK: Process runner

    func test_processRunner_drainsOutputLargerThanAPipe() async throws {
        let result = try await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' x >&2; echo done"],
            timeout: 20, outputLimit: 1_000_000
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.output.count, 300_005)
        XCTAssertTrue(result.output.hasSuffix("done\n"))
    }

    func test_processRunner_truncatesButKeepsDraining() async throws {
        let result = try await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' x"],
            timeout: 20, outputLimit: 1000
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.output.count, 1000)
    }

    func test_processRunner_stopsAChildPastItsDeadline() async throws {
        let start = Date()
        let result = try await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
            timeout: 0.5, outputLimit: 1000
        )
        XCTAssertTrue(result.timedOut)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }

    func test_consoleStatus_explainsSilentAndFailedRuns() {
        typealias Run = SwiftPreviewBuilder.ConsoleRun
        XCTAssertTrue(SwiftPreviewHostView.consoleStatus(
            Run(output: "", exitStatus: 0, timedOut: false, truncated: false)
        ).contains("print("))
        XCTAssertEqual(SwiftPreviewHostView.consoleStatus(
            Run(output: "hi\n", exitStatus: 0, timedOut: false, truncated: false)
        ), "finished")
        XCTAssertTrue(SwiftPreviewHostView.consoleStatus(
            Run(output: "boom", exitStatus: 132, timedOut: false, truncated: false)
        ).contains("exit status 132"))
        XCTAssertTrue(SwiftPreviewHostView.consoleStatus(
            Run(output: "", exitStatus: 15, timedOut: true, truncated: false)
        ).contains("stopped after"))
    }

    // MARK: Cache integrity

    func test_untaggedArtifact_isNotTrusted() throws {
        let directory = try makeTempDirectory()
        let artifact = directory.appendingPathComponent("untagged.dylib")
        try Data("anything".utf8).write(to: artifact)
        XCTAssertFalse(SwiftPreviewCacheIntegrity.isTrusted(artifact))
    }

    func test_signedArtifact_isTrusted() throws {
        let directory = try makeTempDirectory()
        let artifact = directory.appendingPathComponent("signed.dylib")
        try Data("compiled bytes".utf8).write(to: artifact)
        SwiftPreviewCacheIntegrity.sign(artifact)
        XCTAssertTrue(SwiftPreviewCacheIntegrity.isTrusted(artifact))
    }

    /// The case the tag exists for: another process swaps the cached artifact
    /// for its own dylib, keeping the filename the content hash predicts.
    func test_tamperedArtifact_isNotTrusted() throws {
        let directory = try makeTempDirectory()
        let artifact = directory.appendingPathComponent("swapped.dylib")
        try Data("compiled bytes".utf8).write(to: artifact)
        SwiftPreviewCacheIntegrity.sign(artifact)

        try Data("attacker bytes".utf8).write(to: artifact)

        XCTAssertFalse(SwiftPreviewCacheIntegrity.isTrusted(artifact))
    }

    /// A tag lifted from one artifact must not vouch for another.
    func test_transplantedTag_isNotTrusted() throws {
        let directory = try makeTempDirectory()
        let genuine = directory.appendingPathComponent("genuine.dylib")
        let forged = directory.appendingPathComponent("forged.dylib")
        try Data("compiled bytes".utf8).write(to: genuine)
        SwiftPreviewCacheIntegrity.sign(genuine)
        try Data("attacker bytes".utf8).write(to: forged)
        try FileManager.default.copyItem(
            at: genuine.appendingPathExtension("tag"),
            to: forged.appendingPathExtension("tag")
        )
        XCTAssertFalse(SwiftPreviewCacheIntegrity.isTrusted(forged))
    }

    /// `dlopen` follows symlinks, so the path being loaded has to be a real
    /// file before its tag means anything.
    func test_symlinkedArtifact_isRejectedBeforeTagCheck() throws {
        let directory = try makeTempDirectory()
        let target = directory.appendingPathComponent("elsewhere.dylib")
        let link = directory.appendingPathComponent("link.dylib")
        try Data("compiled bytes".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertTrue(SwiftPreviewCacheIntegrity.isPlainOwnedFile(target))
        XCTAssertFalse(SwiftPreviewCacheIntegrity.isPlainOwnedFile(link))
    }

    func test_discard_removesArtifactAndTagTogether() throws {
        let directory = try makeTempDirectory()
        let artifact = directory.appendingPathComponent("stale.dylib")
        try Data("compiled bytes".utf8).write(to: artifact)
        SwiftPreviewCacheIntegrity.sign(artifact)

        SwiftPreviewCacheIntegrity.discard(artifact)

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: artifact.appendingPathExtension("tag").path)
        )
    }
}
#endif
