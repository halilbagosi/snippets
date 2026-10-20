#if !APP_STORE
import XCTest
@testable import Snippets

@MainActor
final class MCPSocketServerTests: XCTestCase {
    private var dir: URL!
    private var path: String { dir.appending(path: "mcp.sock").path(percentEncoded: false) }

    override func setUp() async throws {
        // Short: sockaddr_un paths are capped at 104 bytes.
        dir = URL(filePath: NSTemporaryDirectory()).appending(path: String(UUID().uuidString.prefix(8)))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeServer() -> MCPSocketServer {
        MCPSocketServer(path: path) { line in line == "quiet" ? nil : "echo:" + line }
    }

    /// Blocking read of one line, off the main actor so the server's
    /// main-queue dispatch can run. nil at EOF or after 5 s.
    nonisolated private static func readLine(_ fd: Int32) -> String? {
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 0x0A { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(byte)
        }
        return nil
    }

    private func readLine(_ fd: Int32) async -> String? {
        await Task.detached { Self.readLine(fd) }.value
    }

    func test_repliesInOrderAndSkipsNilReplies() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let fd = try XCTUnwrap(UnixSocket.connect(path: path))
        defer { close(fd) }

        UnixSocket.writeAll(fd, Data("quiet\nhello\nworld\n".utf8))
        let first = await readLine(fd)
        let second = await readLine(fd)
        XCTAssertEqual(first, "echo:hello")
        XCTAssertEqual(second, "echo:world")
    }

    func test_socketIsOwnerOnly() throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func test_halfClosedClientStillGetsItsReply() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let fd = try XCTUnwrap(UnixSocket.connect(path: path))
        defer { close(fd) }

        UnixSocket.writeAll(fd, Data("hello\n".utf8))
        shutdown(fd, SHUT_WR)
        let reply = await readLine(fd)
        let eof = await readLine(fd)
        XCTAssertEqual(reply, "echo:hello")
        XCTAssertNil(eof)
    }

    func test_stopDisconnectsClientsAndRemovesTheSocket() async throws {
        let server = makeServer()
        try server.start()
        let fd = try XCTUnwrap(UnixSocket.connect(path: path))
        defer { close(fd) }

        server.stop()
        let afterStop = await readLine(fd)
        XCTAssertNil(afterStop)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertNil(UnixSocket.connect(path: path))
    }

    func test_replacesAStaleSocketFile() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data())
        let server = makeServer()
        XCTAssertNoThrow(try server.start())
        server.stop()
    }

    func test_refusesToStealALiveSocket() throws {
        let first = makeServer()
        try first.start()
        defer { first.stop() }
        XCTAssertThrowsError(try makeServer().start()) {
            XCTAssertEqual($0 as? UnixSocket.Failure, .inUse)
        }
    }
}
#endif
