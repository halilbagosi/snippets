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

    enum Read: Equatable {
        case line(String)
        case eof
        case timeout
    }

    /// Blocking read of one line, off the main actor so the server's
    /// main-queue dispatch can run. Distinguishes EOF from a 10 s timeout.
    nonisolated private static func readLine(_ fd: Int32) -> Read {
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        while true {
            let count = read(fd, &byte, 1)
            if count == 1 {
                if byte == 0x0A { return .line(String(decoding: bytes, as: UTF8.self)) }
                bytes.append(byte)
            } else if count == 0 {
                return .eof
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return .timeout
            } else {
                return .eof // ECONNRESET and friends: the peer is gone
            }
        }
    }

    /// Discards everything until the server closes the connection.
    nonisolated private static func drain(_ fd: Int32) -> Read {
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 { continue }
            if count == 0 { return .eof }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return .timeout }
            return .eof
        }
    }

    private func readLine(_ fd: Int32) async -> Read {
        await Task.detached { Self.readLine(fd) }.value
    }

    private func drain(_ fd: Int32) async -> Read {
        await Task.detached { Self.drain(fd) }.value
    }

    private func inode(_ path: String) -> UInt64? {
        var info = stat()
        return stat(path, &info) == 0 ? UInt64(info.st_ino) : nil
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
        XCTAssertEqual(first, .line("echo:hello"))
        XCTAssertEqual(second, .line("echo:world"))
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
        XCTAssertEqual(reply, .line("echo:hello"))
        XCTAssertEqual(eof, .eof)
    }

    func test_stopDisconnectsClientsAndRemovesTheSocket() async throws {
        let server = makeServer()
        try server.start()
        let fd = try XCTUnwrap(UnixSocket.connect(path: path))
        defer { close(fd) }

        server.stop()
        let afterStop = await readLine(fd)
        XCTAssertEqual(afterStop, .eof)
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

    /// Flips when the main-queue handler has seen the request.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }

    func test_aClientThatStopsReadingIsDroppedWithinOneDeadline() async throws {
        let big = String(repeating: "x", count: 4 * 1024 * 1024)
        let dispatched = Flag()
        let server = MCPSocketServer(path: path) { line in
            if line == "big" { dispatched.set(); return big }
            return "echo:" + line
        }
        try server.start()
        defer { server.stop() }
        let stalled = try XCTUnwrap(UnixSocket.connect(path: path))
        defer { close(stalled) }
        let other = try XCTUnwrap(UnixSocket.connect(path: path))
        defer { close(other) }

        UnixSocket.writeAll(stalled, Data("big\n".utf8))
        // The big reply is queued ahead of anything the other client sends.
        let wait = Date().addingTimeInterval(5)
        while !dispatched.isSet && Date() < wait { await Task.yield() }
        XCTAssertTrue(dispatched.isSet)

        let started = Date()
        UnixSocket.writeAll(other, Data("hello\n".utf8))
        let reply = await readLine(other)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(reply, .line("echo:hello"))
        // One 2 s deadline for the stalled reply, not one per write() call.
        XCTAssertGreaterThan(elapsed, 1.0)
        XCTAssertLessThan(elapsed, 3.5)
        let end = await drain(stalled)
        XCTAssertEqual(end, .eof)
    }

    func test_aClientTricklingItsReadsIsStillDroppedWithinOneDeadline() async throws {
        let big = String(repeating: "x", count: 4 * 1024 * 1024)
        let server = MCPSocketServer(path: path) { _ in big }
        try server.start()
        defer { server.stop() }
        let fd = try XCTUnwrap(UnixSocket.connect(path: path))
        defer { close(fd) }

        UnixSocket.writeAll(fd, Data("big\n".utf8))
        let started = Date()
        let end = await Task.detached { () -> Read in
            var chunk = [UInt8](repeating: 0, count: 16 * 1024)
            while Date().timeIntervalSince(started) < 8 {
                let count = read(fd, &chunk, chunk.count)
                if count == 0 { return .eof }
                if count < 0 && errno != EINTR { return .eof }
                usleep(500_000) // a slow reader, deliberately
            }
            return .timeout
        }.value
        XCTAssertEqual(end, .eof)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    func test_stopOnAServerThatLostTheBindDoesNotRemoveTheLiveSocket() async throws {
        let first = makeServer()
        try first.start()
        defer { first.stop() }
        let second = makeServer()
        XCTAssertThrowsError(try second.start())
        second.stop()

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        let fd = try XCTUnwrap(UnixSocket.connect(path: path))
        defer { close(fd) }
        UnixSocket.writeAll(fd, Data("hello\n".utf8))
        let reply = await readLine(fd)
        XCTAssertEqual(reply, .line("echo:hello"))
    }

    func test_stopOnANeverStartedServerLeavesTheFileAlone() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data())
        makeServer().stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func test_stopLeavesAFileThatReplacedOurSocket() throws {
        let server = makeServer()
        try server.start()
        let bound = inode(path)
        unlink(path)
        FileManager.default.createFile(atPath: path, contents: Data())
        XCTAssertNotEqual(inode(path), bound)
        server.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func test_anUnterminatedLineOverTheCapClosesTheConnection() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let fd = try XCTUnwrap(UnixSocket.connect(path: path))
        defer { close(fd) }

        let payload = Data(repeating: 0x61, count: 4 * 1024 * 1024 + 1)
        await Task.detached { UnixSocket.writeAll(fd, payload) }.value
        let end = await drain(fd)
        XCTAssertEqual(end, .eof)
    }
}
#endif
