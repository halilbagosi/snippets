#if !APP_STORE
import Foundation

/// Finds an agent CLI by executable name. A Finder-launched app does not
/// inherit the shell's PATH, so well-known install directories are checked
/// first and a login shell is the last resort.
///
/// Lookups can spawn a shell for up to ~4 s, so the public API is `async` and
/// runs them on a background queue; never call the sync `lookup` on the main
/// thread. Found and not-found results are both cached until `refresh`.
final class AgentCLILocator: @unchecked Sendable {
    static let shared = AgentCLILocator()

    private enum Entry { case found(URL), notFound }

    private let directories: [String]
    private let isExecutable: @Sendable (String) -> Bool
    private let shellProbe: @Sendable (String) -> URL?
    private let lock = NSLock()
    private var cache: [String: Entry] = [:]

    init(
        directories: [String] = AgentCLILocator.candidateDirectories(home: NSHomeDirectory()),
        isExecutable: @escaping @Sendable (String) -> Bool = AgentCLILocator.isRegularExecutable,
        shellProbe: @escaping @Sendable (String) -> URL? = AgentCLILocator.loginShellProbe
    ) {
        self.directories = directories
        self.isExecutable = isExecutable
        self.shellProbe = shellProbe
    }

    /// In priority order.
    static func candidateDirectories(home: String) -> [String] {
        [
            "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin",
        ]
    }

    /// Only plain executable names may reach the shell fallback or a path.
    static func isSafeName(_ name: String) -> Bool {
        guard let first = name.first, first != ".", first != "-" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
    }

    /// A regular file (symlinks followed) the user may execute — not a directory.
    static func isRegularExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    static func firstExecutable(
        named name: String, in directories: [String], isExecutable: (String) -> Bool
    ) -> URL? {
        guard isSafeName(name) else { return nil }
        for dir in directories {
            let path = "\(dir)/\(name)"
            if isExecutable(path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// Cached result, resolving off the calling thread on a miss.
    func locate(_ name: String) async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: self.lookup(name)) }
        }
    }

    /// Re-resolves, replacing any cached answer. Call when Settings opens.
    func refresh(_ name: String) async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.resolve(name))
            }
        }
    }

    /// Blocking; only reached from the background queues in `locate`.
    private func lookup(_ name: String) -> URL? {
        lock.lock()
        let entry = cache[name]
        lock.unlock()
        switch entry {
        case .found(let url): return url
        case .notFound: return nil
        case nil: return resolve(name)
        }
    }

    private func resolve(_ name: String) -> URL? {
        let found = Self.firstExecutable(named: name, in: directories, isExecutable: isExecutable)
            ?? (Self.isSafeName(name) ? shellProbe(name) : nil)
        lock.lock()
        cache[name] = found.map(Entry.found) ?? .notFound
        lock.unlock()
        return found
    }

    /// `/bin/zsh -lc 'command -v <name>'`. Hard bound: output goes to a temp
    /// file (never a pipe a grandchild could hold open), the wait has a 3 s
    /// deadline, then SIGTERM, then SIGKILL.
    static func loginShellProbe(_ name: String) -> URL? {
        guard isSafeName(name) else { return nil }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippets-locate-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: outURL.path, contents: nil),
              let out = try? FileHandle(forWritingTo: outURL) else { return nil }
        defer { try? out.close(); try? FileManager.default.removeItem(at: outURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(name)"]
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        if exited.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 0.5)
            }
            return nil
        }
        guard process.terminationStatus == 0,
              let data = try? Data(contentsOf: outURL),
              let line = String(data: data, encoding: .utf8)?
                .split(separator: "\n").last.map(String.init),
              line.hasPrefix("/"), isRegularExecutable(line)
        else { return nil }
        return URL(fileURLWithPath: line)
    }
}
#endif
