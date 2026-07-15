import SwiftUI

/// Live preview for Swift/SwiftUI snippets. Compilation is explicit (Run):
/// it takes seconds and executes the snippet in-process, so it never starts
/// on its own.
struct SwiftPreviewHostView: View {
    let entry: String
    let helpers: [String]
    let theme: Theme

    @State private var phase: Phase = .idle
    @State private var builtCode: String? = nil

    /// Combined-source key: a helper edit invalidates the build like an
    /// entry edit does.
    private var code: String { (helpers + [entry]).joined(separator: "\u{0}") }

    private enum Phase {
        case idle
        case building
        case ready(@MainActor () -> NSView?)
        case failed(String)
    }

    private var codeChangedSinceBuild: Bool {
        if case .idle = phase { return false }
        return builtCode != nil && builtCode != code
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch phase {
            case .idle:
                if SwiftToolchain.isAvailable {
                    runPrompt
                } else {
                    PreviewUnavailableView(
                        message: "Swift previews need the Xcode toolchain. Install Xcode, then relaunch Snippets.",
                        theme: theme
                    )
                }
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
            case .failed(let diagnostics):
                ScrollView {
                    Text(diagnostics)
                        .font(Mono.font(size: 11))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DSToken.Spacing.md)
                }
            }

            if codeChangedSinceBuild {
                rerunBadge
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.accent)
            Text("Compiles and runs this snippet inside Snippets.")
                .font(Mono.font(size: 11))
                .foregroundStyle(theme.textMuted)
            FilterTag(label: "run", icon: "play.fill", accent: theme.accent, isSelected: true) {
                run()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let entrySource = entry
        let helperSources = helpers
        Task {
            do {
                let makeView = try await SwiftPreviewBuilder.shared.build(entry: entrySource, helpers: helperSources)
                phase = .ready(makeView)
            } catch {
                phase = .failed(error.localizedDescription)
            }
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
