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
            try? FileManager.default.removeItem(at: dylibURL)
            try? FileManager.default.removeItem(
                at: cacheDirectory.appendingPathComponent("\(harness.hash).swift")
            )
        }

        _ = try await SwiftPreviewBuilder.shared.build(code: code)

        let recovered = try Data(contentsOf: dylibURL)
        XCTAssertNotEqual(recovered, Data("not a dylib".utf8))
    }
}
