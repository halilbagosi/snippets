// Compiles user code with the Xcode toolchain and dlopens it into this
// process — not shippable on the Mac App Store (guidelines 2.4.5 / 2.5.2), and
// impossible inside the App Sandbox anyway. The AppStore configuration
// defines APP_STORE and leaves the whole engine out.
#if !APP_STORE
import AppKit
import CryptoKit
import Foundation
import OSLog
import Security

/// Locates the Swift toolchain. Previews degrade to an "Xcode required"
/// state when unavailable.
enum SwiftToolchain {
    /// Resolved once per launch; `xcrun` honors DEVELOPER_DIR / xcode-select.
    ///
    /// The subprocess runs on a background queue and the caller blocks on a
    /// semaphore. Never inline this into the static initializer, and keep it
    /// out of SwiftUI body evaluation: when it was first touched there,
    /// `waitUntilExit()` on the main thread spins the run loop — an animation
    /// frame then re-enters body → re-enters this `dispatch_once` → SIGTRAP
    /// (the preview-toggle crash).
    static let swiftcURL: URL? = {
        // Boxed so the background closure can hand the value back without
        // capturing a mutable local (Swift 6 concurrency); the semaphore
        // orders the write before the read.
        final class ResultBox: @unchecked Sendable { var url: URL? }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            defer { semaphore.signal() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["--find", "swiftc"]
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return
            }
            guard process.terminationStatus == 0 else { return }
            let path = String(
                decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { box.url = URL(fileURLWithPath: path) }
        }
        semaphore.wait()
        return box.url
    }()

    static var isAvailable: Bool { swiftcURL != nil }
}

/// Authenticates the compiled-preview cache.
///
/// `SwiftPreviewBuilder` reuses a cached dylib whenever one exists at the
/// content-hash path, and `dlopen` on that path loads whatever is there into
/// this process — which is unsandboxed, with the hardened runtime off. The
/// cache lives under `~/Library/Caches`, so anything else running as this user
/// can drop a file at a predictable name and be loaded, inheriting every TCC
/// grant the app holds. That presumes the attacker already has user-level
/// execution, so this is a persistence step rather than a way in; it is also
/// a cheap one to remove.
///
/// Each artifact is therefore tagged with an HMAC over its bytes, keyed by a
/// per-install secret in the Keychain, and the tag is checked before load. The
/// key placement is the point: a secret sitting next to the artifact would be
/// rewritable by the same attacker who rewrote the artifact, whereas a Keychain
/// item is reachable only through this app's own signed identity.
///
/// A missing or wrong tag is treated as a poisoned cache — the artifact is
/// discarded and rebuilt from source, so a failure here costs a recompile
/// rather than a broken feature.
enum SwiftPreviewCacheIntegrity {
    private static let logger = Logger(subsystem: "Snippets", category: "PreviewCache")
    private static let service = "com.snippets.SwiftPreviewCache"
    private static let account = "artifact-hmac-key"

    /// Per-install HMAC key, created on first use.
    ///
    /// `ThisDeviceOnly` keeps it out of Keychain backups and off other Macs:
    /// the key authenticates *this* machine's build cache, and a copy
    /// travelling to another install would only widen what it vouches for.
    private static let key: SymmetricKey? = {
        if let existing = loadKey() { return existing }
        let fresh = SymmetricKey(size: .bits256)
        return storeKey(fresh) ? fresh : nil
    }()

    private static func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func storeKey(_ key: SymmetricKey) -> Bool {
        let data = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(attributes as CFDictionary)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Could not store preview-cache key: \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }

    private static func tagURL(for artifact: URL) -> URL {
        artifact.appendingPathExtension("tag")
    }

    private static func tag(for data: Data, key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    /// Writes the authentication tag for a freshly built artifact.
    static func sign(_ artifact: URL) {
        guard let key, let data = try? Data(contentsOf: artifact) else { return }
        try? tag(for: data, key: key).write(to: tagURL(for: artifact), options: .atomic)
    }

    /// Whether `artifact` is exactly what this install built.
    ///
    /// Without a key (Keychain unavailable) this returns false, which routes
    /// every load through a rebuild: slower, never less safe.
    static func isTrusted(_ artifact: URL) -> Bool {
        guard let key,
              let expected = try? Data(contentsOf: tagURL(for: artifact)),
              let data = try? Data(contentsOf: artifact) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            expected, authenticating: data, using: key
        )
    }

