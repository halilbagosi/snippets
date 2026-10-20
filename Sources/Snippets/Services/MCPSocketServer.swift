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

    /// Writes all of `data`, retrying short writes. False once the peer is gone.
    @discardableResult
    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
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
final class MCPSocketServer: @unchecked Sendable {
    typealias Handler = @MainActor @Sendable (String) -> String?

    let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.halilbagosi.Snippets.mcp")
    private var listenSource: DispatchSourceRead?
    private var connections: [ObjectIdentifier: Connection] = [:]

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
        // Owner only: whoever can connect can read the whole library.
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { let e = errno; close(fd); unlink(path); throw UnixSocket.Failure.system("listen", e) }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection(on: fd) }
        source.setCancelHandler { close(fd) }
        queue.sync { listenSource = source }
        source.resume()
    }

    /// Stops listening and drops every connection. Safe to call twice.
    func stop() {
        queue.sync {
            listenSource?.cancel()
            listenSource = nil
            let open = Array(connections.values)
            connections.removeAll()
            open.forEach { $0.close() }
        }
        unlink(path)
    }

    private func acceptConnection(on listenFD: Int32) {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
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
    private let fd: Int32
    private let source: DispatchSourceRead
    private var buffer = Data()
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
        if let reply, !isClosed, !UnixSocket.writeAll(fd, Data((reply + "\n").utf8)) {
            close()
            return
        }
        closeIfFinished()
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(fd, &chunk, chunk.count)
        guard count > 0 else {
            // The client half-closed or hung up. Stop reading, but keep the
            // descriptor until replies already in flight are written.
            inputEnded = true
            source.cancel()
            return
        }
        buffer.append(contentsOf: chunk[0..<count])
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer = Data(buffer[buffer.index(after: newline)...])
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { onLine?(self, line) }
        }
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
