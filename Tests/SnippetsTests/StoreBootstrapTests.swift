import SwiftData
import XCTest
@testable import Snippets

@MainActor
final class StoreBootstrapTests: XCTestCase {
    private struct StubError: Error {}

    private var directory: URL!
    private var storeURL: URL!
    private var backups: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        directory = fm.temporaryDirectory.appending(path: "StoreBootstrapTests-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appending(path: "Snippets.store")
        backups = directory.appending(path: "Snippets/Backups")
        suiteName = "StoreBootstrapTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fm.removeItem(at: directory)
    }

    private func writeStore(wal: Bool = true) throws {
        try Data("main-bytes".utf8).write(to: storeURL)
        if wal {
            try Data("wal-bytes".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))
            try Data("shm-bytes".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-shm"))
        }
    }

    private func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + seconds)
    }

    private func backupNames() throws -> [String] {
        guard fm.fileExists(atPath: backups.path) else { return [] }
        return try fm.contentsOfDirectory(atPath: backups.path).sorted()
    }

    private func memoryContainer() throws -> ModelContainer {
        try ModelContainer(for: Snippet.self, MediaItem.self, SnippetCollection.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    // MARK: - StoreBackup

    func test_backup_noStore_returnsNilAndCreatesNothing() throws {
        let result = StoreBackup.backUpIfBuildChanged(
            storeURL: storeURL, backupsDirectory: backups, currentBuild: "1", defaults: defaults, now: at(0))
        XCTAssertNil(result)
        XCTAssertFalse(fm.fileExists(atPath: backups.path))
        XCTAssertNil(defaults.string(forKey: StoreBackup.lastOpenedBuildKey))
    }

    func test_backup_firstOpen_copiesEveryFileAndRecordsBuild() throws {
        try writeStore()
        let result = try XCTUnwrap(StoreBackup.backUpIfBuildChanged(
            storeURL: storeURL, backupsDirectory: backups, currentBuild: "7", defaults: defaults, now: at(0)))
        XCTAssertTrue(result.lastPathComponent.hasSuffix("-build7"))
        for file in StoreFiles.existing(for: storeURL) {
            let copy = result.appending(path: file.lastPathComponent)
            XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: file), file.lastPathComponent)
        }
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: result.path).count, 3)
        XCTAssertEqual(defaults.string(forKey: StoreBackup.lastOpenedBuildKey), "7")
    }

    func test_backup_sameBuildAgain_doesNothing() throws {
        try writeStore()
        StoreBackup.backUpIfBuildChanged(
            storeURL: storeURL, backupsDirectory: backups, currentBuild: "7", defaults: defaults, now: at(0))
        let second = StoreBackup.backUpIfBuildChanged(
            storeURL: storeURL, backupsDirectory: backups, currentBuild: "7", defaults: defaults, now: at(60))
        XCTAssertNil(second)
        XCTAssertEqual(try backupNames().count, 1)
    }

    func test_backup_newBuild_makesSecondBackupAndLeavesOriginals() throws {
        try writeStore()
        StoreBackup.backUpIfBuildChanged(
            storeURL: storeURL, backupsDirectory: backups, currentBuild: "7", defaults: defaults, now: at(0))
        let second = StoreBackup.backUpIfBuildChanged(
            storeURL: storeURL, backupsDirectory: backups, currentBuild: "8", defaults: defaults, now: at(60))
        XCTAssertNotNil(second)
        XCTAssertEqual(try backupNames().count, 2)
        XCTAssertEqual(try Data(contentsOf: storeURL), Data("main-bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: storeURL.path + "-wal")), Data("wal-bytes".utf8))
        XCTAssertEqual(defaults.string(forKey: StoreBackup.lastOpenedBuildKey), "8")
    }

    func test_backup_keepsNewestFiveAndNeverPrunesUnreadable() throws {
        try writeStore()
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        // Seven older backups plus an unreadable-library folder that sorts
        // after every one of them.
        for day in 1...7 {
            try fm.createDirectory(
                at: backups.appending(path: "2026010\(day)-000000-build\(day)"), withIntermediateDirectories: true)
        }
        let unreadable = backups.appending(path: "unreadable-20260101-000000")
        try fm.createDirectory(at: unreadable, withIntermediateDirectories: true)

        StoreBackup.backUpIfBuildChanged(
            storeURL: storeURL, backupsDirectory: backups, currentBuild: "9", defaults: defaults, now: at(0))

        let names = try backupNames()
        XCTAssertEqual(names.filter { !$0.hasPrefix("unreadable-") }.count, StoreBackup.keep)
        XCTAssertTrue(names.contains("unreadable-20260101-000000"))
        XCTAssertFalse(names.contains("20260101-000000-build1"))
        XCTAssertTrue(names.contains { $0.hasSuffix("-build9") })
    }

    func test_moveAside_movesEveryFileIntoUnreadableFolder() throws {
        try writeStore()
        let destination = try StoreBackup.moveAside(storeURL: storeURL, backupsDirectory: backups, now: at(0))
        XCTAssertTrue(destination.lastPathComponent.hasPrefix("unreadable-"))
        XCTAssertTrue(StoreFiles.existing(for: storeURL).isEmpty)
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "Snippets.store")), Data("main-bytes".utf8))
        XCTAssertTrue(fm.fileExists(atPath: destination.appending(path: "Snippets.store-wal").path))
        XCTAssertTrue(fm.fileExists(atPath: destination.appending(path: "Snippets.store-shm").path))
    }

    // MARK: - StoreBootstrap.recoveryMessage

    private static let firstSentence = "The library file may be damaged, or it was made by a newer version of Snippets."
    private static let lastSentence = "Starting with an empty library moves the current file into a Backups folder; nothing is deleted."

    func test_recoveryMessage_swiftDataError_omitsTheRawError() {
        let message = StoreBootstrap.recoveryMessage(for: SwiftDataError.loadIssueModelContainer)
        XCTAssertFalse(message.contains("SwiftData"))
        XCTAssertFalse(message.contains("error 1"))
        XCTAssertEqual(message.components(separatedBy: "\n\n").count, 2)
        XCTAssertTrue(message.hasPrefix(Self.firstSentence))
        XCTAssertTrue(message.hasSuffix(Self.lastSentence))
    }

    func test_recoveryMessage_fileError_includesItsDescription() {
        let error = CocoaError(.fileWriteNoPermission)
        let paragraphs = StoreBootstrap.recoveryMessage(for: error).components(separatedBy: "\n\n")
        XCTAssertEqual(paragraphs.count, 3)
        XCTAssertEqual(paragraphs[0], Self.firstSentence)
        XCTAssertEqual(paragraphs[1], error.localizedDescription)
        XCTAssertEqual(paragraphs[2], Self.lastSentence)
    }

    // MARK: - StoreBootstrap.open

    func test_open_succeedsFirstTry_neverAsks() throws {
        var asked = 0
        let container = StoreBootstrap.open(
            storeURL: storeURL, backupsDirectory: backups,
            makeContainer: { _ in try self.memoryContainer() },
            ask: { _ in asked += 1; return .quit },
            reveal: { _ in })
        XCTAssertNotNil(container)
        XCTAssertEqual(asked, 0)
    }

    func test_open_failureThenQuit_returnsNilAndLeavesStore() throws {
        try writeStore()
        let container = StoreBootstrap.open(
            storeURL: storeURL, backupsDirectory: backups,
            makeContainer: { _ in throw StubError() },
            ask: { _ in .quit },
            reveal: { _ in })
        XCTAssertNil(container)
        XCTAssertEqual(try Data(contentsOf: storeURL), Data("main-bytes".utf8))
        XCTAssertFalse(fm.fileExists(atPath: backups.path))
    }

    func test_open_failureThenStartEmpty_movesFileAsideAndReturnsContainer() throws {
        try writeStore()
        var attempts = 0
        let container = StoreBootstrap.open(
            storeURL: storeURL, backupsDirectory: backups,
            makeContainer: { _ in
                attempts += 1
                if attempts == 1 { throw StubError() }
                return try self.memoryContainer()
            },
            ask: { _ in .startEmpty },
            reveal: { _ in })
        XCTAssertNotNil(container)
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(fm.fileExists(atPath: storeURL.path))
        let unreadable = try backupNames().filter { $0.hasPrefix("unreadable-") }
        XCTAssertEqual(unreadable.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: backups.appending(path: unreadable[0]).appending(path: "Snippets.store").path))
    }

    func test_open_failureThenRevealThenQuit_revealsOnceAndReturnsNil() throws {
        try writeStore()
        var answers: [StoreRecoveryChoice] = [.reveal, .quit]
        var revealed: [URL] = []
        var attempts = 0
        let container = StoreBootstrap.open(
            storeURL: storeURL, backupsDirectory: backups,
            makeContainer: { _ in attempts += 1; throw StubError() },
            ask: { _ in answers.removeFirst() },
            reveal: { revealed.append($0) })
        XCTAssertNil(container)
        XCTAssertEqual(revealed, [storeURL])
        XCTAssertEqual(attempts, 1, "revealing must not silently retry the open")
    }
}
