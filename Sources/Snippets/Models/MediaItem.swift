import Foundation
import SwiftData

enum MediaKind: String, Codable, CaseIterable {
    case image
    case video
}

@Model
final class MediaItem {
    var fileName: String
    var fileTypeRaw: String
    var addedAt: Date

    var snippet: Snippet?

    var kind: MediaKind {
        MediaKind(rawValue: fileTypeRaw) ?? .image
    }

    init(fileName: String, kind: MediaKind, addedAt: Date = .now) {
        self.fileName = fileName
        self.fileTypeRaw = kind.rawValue
        self.addedAt = addedAt
    }
}
