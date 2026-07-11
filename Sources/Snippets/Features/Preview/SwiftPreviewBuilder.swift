import AppKit
import Foundation

/// Locates the Swift toolchain. Previews degrade to an "Xcode required"
/// state when unavailable.
enum SwiftToolchain {
    /// Resolved once per launch; `xcrun` honors DEVELOPER_DIR / xcode-select.
    static let swiftcURL: URL? = {
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
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let path = String(
            decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }()

    static var isAvailable: Bool { swiftcURL != nil }
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

        if !FileManager.default.fileExists(atPath: dylibURL.path) {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let sourceURL = cacheDirectory.appendingPathComponent("\(harness.hash).swift")
            try harness.source.write(to: sourceURL, atomically: true, encoding: .utf8)
            try compile(swiftc: swiftc, source: sourceURL, output: dylibURL, hash: harness.hash)
        }

        guard let handle = dlopen(dylibURL.path, RTLD_NOW) else {
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
