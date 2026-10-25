#if !APP_STORE
import Darwin
import Foundation

/// Unix-domain socket plumbing shared by the in-app server and the
/// `--mcp-stdio` shim.
enum UnixSocket {
    enum Failure: Error, Equatable {
        case pathTooLong
        /// Another Snippets process is already serving this path.
        case inUse
        case system(String, Int32)
    }

    static func address(path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { throw Failure.pathTooLong }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }

    /// A connected stream socket, or nil when nothing is listening.
    static func connect(path: String) -> Int32? {
        guard let addr = try? address(path: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let result = withUnsafePointer(to: addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { close(fd); return nil }
        disableSIGPIPE(fd)
        return fd
    }

    /// A peer that hangs up mid-write must cost an error return, not the process.
    static func disableSIGPIPE(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// One deadline for a whole reply: a client that stops (or trickles) reading
    /// must cost a failed write, not a stalled server queue.
    static let sendTimeoutSeconds: TimeInterval = 2

    private static func setSendTimeout(_ fd: Int32, _ seconds: TimeInterval) {
        let whole = Int(seconds)
        let micros = max(1000, Int((seconds - Double(whole)) * 1_000_000)) // 0 would mean "forever"
        var timeout = timeval(tv_sec: whole, tv_usec: Int32(whole == 0 ? micros : min(micros, 999_999)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Writes all of `data`, retrying short writes. False once the peer is gone.
    /// With `timeout`, the whole write shares one deadline and also fails when
    /// it passes (a timed-out write surfaces as EAGAIN).
    @discardableResult
    static func writeAll(_ fd: Int32, _ data: Data, timeout: TimeInterval? = nil) -> Bool {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        return data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                if let deadline {
                    let left = deadline.timeIntervalSinceNow
                    if left <= 0 { return false }
                    setSendTimeout(fd, left)
                }
                // Bounded slices: a blocked write() only times out when no space opens
                // for the whole timeout, so a trickling reader would never trip it.
                let written = write(fd, pointer, min(remaining, 16 * 1024))
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
            return true
        }
    }
}

/// Listens on a Unix socket and hands each newline-delimited message to
/// `handler` on the main actor, writing back whatever it returns. Main-queue
/// dispatch keeps replies in request order. All socket state lives on `queue`.
///
/// Callers must call `stop()` before releasing the server; there is no deinit
/// cleanup because a `queue.sync` there could deadlock.
final class MCPSocketServer: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (String) -> String?

    let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.halilbagosi.Snippets.mcp")
    private var listenSource: DispatchSourceRead?
    private var connections: [ObjectIdentifier: Connection] = [:]
    /// Device and inode of the socket file this instance bound; nil when it holds none.
    private var boundInode: FileID?
    /// Whether `listenSource` is suspended while accept backs off.
    private var listenSuspended = false

    init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    /// Binds and starts accepting. A socket file left by a crash is replaced;
    /// one another process is still serving is not.
    func start() throws {
        try FileManager.default.createDirectory(
            at: URL(filePath: path).deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let live = UnixSocket.connect(path: path) {
            close(live)
            throw UnixSocket.Failure.inUse
        }
        unlink(path)

        let addr = try UnixSocket.address(path: path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocket.Failure.system("socket", errno) }
        let bound = withUnsafePointer(to: addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { let e = errno; close(fd); throw UnixSocket.Failure.system("bind", e) }
        let inode = Self.inode(of: path)
        // Owner only: whoever can connect can read the whole library.
        guard chmod(path, 0o600) == 0 else {
            let e = errno; close(fd); unlink(path); throw UnixSocket.Failure.system("chmod", e)
        }
        // Non-blocking so the accept loop can drain until EAGAIN.
        let flags = fcntl(fd, F_GETFL)
        guard flags != -1, fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1 else {
            let e = errno; close(fd); unlink(path); throw UnixSocket.Failure.system("fcntl", e)
        }
        guard listen(fd, 8) == 0 else { let e = errno; close(fd); unlink(path); throw UnixSocket.Failure.system("listen", e) }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self, unowned source] in self?.acceptConnections(on: fd, source: source) }
        source.setCancelHandler { close(fd) }
        queue.sync {
            listenSource = source
            listenSuspended = false
            boundInode = inode
        }
        source.resume()
    }

    private struct FileID: Equatable {
        let device: Int64
        let inode: UInt64
    }

    private static func inode(of path: String) -> FileID? {
        var info = stat()
        return stat(path, &info) == 0 ? FileID(device: Int64(info.st_dev), inode: UInt64(info.st_ino)) : nil
    }

    /// Stops listening and drops every connection. Safe to call twice.
    func stop() {
        let ours: FileID? = queue.sync {
            if let source = listenSource {
                source.cancel()
                // A suspended source runs its cancel handler (closing the fd) only once resumed.
                if listenSuspended { source.resume() }
            }
            listenSource = nil
            listenSuspended = false
            let open = Array(connections.values)
            connections.removeAll()
            open.forEach { $0.close() }
            defer { boundInode = nil }
            return boundInode
        }
        // Only remove the file we bound, never another instance's replacement.
        if let ours, Self.inode(of: path) == ours { unlink(path) }
    }

    private func acceptConnections(on listenFD: Int32, source: DispatchSourceRead) {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd >= 0 {
                adopt(fd)
                continue
            }
            switch errno {
            case EAGAIN, EWOULDBLOCK: return
            case EINTR, ECONNABORTED: continue
            default:
                // EMFILE/ENFILE or anything else: stop polling a socket that stays
                // readable, and try again in a second.
                guard !listenSuspended else { return }
                listenSuspended = true
                source.suspend()
                queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, listenSource === source, listenSuspended else { return }
                    listenSuspended = false
                    source.resume()
                }
                return
            }
        }
    }

    private func adopt(_ fd: Int32) {
        // Darwin hands accepted sockets the listener's O_NONBLOCK; writes here must block (bounded by the send timeout).
        let flags = fcntl(fd, F_GETFL)
        guard flags != -1, fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) != -1 else { Darwin.close(fd); return }
        UnixSocket.disableSIGPIPE(fd)
        let connection = Connection(fd: fd, queue: queue)
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.onLine = { [weak self] connection, line in self?.dispatch(line, on: connection) }
        connection.onClose = { [weak self] in self?.connections[key] = nil }
        connection.resume()
    }

    private func dispatch(_ line: String, on connection: Connection) {
        connection.beginRequest()
        let handler = self.handler
        let queue = self.queue
        DispatchQueue.main.async {
            let reply = MainActor.assumeIsolated { handler(line) }
            queue.async { connection.finishRequest(reply) }
        }
    }
}

/// One client. Everything here runs on the server's queue.
private final class Connection: @unchecked Sendable {
    /// A line longer than this is a misbehaving client, not a request.
    private static let maxLineBytes = 4 * 1024 * 1024

