import Foundation
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

enum MediaManager {
    private static let imageTypes: [UTType] = [.png, .jpeg, .heic, .gif, .webP, .tiff, .bmp]
    private static let videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, .movie, .video]

    static var allowedTypes: [UTType] { imageTypes + videoTypes }

    static var mediaDirectoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Snippets/Media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func resolvedURL(for fileName: String) -> URL {
        mediaDirectoryURL.appendingPathComponent(fileName)
    }

    static func kind(for url: URL) -> MediaKind {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .image }
        if videoTypes.contains(where: { type.conforms(to: $0) }) { return .video }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        return .image
    }

    @MainActor
    static func pickAndImport() -> [MediaItem] {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = allowedTypes
        panel.prompt = "Attach"

        guard panel.runModal() == .OK else { return [] }

        return panel.urls.compactMap { sourceURL in
            do {
                let ext = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
                let newName = "\(UUID().uuidString).\(ext)"
                let destination = resolvedURL(for: newName)
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                return MediaItem(fileName: newName, kind: kind(for: sourceURL))
            } catch {
                return nil
            }
        }
        #else
        return []
        #endif
    }

    static func deleteFile(for item: MediaItem) {
        let url = resolvedURL(for: item.fileName)
        try? FileManager.default.removeItem(at: url)
    }
}
