import Foundation
import UniformTypeIdentifiers

protocol MediaManaging {
    var allowedTypes: [UTType] { get }

    func resolvedURL(for fileName: String) -> URL
    func kind(for url: URL) -> MediaKind

    @MainActor
    func pickAndImport() -> [MediaItem]

    func deleteFile(for item: MediaItem)
}