    private let fd: Int32
    private let source: DispatchSourceRead
    private var buffer = Data()
    /// Start of the bytes in `buffer` not yet searched for a newline.
    private var scanFrom = 0
    /// Requests handed to the main actor and not yet answered.
    private var pending = 0
    private var inputEnded = false
    private var readStopped = false
    private var isClosed = false

    var onLine: ((Connection, String) -> Void)?
    var onClose: (() -> Void)?

    init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        // Strong captures are released once the source is cancelled, which
        // every connection eventually is.
        source.setEventHandler { [self] in readAvailable() }
        source.setCancelHandler { [self] in sourceDidCancel() }
    }

    func resume() { source.resume() }

    func beginRequest() { pending += 1 }

    func finishRequest(_ reply: String?) {
        pending -= 1
        if let reply, !isClosed, !UnixSocket.writeAll(fd, Data((reply + "\n").utf8), timeout: UnixSocket.sendTimeoutSeconds) {
            close()
            return
        }
        closeIfFinished()
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        var count: Int
        repeat { count = read(fd, &chunk, chunk.count) } while count < 0 && errno == EINTR
        if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
        guard count > 0 else {
            // The client half-closed or hung up. Stop reading, but keep the
            // descriptor until replies already in flight are written.
            inputEnded = true
            source.cancel()
            return
        }
        buffer.append(contentsOf: chunk[0..<count])
        var lineStart = buffer.startIndex
        var searchFrom = buffer.index(buffer.startIndex, offsetBy: scanFrom)
        while let newline = buffer[searchFrom...].firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[lineStart..<newline], as: UTF8.self)
            lineStart = buffer.index(after: newline)
            searchFrom = lineStart
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { onLine?(self, line) }
        }
        // Drop the consumed prefix once per read.
        if lineStart > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<lineStart) }
        scanFrom = buffer.count
        if buffer.count > Self.maxLineBytes { close() }
    }

    private func sourceDidCancel() {
        readStopped = true
        if isClosed { Darwin.close(fd) } else { closeIfFinished() }
    }

    private func closeIfFinished() {
        if inputEnded && pending == 0 { close() }
    }

    /// Closes now, dropping any replies still in flight.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        onClose?()
        onClose = nil
        onLine = nil
        // The fd is closed only once the read source has let go of it.
        if readStopped { Darwin.close(fd) } else { source.cancel() }
    }
}
#endif
