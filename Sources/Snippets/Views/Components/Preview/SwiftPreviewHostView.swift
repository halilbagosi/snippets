// Hosts SwiftPreviewBuilder output; see the note there on APP_STORE.
#if !APP_STORE
import SwiftUI

/// Live preview for Swift snippets. Compilation is explicit (Run): it takes
/// seconds and executes the snippet's code, so it never starts on its own.
/// SwiftUI views render in place; other code runs as a console program and
/// its output is shown.
struct SwiftPreviewHostView: View {
    let entry: String
    let helpers: [String]
    let theme: Theme

    @State private var phase: Phase = .idle
    @State private var builtCode: String? = nil
    /// Bumped by every run, so a slow build that finishes after a newer one
    /// started can't overwrite the newer result.
    @State private var generation = 0

    /// Combined-source key: a helper edit invalidates the build like an
    /// entry edit does.
    private var code: String { (helpers + [entry]).joined(separator: "\u{0}") }

    private enum Phase {
        case idle
        case building
        case ready(@MainActor () -> NSView?)
        case console(SwiftPreviewBuilder.ConsoleRun)
        case failed(String)
        case unavailable(String)
    }

    private var codeChangedSinceBuild: Bool {
        switch phase {
        case .idle, .building, .unavailable: return false
        case .ready, .console, .failed: return builtCode != nil && builtCode != code
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch phase {
            case .idle:
                runPrompt
            case .building:
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("compiling…")
                        .font(Mono.font(size: 11))
                        .foregroundStyle(theme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready(let makeView):
                CompiledSwiftView(makeView: makeView)
                    .id(builtCode)
            case .console(let run):
                consoleOutput(run)
            case .failed(let diagnostics):
                ScrollView {
                    Text(diagnostics)
                        .font(Mono.font(size: 11))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DSToken.Spacing.md)
                }
            case .unavailable(let message):
                PreviewUnavailableView(message: message, theme: theme)
            }

            if codeChangedSinceBuild {
                rerunBadge
            } else if case .console = phase {
                // A program can print something different each run.
                FilterTag(label: "run again", icon: "arrow.clockwise", accent: theme.accent, isSelected: false) {
                    run()
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.accent)
            Text("Compiles and runs this snippet.")
                .font(Mono.font(size: 11))
                .foregroundStyle(theme.textMuted)
            FilterTag(label: "run", icon: "play.fill", accent: theme.accent, isSelected: true) {
                run()
            }
            Text("Views render here; other code runs and shows what it prints.")
                .font(Mono.font(size: 10))
                .foregroundStyle(theme.textMuted.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSToken.Spacing.md)
    }

    private func consoleOutput(_ run: SwiftPreviewBuilder.ConsoleRun) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !run.output.isEmpty {
                    Text(run.output)
                        .font(Mono.font(size: 12))
                        .foregroundStyle(theme.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(Self.consoleStatus(run))
                    .font(Mono.font(size: 10))
                    .foregroundStyle(run.exitStatus == 0 && !run.timedOut ? theme.textMuted : .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DSToken.Spacing.md)
            // Clear of the "run again" button.
            .padding(.trailing, 90)
        }
    }

    /// The line under a console run's output.
    static func consoleStatus(_ run: SwiftPreviewBuilder.ConsoleRun) -> String {
        if run.timedOut {
            return "stopped after \(Int(SwiftPreviewBuilder.runTimeout)) seconds — the program was still running"
        }
        var parts: [String] = []
        if run.output.isEmpty {
            parts.append(run.exitStatus == 0
                ? "ran without printing anything. Use print(…) to show values, or declare a View to render UI."
                : "exited without printing anything")
        }
        if run.truncated { parts.append("output truncated") }
        if run.exitStatus != 0 { parts.append("exit status \(run.exitStatus)") }
        return parts.isEmpty ? "finished" : parts.joined(separator: " · ")
    }

    private var rerunBadge: some View {
        FilterTag(label: "code changed — run again", icon: "arrow.clockwise", accent: theme.accent, isSelected: true) {
            run()
        }
        .padding(10)
    }

    private func run() {
        phase = .building
        builtCode = code
        generation += 1
        let thisRun = generation
        let entrySource = entry
        let helperSources = helpers
        Task {
            let next: Phase
            do {
                switch try await SwiftPreviewBuilder.shared.build(entry: entrySource, helpers: helperSources) {
                case .view(let makeView): next = .ready(makeView)
                case .console(let run): next = .console(run)
                }
            } catch SwiftPreviewBuilder.BuildError.toolchainUnavailable {
                next = .unavailable(SwiftPreviewBuilder.BuildError.toolchainUnavailable.localizedDescription)
            } catch {
                next = .failed(error.localizedDescription)
            }
            guard thisRun == generation else { return }
            phase = next
        }
    }
}

/// Hosts the NSView produced by the compiled snippet's factory.
private struct CompiledSwiftView: NSViewRepresentable {
    let makeView: @MainActor () -> NSView?

    func makeNSView(context: Context) -> NSView {
        makeView() ?? NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