    /// Removes an artifact and its tag together, so a later build cannot find
    /// a tag vouching for bytes that are no longer there.
    static func discard(_ artifact: URL) {
        try? FileManager.default.removeItem(at: artifact)
        try? FileManager.default.removeItem(at: tagURL(for: artifact))
    }

    /// Whether the cache path is a plain file this user owns, rather than a
    /// symlink pointing somewhere more interesting. Checked before the HMAC
    /// because `dlopen` follows links and the tag would authenticate the
    /// link's target, not the path being asked for.
    static func isPlainOwnedFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular else { return false }
        let owner = attributes[.ownerAccountID] as? NSNumber
        return owner?.uint32Value == getuid()
    }
}

/// Compiles Swift snippets and either loads them in-process (views) or runs
/// them as a child process (everything else).
///
/// Artifacts are cached by content hash (re-running unchanged code is
/// instant). Dylibs are never unloaded — dlclose is unsafe once Swift
/// metadata has escaped. The per-hash module and symbol names keep multiple
/// loaded snippets from colliding.
actor SwiftPreviewBuilder {
    static let shared = SwiftPreviewBuilder()

    /// What a successful build produces.
    enum Output {
        /// Creates a fresh hosted view on the main thread.
        case view(@MainActor () -> NSView?)
        /// The finished console run.
        case console(ConsoleRun)
    }

    struct ConsoleRun: Equatable, Sendable {
        /// Standard output and standard error, interleaved as written.
        let output: String
        let exitStatus: Int32
        let timedOut: Bool
        let truncated: Bool
    }

    enum BuildError: LocalizedError {
        case toolchainUnavailable
        case compileFailed(String)
        case compileTimedOut
        case loadFailed(String)

        var errorDescription: String? {
            switch self {
            case .toolchainUnavailable:
                return "Swift previews need the Xcode toolchain. Install Xcode, then relaunch Snippets."
            case .compileFailed(let diagnostics):
                return diagnostics
            case .compileTimedOut:
                return "Compiling took longer than \(Int(SwiftPreviewBuilder.compileTimeout)) seconds and was stopped. Very large view bodies can overwhelm the type checker; splitting them into smaller views helps."
            case .loadFailed(let message):
                return "Failed to load compiled preview: \(message)"
            }
        }
    }

    static let compileTimeout: TimeInterval = 180
    /// Console snippets are demonstrations, not jobs: anything still running
    /// after this is almost certainly an infinite loop.
    static let runTimeout: TimeInterval = 10
    private static let compileOutputLimit = 512 * 1024
    private static let runOutputLimit = 256 * 1024

    private let cacheDirectory: URL

    /// `cacheDirectory` is for tests; the app uses `shared` and the default.
    init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory ?? {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return base.appendingPathComponent("SnippetPreviews", isDirectory: true)
        }()
    }

    func build(code: String) async throws -> Output {
        try await build(entry: code, helpers: [])
    }

    /// Entry plus resolved dependency sources, compiled as one unit. The
    /// cache key is the combined-source hash, so helper edits invalidate it.
    func build(entry: String, helpers: [String]) async throws -> Output {
        guard SwiftToolchain.isAvailable else {
            throw BuildError.toolchainUnavailable
        }
        let harness = try SwiftPreviewHarness.make(entry: entry, helpers: helpers)
        let artifact = try await cachedArtifact(for: harness)

        switch harness.mode {
        case .view:
            return .view(try load(artifact, symbol: harness.symbolName))
        case .console:
            return .console(try await runConsole(artifact))
        }
    }

    /// The compiled artifact for `harness`, from the cache when there is a
    /// trusted one, compiled otherwise.
    ///
    /// A cache hit counts only if the artifact is one this install built and
    /// nothing has touched since. Anything else — no tag, wrong tag, a
    /// symlink where a file should be — is discarded and rebuilt rather than
    /// used, because `dlopen`/exec is not a step you get to take back.
    private func cachedArtifact(for harness: SwiftPreviewHarness.Harness) async throws -> URL {
        let suffix = harness.mode == .view ? "dylib" : "run"
        let artifact = cacheDirectory.appendingPathComponent("\(harness.hash).\(suffix)")
        if FileManager.default.fileExists(atPath: artifact.path) {
            if SwiftPreviewCacheIntegrity.isPlainOwnedFile(artifact),
               SwiftPreviewCacheIntegrity.isTrusted(artifact) {
                return artifact
            }
            SwiftPreviewCacheIntegrity.discard(artifact)
        }
        try await compileToCache(harness: harness, artifact: artifact)
        return artifact
    }

    private func load(_ dylibURL: URL, symbol: String) throws -> @MainActor () -> NSView? {
        guard let handle = dlopen(dylibURL.path, RTLD_NOW) else {
            // Whatever is at the path is unusable (e.g. a truncated dylib left
            // by a crash mid-write); drop it so the next run rebuilds.
            let message = dlerror().map { String(cString: $0) } ?? "dlopen failed"
            SwiftPreviewCacheIntegrity.discard(dylibURL)
            throw BuildError.loadFailed(message)
        }
        guard let symbol = dlsym(handle, symbol) else {
            throw BuildError.loadFailed("symbol \(symbol) not found")
        }
        typealias Factory = @convention(c) () -> UnsafeMutableRawPointer
        let factory = unsafeBitCast(symbol, to: Factory.self)
        return {
            Unmanaged<NSView>.fromOpaque(factory()).takeRetainedValue()
        }
    }

    /// Runs a console artifact out of process: a crash or a hang there costs
    /// the run, not the app.
    private func runConsole(_ executable: URL) async throws -> ConsoleRun {
        // Re-checked at the last moment before exec, as for dlopen.
        guard SwiftPreviewCacheIntegrity.isPlainOwnedFile(executable),
              SwiftPreviewCacheIntegrity.isTrusted(executable) else {
            SwiftPreviewCacheIntegrity.discard(executable)
            throw BuildError.loadFailed("the compiled program changed on disk; run again")
        }
        let result = try await ProcessRunner.run(
            executable, arguments: [],
            timeout: Self.runTimeout, outputLimit: Self.runOutputLimit,
            currentDirectory: FileManager.default.temporaryDirectory
        )
        return ConsoleRun(
            output: result.output, exitStatus: result.status,
            timedOut: result.timedOut, truncated: result.truncated
        )
    }

    /// Compiles to a uniquely-named temp path in the cache directory, then
    /// atomically promotes it to `artifact` — a crash mid-compile can never
    /// leave a truncated artifact at the final path.
    private func compileToCache(harness: SwiftPreviewHarness.Harness, artifact: URL) async throws {
        // 0700 so the compiled artifacts are not readable or, more to the
        // point, writable by other accounts on the machine. The parent Caches
        // directory is already user-scoped; this narrows the window a shared or
        // misconfigured home directory would otherwise leave open.
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let sourceURL = cacheDirectory.appendingPathComponent("\(harness.hash).swift")
        try harness.source.write(to: sourceURL, atomically: true, encoding: .utf8)
        let tempURL = artifact.appendingPathExtension("tmp-\(UUID().uuidString)")
        do {
            try await compile(harness: harness, source: sourceURL, output: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        try Self.promoteArtifact(at: tempURL, to: artifact)
        // Tagged after promotion, so the tag only ever vouches for bytes that
        // reached the final path.
        SwiftPreviewCacheIntegrity.sign(artifact)
    }

    /// Moves a freshly-built artifact into its final cache location. If the
    /// destination already exists (a concurrent build won), the temp file is
    /// discarded and the existing artifact is used. The temp file never
    /// survives, success or failure.
    static func promoteArtifact(
        at tempURL: URL, to finalURL: URL, fileManager: FileManager = .default
    ) throws {
        defer { try? fileManager.removeItem(at: tempURL) }
        guard !fileManager.fileExists(atPath: finalURL.path) else { return }
        do {
            try fileManager.moveItem(at: tempURL, to: finalURL)
        } catch CocoaError.fileWriteFileExists {
            // Concurrent winner appeared between the check and the move.
        }
    }

    /// Arguments for `xcrun`, separated out so tests can check them.
    static func compileArguments(
        for harness: SwiftPreviewHarness.Harness, source: URL, output: URL
    ) -> [String] {
        // Pin the target to the app's deployment platform: swiftc defaults to
        // the host OS version, whose stdlib the SDK may not ship yet (e.g.
        // host 27 with a macOS 26 SDK).
        #if arch(arm64)
        let target = "arm64-apple-macos26.0"
        #else
        let target = "x86_64-apple-macos26.0"
        #endif
        var arguments = ["swiftc", "-target", target]
        switch harness.mode {
        case .view:
            arguments += ["-parse-as-library", "-emit-library"]
        case .console(let parseAsLibrary):
            if parseAsLibrary { arguments.append("-parse-as-library") }
        }
        return arguments + [
            "-Onone",
            // One line per diagnostic plus the offending source line, with
            // the file:line from `#sourceLocation`. The default style prints
            // excerpts of the generated file with its own line numbers,
            // which contradict the snippet's.
            "-diagnostic-style=llvm",
            "-module-name", "SnippetPreview_\(harness.hash.prefix(8))",
            "-o", output.path,
            source.path
        ]
    }

    private func compile(harness: SwiftPreviewHarness.Harness, source: URL, output: URL) async throws {
        // Routed through xcrun so the SDK is resolved.
        let result = try await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: Self.compileArguments(for: harness, source: source, output: output),
            timeout: Self.compileTimeout, outputLimit: Self.compileOutputLimit
        )
        if result.timedOut { throw BuildError.compileTimedOut }
        guard result.status == 0 else {
            throw BuildError.compileFailed(
                SwiftPreviewHarness.describeCompileFailure(result.output, harness: harness)
            )
        }
    }
}

