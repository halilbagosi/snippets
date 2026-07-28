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
    /// semaphore. Never inline this into the static initializer: this lazy
    /// static is first touched during SwiftUI body evaluation, and
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

/// Compiles SwiftUI snippets to dylibs and loads them in-process.
///
/// Dylibs are cached by content hash (re-running unchanged code is instant)
/// and never unloaded — dlclose is unsafe once Swift metadata has escaped.
/// The per-hash module and symbol names keep multiple loaded snippets from
/// colliding.
actor SwiftPreviewBuilder {
    static let shared = SwiftPreviewBuilder()

    enum BuildError: LocalizedError {
        case toolchainUnavailable
        case compileFailed(String)
        case loadFailed(String)

        var errorDescription: String? {
            switch self {
            case .toolchainUnavailable:
                return "Swift previews need the Xcode toolchain. Install Xcode, then relaunch Snippets."
            case .compileFailed(let diagnostics):
                return diagnostics
            case .loadFailed(let message):
                return "Failed to load compiled preview: \(message)"
            }
        }
    }

    private var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SnippetPreviews", isDirectory: true)
    }

    /// Compiles (or reuses a cached dylib for) the snippet and returns a
    /// factory that creates a fresh hosted view on the main thread.
    func build(code: String) async throws -> @MainActor () -> NSView? {
        try await build(entry: code, helpers: [])
    }

    /// Entry plus resolved dependency sources, compiled as one unit. The
    /// cache key is the combined-source hash, so helper edits invalidate it.
    func build(entry: String, helpers: [String]) async throws -> @MainActor () -> NSView? {
        guard let swiftc = SwiftToolchain.swiftcURL else {
            throw BuildError.toolchainUnavailable
        }
        let harness = try SwiftPreviewHarness.make(entry: entry, helpers: helpers)
        let dylibURL = cacheDirectory.appendingPathComponent("\(harness.hash).dylib")

        // A cache hit counts only if the artifact is one this install built and
        // nothing has touched since. Anything else — no tag, wrong tag, a
        // symlink where a file should be — is discarded and rebuilt rather
        // than loaded, because `dlopen` is not a step you get to take back.
        var usedCache = FileManager.default.fileExists(atPath: dylibURL.path)
        if usedCache, !(SwiftPreviewCacheIntegrity.isPlainOwnedFile(dylibURL)
                        && SwiftPreviewCacheIntegrity.isTrusted(dylibURL)) {
            SwiftPreviewCacheIntegrity.discard(dylibURL)
            usedCache = false
        }
        if !usedCache {
            try compileToCache(swiftc: swiftc, harness: harness, dylibURL: dylibURL)
        }

        var handle = dlopen(dylibURL.path, RTLD_NOW)
        if handle == nil, usedCache {
            // Poisoned cache (e.g. a truncated dylib left by a crash
            // mid-write): drop the artifact and rebuild once.
            SwiftPreviewCacheIntegrity.discard(dylibURL)
            try compileToCache(swiftc: swiftc, harness: harness, dylibURL: dylibURL)
            handle = dlopen(dylibURL.path, RTLD_NOW)
        }
        guard let handle else {
            let message = dlerror().map { String(cString: $0) } ?? "dlopen failed"
            throw BuildError.loadFailed(message)
        }
        guard let symbol = dlsym(handle, harness.symbolName) else {
            throw BuildError.loadFailed("symbol \(harness.symbolName) not found")
        }
        typealias Factory = @convention(c) () -> UnsafeMutableRawPointer
        let factory = unsafeBitCast(symbol, to: Factory.self)
        return {
            Unmanaged<NSView>.fromOpaque(factory()).takeRetainedValue()
        }
    }

    /// Compiles to a uniquely-named temp path in the cache directory, then
    /// atomically promotes it to `dylibURL` — a crash mid-compile can never
    /// leave a truncated dylib at the final path.
    private func compileToCache(swiftc: URL, harness: SwiftPreviewHarness.Harness, dylibURL: URL) throws {
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
        let tempURL = cacheDirectory
            .appendingPathComponent("\(harness.hash).dylib.tmp-\(UUID().uuidString)")
        do {
            try compile(swiftc: swiftc, source: sourceURL, output: tempURL, hash: harness.hash)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        try Self.promoteArtifact(at: tempURL, to: dylibURL)
        // Tagged after promotion, so the tag only ever vouches for bytes that
        // reached the final path.
        SwiftPreviewCacheIntegrity.sign(dylibURL)
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

    private func compile(swiftc: URL, source: URL, output: URL, hash: String) throws {
        let process = Process()
        // Route through xcrun so the SDK is resolved, and pin the target to
        // the app's deployment platform: swiftc defaults to the host OS
        // version, whose stdlib the SDK may not ship yet (e.g. host 27 with
        // a macOS 26 SDK).
        #if arch(arm64)
        let target = "arm64-apple-macos26.0"
        #else
        let target = "x86_64-apple-macos26.0"
        #endif
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swiftc",
            "-target", target,
            "-parse-as-library",
            "-emit-library",
            "-Onone",
            "-module-name", "SnippetPreview_\(hash.prefix(8))",
            "-o", output.path,
            source.path
        ]
        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let diagnostics = String(
                decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            )
            // Point diagnostics at snippet lines, not the temp file path.
            let cleaned = diagnostics.replacingOccurrences(of: source.path + ":", with: "line ")
            throw BuildError.compileFailed(cleaned)
        }
    }
}
