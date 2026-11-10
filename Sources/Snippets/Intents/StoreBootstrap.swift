import Foundation
import SwiftData

/// The store and its SQLite sidecars.
enum StoreFiles {
    /// The store file plus its write-ahead-log and shared-memory sidecars —
    /// only those that exist. Copying or moving the database without its
    /// sidecars can lose the most recent writes, so they always travel together.
    static func existing(for storeURL: URL, fileManager: FileManager = .default) -> [URL] {
        [storeURL, URL(fileURLWithPath: storeURL.path + "-wal"), URL(fileURLWithPath: storeURL.path + "-shm")]
            .filter { fileManager.fileExists(atPath: $0.path) }
    }
}

enum StoreBackup {
    static let lastOpenedBuildKey = "store.lastOpenedBuild"
    static let keep = 5
    static let unreadablePrefix = "unreadable-"

    /// Copies the store files into `backupsDirectory/<yyyyMMdd-HHmmss>-build<N>/`
    /// when a store exists and `currentBuild` differs from the build recorded
    /// in `defaults`. Records `currentBuild` afterwards, then prunes to the
    /// newest `keep` backups. Returns the new backup's URL, or nil when none
    /// was needed. A failed copy returns nil and does NOT record the build, so
    /// the next launch tries again; it never prevents the app from opening.
    @discardableResult
    static func backUpIfBuildChanged(
        storeURL: URL, backupsDirectory: URL, currentBuild: String,
        defaults: UserDefaults, now: Date = .now, fileManager: FileManager = .default
    ) -> URL? {
        let files = StoreFiles.existing(for: storeURL, fileManager: fileManager)
        guard !files.isEmpty else { return nil }
        guard defaults.string(forKey: lastOpenedBuildKey) != currentBuild else { return nil }

        let destination = backupsDirectory.appending(path: "\(timestamp(now))-build\(currentBuild)")
        do {
            try copy(files, into: destination, fileManager: fileManager)
        } catch {
            // Leave no half-written backup behind to be mistaken for a good one.
            try? fileManager.removeItem(at: destination)
            return nil
        }
        defaults.set(currentBuild, forKey: lastOpenedBuildKey)
        prune(backupsDirectory: backupsDirectory, fileManager: fileManager)
        return destination
    }

    /// Moves the store files into `backupsDirectory/unreadable-<yyyyMMdd-HHmmss>/`.
    static func moveAside(
        storeURL: URL, backupsDirectory: URL, now: Date = .now, fileManager: FileManager = .default
    ) throws -> URL {
        let destination = backupsDirectory.appending(path: "\(unreadablePrefix)\(timestamp(now))")
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in StoreFiles.existing(for: storeURL, fileManager: fileManager) {
            try fileManager.moveItem(at: file, to: destination.appending(path: file.lastPathComponent))
        }
        return destination
    }

    private static func copy(_ files: [URL], into destination: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in files {
            try fileManager.copyItem(at: file, to: destination.appending(path: file.lastPathComponent))
        }
    }

    /// Backup names start with a sortable timestamp, so "newest" is the
    /// greatest name. Unreadable-library folders are the user's only copy of a
    /// library the app could not open, so they are never pruned.
    private static func prune(backupsDirectory: URL, fileManager: FileManager) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        else { return }
        let backups = entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !$0.lastPathComponent.hasPrefix(unreadablePrefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for stale in backups.dropLast(keep) {
            try? fileManager.removeItem(at: stale)
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

enum StoreRecoveryChoice { case quit, reveal, startEmpty }

enum StoreBootstrap {
    /// Opens the store, asking what to do each time it fails. Returns nil when
    /// the user chose to quit.
    @MainActor
    static func open(
        storeURL: URL, backupsDirectory: URL,
        makeContainer: (URL) throws -> ModelContainer,
        ask: (Error) -> StoreRecoveryChoice,
        reveal: (URL) -> Void
    ) -> ModelContainer? {
        var failure: Error?
        while true {
            if failure == nil {
                do {
                    return try makeContainer(storeURL)
                } catch {
                    failure = error
                }
            }
            // `failure` is non-nil here: either the open just failed, or the
            // user asked to look at the file or moving it aside failed, and in
            // both cases opening again would only repeat the same answer.
            switch ask(failure!) {
            case .quit:
                return nil
            case .reveal:
                reveal(storeURL)
            case .startEmpty:
                do {
                    _ = try StoreBackup.moveAside(storeURL: storeURL, backupsDirectory: backupsDirectory)
                    failure = nil
                } catch {
                    failure = error
                }
            }
        }
    }
}
