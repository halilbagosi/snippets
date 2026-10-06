import XCTest
@testable import Snippets

final class SnippetArchiveTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func media(_ kind: String, _ ext: String) -> SnippetArchive.MediaRecord {
        .init(kind: kind, fileExtension: ext, addedAt: t, data: Data([1, 2, 3]))
    }

    private func snippet(
        _ id: UUID = UUID(),
        collections: [UUID] = [],
        deps: [UUID] = [],
        configs: [PreviewParamConfig] = [],
        active: UUID? = nil,
        media: [SnippetArchive.MediaRecord] = []
    ) -> SnippetArchive.SnippetRecord {
        .init(id: id, title: "Title", description: "Desc", language: "React", code: "code",
              createdAt: t, updatedAt: t, isFavorite: true, copyCount: 4,
              collectionIDs: collections, dependencyIDs: deps,
              paramConfigs: configs, activeParamConfigID: active, media: media)
    }

    private func collection(_ id: UUID = UUID(), name: String = "C", parent: UUID? = nil) -> SnippetArchive.CollectionRecord {
        .init(id: id, name: name, colorHex: "#FF0000", colorHexDark: "#330000", iconName: "star",
              parentID: parent, isFavorite: true, createdAt: t, updatedAt: t)
    }

    func test_encodeDecode_roundTripsEveryField() throws {
        let root = UUID(), child = UUID(), dep = UUID(), config = UUID()
        let archive = SnippetArchive(
            exportedAt: t, appVersion: "1.0",
            collections: [collection(root, name: "Root"), collection(child, name: "Child", parent: root)],
            snippets: [
                snippet(dep),
                snippet(collections: [child], deps: [dep],
                        configs: [PreviewParamConfig(id: config, name: "Big", values: ["size": .number(40)], isDefault: false)],
                        active: config, media: [media("image", "png")]),
            ])
        XCTAssertEqual(try SnippetArchive.decode(archive.encoded()), archive)
    }

    func test_decode_rejectsNonJSON() {
        XCTAssertThrowsError(try SnippetArchive.decode(Data("hello".utf8))) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .notAnArchive)
        }
    }

    func test_decode_rejectsOtherFormats() {
        XCTAssertThrowsError(try SnippetArchive.decode(Data(#"{"format":"com.example.other","version":1}"#.utf8))) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .notAnArchive)
        }
    }

    func test_decode_rejectsNewerVersion_beforeLookingAtTheBody() {
        XCTAssertThrowsError(try SnippetArchive.decode(Data(#"{"format":"com.halilbagosi.snippets","version":2}"#.utf8))) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .newerVersion)
        }
    }

    func test_decode_rejectsMissingFields() {
        XCTAssertThrowsError(try SnippetArchive.decode(Data(#"{"format":"com.halilbagosi.snippets","version":1}"#.utf8))) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .damaged)
        }
    }

    func test_decode_rejectsDuplicateIDs() throws {
        let id = UUID()
        let archive = SnippetArchive(exportedAt: t, appVersion: "1.0", collections: [], snippets: [snippet(id), snippet(id)])
        XCTAssertThrowsError(try SnippetArchive.decode(archive.encoded())) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .damaged)
        }
    }

    func test_decode_rejectsOversizedData() throws {
        let data = try SnippetArchive(exportedAt: t, appVersion: "1.0", collections: [], snippets: []).encoded()
        XCTAssertThrowsError(try SnippetArchive.decode(data, maxByteCount: data.count - 1)) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .tooLarge)
        }
    }

    func test_sanitized_dropsDanglingReferences() {
        let real = UUID(), self_ = UUID()
        let archive = SnippetArchive(
            exportedAt: t, appVersion: "1.0",
            collections: [collection(real, parent: UUID())],
            snippets: [
                snippet(self_, collections: [real, UUID(), real], deps: [UUID(), self_], active: UUID()),
            ]).sanitized()
        XCTAssertNil(archive.collections[0].parentID)
        XCTAssertEqual(archive.snippets[0].collectionIDs, [real])
        XCTAssertEqual(archive.snippets[0].dependencyIDs, [])
        XCTAssertNil(archive.snippets[0].activeParamConfigID)
    }

    func test_sanitized_keepsDependencyOrder() {
        let a = UUID(), b = UUID(), c = UUID()
        let archive = SnippetArchive(exportedAt: t, appVersion: "1.0", collections: [],
                                     snippets: [snippet(a, deps: [c, b]), snippet(b), snippet(c)]).sanitized()
        XCTAssertEqual(archive.snippets[0].dependencyIDs, [c, b])
    }

    func test_sanitized_breaksParentCycles() {
        let a = UUID(), b = UUID()
        let archive = SnippetArchive(exportedAt: t, appVersion: "1.0",
                                     collections: [collection(a, parent: b), collection(b, parent: a)],
                                     snippets: []).sanitized()
        XCTAssertEqual(archive.collections[0].parentID, b)
        XCTAssertNil(archive.collections[1].parentID)
    }

    func test_sanitized_dropsUnacceptableMedia() {
        let archive = SnippetArchive(
            exportedAt: t, appVersion: "1.0", collections: [],
            snippets: [snippet(media: [
                media("image", "png"), media("video", "mov"), media("audio", "png"),
                media("image", "exe"), media("image", "../png"), media("image", ""),
            ])]).sanitized()
        XCTAssertEqual(archive.snippets[0].media.map(\.fileExtension), ["png", "mov"])
    }
}
