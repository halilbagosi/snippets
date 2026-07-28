import Foundation
import OSLog
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

struct MediaManager: MediaManaging {
    static let shared = MediaManager()

    private static let logger = Logger(subsystem: "Snippets", category: "MediaManager")
    private static let imageTypes: [UTType] = [.png, .jpeg, .heic, .gif, .webP, .tiff, .bmp]
    private static let videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, .movie, .video]

    static var allowedTypes: [UTType] { imageTypes + videoTypes }

    var allowedTypes: [UTType] { Self.allowedTypes }

    static var mediaDirectoryURL: URL {
        shared.resolvedMediaDirectoryURL
    }

    private var resolvedMediaDirectoryURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = support.appendingPathComponent("Snippets/Media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                Self.logger.error("Failed to create media directory at \(dir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return dir
    }

    static func resolvedURL(for fileName: String) -> URL {
        shared.resolvedURL(for: fileName)
    }

    func resolvedURL(for fileName: String) -> URL {
        resolvedMediaDirectoryURL.appendingPathComponent(Self.safeFileName(fileName))
    }

    /// Confines a stored media filename to a single component inside the media
    /// directory.
    ///
    /// Every name written today is a UUID this app generated, so nothing hits
    /// the rejection path. It exists because the *reads* are the dangerous
    /// direction and they are already spread across six call sites: the moment
    /// a `MediaItem` can arrive from an import, a sync, or a shared library, a
    /// name like `../../../../etc/passwd` would resolve wherever it liked, and
    /// the video player would happily open it. Cheap to add now, easy to
    /// forget once there is an importer to write.
    ///
    /// Rejected names collapse to a constant that resolves inside the media
    /// directory and simply does not exist, so callers see the same
    /// missing-file behavior they already handle.
    static func safeFileName(_ fileName: String) -> String {
        let rejected = "__invalid__"
        guard !fileName.isEmpty,
              !fileName.hasPrefix("."),
              !fileName.contains("/"),
              !fileName.contains("\\"),
              !fileName.contains("\0"),
              // A name that is not exactly its own last component is trying to
              // be a path, whatever separator it used to get there.
              (fileName as NSString).lastPathComponent == fileName
        else {
            logger.error("Rejected unsafe media filename \(fileName, privacy: .public)")
            return rejected
        }
        return fileName
    }

    static func kind(for url: URL) -> MediaKind {
        shared.kind(for: url)
    }

    func kind(for url: URL) -> MediaKind {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return .image }
        if Self.videoTypes.contains(where: { type.conforms(to: $0) }) { return .video }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        return .image
    }

    @MainActor
    static func pickAndImport() -> [MediaItem] {
        shared.pickAndImport()
    }

    @MainActor
    func pickAndImport() -> [MediaItem] {
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
                Self.logger.error("Failed to import media file \(sourceURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        #else
        return []
        #endif
    }

    static func deleteFile(for item: MediaItem) {
        shared.deleteFile(for: item)
    }

    func deleteFile(for item: MediaItem) {
        let url = resolvedURL(for: item.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("Failed to delete media file \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