/// Runs a child process to completion without the two classic hangs: output
/// is drained while the child runs (a full pipe otherwise blocks a chatty
/// child forever — swiftc reporting a few hundred errors fills 64 KB), and a
/// deadline terminates a child that never finishes.
enum ProcessRunner {
    struct Result: Sendable {
        let status: Int32
        /// Standard output and standard error, interleaved.
        let output: String
        let timedOut: Bool
        /// More than `outputLimit` bytes were written; the rest was read and
        /// discarded so the child could keep going.
        let truncated: Bool
    }

    /// State shared between the reader, the deadline and the waiting thread.
    private final class Shared: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var truncated = false
        private var timedOut = false
        let limit: Int
        init(limit: Int) { self.limit = limit }

        func append(_ chunk: Data) {
            lock.withLock {
                let room = limit - data.count
                if chunk.count > room { truncated = true }
                if room > 0 { data.append(chunk.prefix(room)) }
            }
        }
        func markTimedOut() { lock.withLock { timedOut = true } }
        func snapshot() -> (Data, Bool, Bool) { lock.withLock { (data, truncated, timedOut) } }
    }

    static func run(
        _ executable: URL, arguments: [String],
        timeout: TimeInterval, outputLimit: Int, currentDirectory: URL? = nil
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                if let currentDirectory { process.currentDirectoryURL = currentDirectory }
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // Our copy of the write end must go, or the reader never sees
                // EOF.
                try? pipe.fileHandleForWriting.close()

                let shared = Shared(limit: outputLimit)
                let readerDone = DispatchSemaphore(value: 0)
                let reader = pipe.fileHandleForReading
                DispatchQueue.global(qos: .userInitiated).async {
                    while true {
                        let chunk = reader.availableData
                        if chunk.isEmpty { break }
                        shared.append(chunk)
                    }
                    readerDone.signal()
                }

                let pid = process.processIdentifier
                let deadline = DispatchWorkItem {
                    shared.markTimedOut()
                    kill(pid, SIGTERM)
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        kill(pid, SIGKILL)
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                process.waitUntilExit()
                deadline.cancel()
                // A grandchild that inherited the pipe can hold it open after
                // the child exits; don't wait on it for long.
                _ = readerDone.wait(timeout: .now() + 2)

                let (data, truncated, timedOut) = shared.snapshot()
                continuation.resume(returning: Result(
                    status: process.terminationStatus,
                    output: String(decoding: data, as: UTF8.self),
                    timedOut: timedOut,
                    truncated: truncated
                ))
            }
        }
    }
}
#endif
