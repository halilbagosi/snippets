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
