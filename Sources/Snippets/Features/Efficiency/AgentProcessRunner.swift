#if !APP_STORE
import Foundation

struct AgentProcessResult: Sendable, Equatable {
    var exitCode: Int32
    var stdout: Data
    var stderr: Data
}

/// Runs one process to completion. Injectable so rater logic is testable
/// without spawning anything.
protocol AgentProcessRunning: Sendable {
    /// Throws `.timedOut` after `timeout`, `.cancelled` when the task is
    /// cancelled, `.failed` when the process cannot start.
    func run(
        executable: URL, arguments: [String], stdin: Data,
        environment: [String: String], workingDirectory: URL, timeout: TimeInterval
    ) async throws -> AgentProcessResult
}

/// `Process`-backed runner. Stdin, stdout and stderr are files in a private
/// temp directory, never pipes, so a lingering grandchild can never block
/// completion. Timeout and cancellation: SIGTERM, then SIGKILL after 2 s.
struct FoundationProcessRunner: AgentProcessRunning {
    var killGrace: TimeInterval = 2

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private(set) var cancelled = false
        private(set) var timedOut = false

        func attach(_ process: Process) -> Bool {
            lock.lock(); defer { lock.unlock() }
            self.process = process
            return cancelled
        }
        func cancel() { lock.lock(); cancelled = true; let p = process; lock.unlock(); p?.terminate() }
        func timeOut() { lock.lock(); timedOut = true; let p = process; lock.unlock(); p?.terminate() }
        func kill9() {
            lock.lock(); let p = process; lock.unlock()
            if let p, p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }

    func run(
        executable: URL, arguments: [String], stdin: Data,
        environment: [String: String], workingDirectory: URL, timeout: TimeInterval
    ) async throws -> AgentProcessResult {
        if Task.isCancelled { throw EfficiencyRatingError.cancelled }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippets-run-\(UUID().uuidString)", isDirectory: true)
        let inURL = scratch.appendingPathComponent("in"), outURL = scratch.appendingPathComponent("out"),
            errURL = scratch.appendingPathComponent("err")
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            try stdin.write(to: inURL)
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            FileManager.default.createFile(atPath: errURL.path, contents: nil)
        } catch { throw EfficiencyRatingError.failed("could not prepare the run: \(error.localizedDescription)") }
        defer { try? FileManager.default.removeItem(at: scratch) }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        let inHandle = try? FileHandle(forReadingFrom: inURL)
        let outHandle = try? FileHandle(forWritingTo: outURL)
        let errHandle = try? FileHandle(forWritingTo: errURL)
        defer { try? inHandle?.close(); try? outHandle?.close(); try? errHandle?.close() }
        process.standardInput = inHandle
        process.standardOutput = outHandle
        process.standardError = errHandle

        let state = State()
        let grace = killGrace
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch {
                    cont.resume(throwing: EfficiencyRatingError.failed("could not start the agent: \(error.localizedDescription)"))
                    return
                }
                if state.attach(process) { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning else { return }
                    state.timeOut()
                    DispatchQueue.global().asyncAfter(deadline: .now() + grace) { state.kill9() }
                }
            }
        } onCancel: {
            state.cancel()
            DispatchQueue.global().asyncAfter(deadline: .now() + grace) { state.kill9() }
        }

        if state.cancelled { throw EfficiencyRatingError.cancelled }
        if state.timedOut { throw EfficiencyRatingError.timedOut }
        return AgentProcessResult(
            exitCode: exitCode,
            stdout: (try? Data(contentsOf: outURL)) ?? Data(),
            stderr: (try? Data(contentsOf: errURL)) ?? Data()
        )
    }
}
#endif
