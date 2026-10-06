import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A Snippets export (`.snippets`). Declared in `Snippets-Info.plist`.
    static let snippetsArchive = UTType(exportedAs: "com.halilbagosi.snippets", conformingTo: .json)
}

/// The on-disk shape of a `.snippets` export. Plain values only — no
/// SwiftData — so encoding, decoding and validation are testable on their own.
///
/// Preview permissions are deliberately absent from the format: a file can
/// never carry run approval or network access into someone's library.
struct SnippetArchive: Codable, Equatable {
    static let formatIdentifier = "com.halilbagosi.snippets"
    static let currentVersion = 1
    /// The whole file is held in memory while it is read, media included.
    static let maxByteCount = 500 * 1024 * 1024

    var format: String = SnippetArchive.formatIdentifier
    var version: Int = SnippetArchive.currentVersion
    var exportedAt: Date
    var appVersion: String
    var collections: [CollectionRecord]
    var snippets: [SnippetRecord]

    struct CollectionRecord: Codable, Equatable {
        var id: UUID
        var name: String
        var colorHex: String
        var colorHexDark: String?
        var iconName: String
        var parentID: UUID?
        var isFavorite: Bool
        var createdAt: Date
        var updatedAt: Date
    }

    struct SnippetRecord: Codable, Equatable {
        var id: UUID
        var title: String
        var description: String
        var language: String
        var code: String
        var createdAt: Date
        var updatedAt: Date
        var isFavorite: Bool
        var copyCount: Int
        var collectionIDs: [UUID]
        /// In the user's arranged order.
        var dependencyIDs: [UUID]
        var paramConfigs: [PreviewParamConfig]
        var activeParamConfigID: UUID?
        var media: [MediaRecord]
    }

    struct MediaRecord: Codable, Equatable {
        var kind: String
        var fileExtension: String
        var addedAt: Date
        /// Base64 in the JSON (JSONEncoder's default for `Data`).
        var data: Data
    }

    enum ReadError: LocalizedError, Equatable {
        case tooLarge, notAnArchive, newerVersion, damaged

        var errorDescription: String? {
            switch self {
            case .tooLarge: "This file is too large to import."
            case .notAnArchive: "This isn't a Snippets export."
            case .newerVersion: "This file was made by a newer version of Snippets."
            case .damaged: "This Snippets export is damaged."
            }
        }
    }

    // MARK: Coding

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return try encoder.encode(self)
    }

    /// Validates and sanitises before returning; nothing it returns needs
    /// re-checking by the importer.
    static func decode(_ data: Data, maxByteCount: Int = SnippetArchive.maxByteCount) throws -> SnippetArchive {
        guard data.count <= maxByteCount else { throw ReadError.tooLarge }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            if let date = try? Date(string, strategy: .iso8601) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(string)")
        }

        // Read the envelope first, so a newer file says so instead of failing
        // on whichever field changed shape.
        struct Envelope: Decodable { let format: String; let version: Int }
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.format == formatIdentifier
        else { throw ReadError.notAnArchive }
        guard envelope.version <= currentVersion else { throw ReadError.newerVersion }

        let archive: SnippetArchive
        do { archive = try decoder.decode(SnippetArchive.self, from: data) } catch { throw ReadError.damaged }

        guard Set(archive.collections.map(\.id)).count == archive.collections.count,
              Set(archive.snippets.map(\.id)).count == archive.snippets.count
        else { throw ReadError.damaged }

        return archive.sanitized()
    }

    // MARK: Sanitising

    /// Drops what cannot be honoured instead of rejecting the file: references
    /// to ids not in the file, self-dependencies, parent cycles, an active
    /// config that does not exist, and media the app would not accept.
    func sanitized() -> SnippetArchive {
        let collectionIDs = Set(collections.map(\.id))
        let snippetIDs = Set(snippets.map(\.id))
        var copy = self

        copy.collections = Self.breakingParentCycles(collections.map { record in
            var record = record
            if let parent = record.parentID, parent == record.id || !collectionIDs.contains(parent) {
                record.parentID = nil
            }
            return record
        })

        copy.snippets = snippets.map { record in
            var record = record
            record.collectionIDs = record.collectionIDs.filter(collectionIDs.contains).removingDuplicates()
            record.dependencyIDs = record.dependencyIDs
                .filter { snippetIDs.contains($0) && $0 != record.id }
                .removingDuplicates()
            if let active = record.activeParamConfigID, !record.paramConfigs.contains(where: { $0.id == active }) {
                record.activeParamConfigID = nil
            }
            record.media = record.media.filter(Self.isAcceptable)
            return record
        }
        return copy
    }

    /// Walks each parent chain; the link that would close a loop is cut.
    private static func breakingParentCycles(_ collections: [CollectionRecord]) -> [CollectionRecord] {
        var parent = Dictionary(collections.map { ($0.id, $0.parentID) }, uniquingKeysWith: { first, _ in first })
        for start in collections.map(\.id) {
            var path: Set<UUID> = [start]
            var current = start
            while let next = parent[current] ?? nil {
                if path.contains(next) {
                    parent[current] = .some(nil)
                    break
                }
                path.insert(next)
                current = next
            }
        }
        return collections.map { record in
            var record = record
            record.parentID = parent[record.id] ?? nil
            return record
        }
    }

    /// Only image/video attachments whose extension maps to a type the media
    /// picker already accepts. The extension is the only part of an imported
    /// attachment that ever reaches a file name.
    static func isAcceptable(_ media: MediaRecord) -> Bool {
        guard MediaKind(rawValue: media.kind) != nil,
              !media.fileExtension.isEmpty,
              media.fileExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              let type = UTType(filenameExtension: media.fileExtension.lowercased())
        else { return false }
        return MediaManager.allowedTypes.contains { type.conforms(to: $0) }
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
