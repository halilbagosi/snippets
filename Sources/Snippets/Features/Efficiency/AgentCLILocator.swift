#if !APP_STORE
import Foundation

/// Finds an agent CLI by executable name. A Finder-launched app does not
/// inherit the shell's PATH, so well-known install directories are checked
/// first and a login shell is the last resort.
final class AgentCLILocator: @unchecked Sendable {
    static let shared = AgentCLILocator()

    /// In priority order.
    static func candidateDirectories(home: String) -> [String] {
        [
            "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin",
        ]
    }

    /// Only plain executable names may reach the shell fallback.
    static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
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

    private let lock = NSLock()
    private var cache: [String: URL] = [:]

    /// Cached; call `refresh(name)` when Settings opens.
    func locate(_ name: String) -> URL? {
        lock.lock()
        if let hit = cache[name] { lock.unlock(); return hit }
        lock.unlock()
        return refresh(name)
    }

    @discardableResult
    func refresh(_ name: String) -> URL? {
        let found = Self.firstExecutable(
            named: name,
            in: Self.candidateDirectories(home: NSHomeDirectory()),
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        ) ?? Self.viaLoginShell(name)
        lock.lock()
        cache[name] = found
        lock.unlock()
        return found
    }

    /// `/bin/zsh -lc 'command -v <name>'`, killed after 3 s.
    private static func viaLoginShell(_ name: String) -> URL? {
        guard isSafeName(name) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(name)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        guard process.terminationStatus == 0,
              let line = String(data: data, encoding: .utf8)?
                .split(separator: "\n").last.map(String.init),
              line.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: line)
        else { return nil }
        return URL(fileURLWithPath: line)
    }
}
#endif
