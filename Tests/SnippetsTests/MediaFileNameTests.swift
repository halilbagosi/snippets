import XCTest
@testable import Snippets

/// The media directory is addressed by filename from six call sites, and those
/// names come out of the persisted store. Today they are UUIDs this app minted,
/// so these are guard-rail tests for the day an importer exists.
final class MediaFileNameTests: XCTestCase {
    private func resolved(_ name: String) -> URL {
        MediaManager.resolvedURL(for: name)
    }

    func test_generatedUUIDName_passesThrough() {
        let name = "\(UUID().uuidString).png"
        XCTAssertEqual(MediaManager.safeFileName(name), name)
        XCTAssertEqual(resolved(name).lastPathComponent, name)
    }

    func test_traversalIsRejected() {
        for name in ["../secret.png", "../../../../etc/passwd", "a/../../b.png"] {
            XCTAssertNotEqual(MediaManager.safeFileName(name), name, "accepted \(name)")
        }
    }

    /// The property that actually matters: whatever the name, the URL stays
    /// inside the media directory.
    func test_resolvedURLNeverEscapesMediaDirectory() {
        let directory = MediaManager.mediaDirectoryURL.standardizedFileURL.path
        for name in ["../secret.png", "../../etc/passwd", "sub/dir/x.png", "", ".", "..", "/etc/passwd"] {
            let path = resolved(name).standardizedFileURL.path
            XCTAssertTrue(
                path.hasPrefix(directory + "/"),
                "\(name) resolved outside the media directory: \(path)"
            )
        }
    }

    func test_hiddenAndEmptyNamesAreRejected() {
        XCTAssertNotEqual(MediaManager.safeFileName(""), "")
        XCTAssertNotEqual(MediaManager.safeFileName(".hidden"), ".hidden")
    }
}
