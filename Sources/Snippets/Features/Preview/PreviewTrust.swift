import Foundation
import Observation
import SwiftUI

/// What the user has agreed to let snippet previews do.
///
/// Previewing a snippet *runs* it — JavaScript in a web view, a shader on the
/// GPU, native code for the Swift flavor. That is the point of the feature and
/// entirely safe for code you wrote yourself, which is where snippets come from
/// today. It stops being safe the moment a snippet arrives from somewhere else,
/// and the cheapest moment to decide is before that happens.
///
/// Two independent decisions live here:
///
/// - **Auto-run** — global, set once from the first-launch prompt and
///   changeable in Settings. Off means a preview waits behind a Run button
///   instead of executing on open.
/// - **CDN modules** — per snippet, never global. Granting one lets that
///   snippet pull npm packages from esm.sh, which is the only way a preview can
///   reach the network at all (see `WebPreviewHTMLBuilder.Policy`). It stays
///   granular because it is the one capability that leaves the machine.
@MainActor
@Observable
final class PreviewTrust {
    private enum Key {
        static let autoRun = "settings.preview.autoRun"
        static let hasPrompted = "settings.preview.hasPromptedForPolicy"
        static let cdnGrants = "settings.preview.cdnGrants"
    }

    /// When true, web and Metal previews run as soon as a snippet is opened.
    /// When false they wait for an explicit Run, like the Swift flavor always
    /// has. Defaults to false: the safe answer is the one that applies before
    /// the user has told us anything.
    var autoRunPreviews: Bool {
        didSet { UserDefaults.standard.set(autoRunPreviews, forKey: Key.autoRun) }
    }

    /// Whether the first-launch explanation has been shown. Persisted so the
    /// prompt is genuinely once-per-install, not once-per-launch.
    var hasPromptedForPolicy: Bool {
        didSet { UserDefaults.standard.set(hasPromptedForPolicy, forKey: Key.hasPrompted) }
    }

    /// Snippets allowed to load npm modules from esm.sh, by `Snippet.uuid`.
    private var cdnGrants: Set<UUID> {
        didSet {
            UserDefaults.standard.set(
                cdnGrants.map(\.uuidString), forKey: Key.cdnGrants
            )
        }
    }

    /// Snippets the user has run this launch while auto-run is off. Kept in
    /// memory only: approving a run is a decision about *this* look at the
    /// snippet, and it should not silently become permanent.
    private var sessionApproved: Set<UUID> = []

    init() {
        let defaults = UserDefaults.standard
        self.autoRunPreviews = defaults.bool(forKey: Key.autoRun)
        self.hasPromptedForPolicy = defaults.bool(forKey: Key.hasPrompted)
        self.cdnGrants = Set(
            (defaults.stringArray(forKey: Key.cdnGrants) ?? []).compactMap(UUID.init(uuidString:))
        )
    }

    // MARK: - Running

    /// Whether the preview for `snippetID` may execute right now.
    func mayRun(_ snippetID: UUID?) -> Bool {
        if autoRunPreviews { return true }
        guard let snippetID else { return false }
        return sessionApproved.contains(snippetID)
    }

    /// Records an explicit Run for this launch.
    func approveRun(_ snippetID: UUID?) {
        guard let snippetID else { return }
        sessionApproved.insert(snippetID)
    }

    // MARK: - CDN modules

    func allowsCDNModules(_ snippetID: UUID?) -> Bool {
        guard let snippetID else { return false }
        return cdnGrants.contains(snippetID)
    }

    func setCDNModulesAllowed(_ allowed: Bool, for snippetID: UUID?) {
        guard let snippetID else { return }
        if allowed {
            cdnGrants.insert(snippetID)
        } else {
            cdnGrants.remove(snippetID)
        }
    }

    /// Drops a deleted snippet's grant so a later snippet reusing the id (or a
    /// restored one) does not inherit approval nobody gave it.
    func forget(_ snippetID: UUID?) {
        guard let snippetID else { return }
        cdnGrants.remove(snippetID)
        sessionApproved.remove(snippetID)
    }

    /// The policy the preview builder should render `snippetID` under.
    func policy(for snippetID: UUID?) -> WebPreviewHTMLBuilder.Policy {
        WebPreviewHTMLBuilder.Policy(allowsCDNModules: allowsCDNModules(snippetID))
    }
}

/// One-time explanation of what previewing does, shown on first launch.
///
/// It asks rather than informs: the choice it offers *is* the setting, so the
/// user starts with a policy they picked instead of one they have to discover.
private struct PreviewTrustPrompt: ViewModifier {
    @Environment(PreviewTrust.self) private var trust

    /// Real state, deliberately.
    ///
    /// Presentation has to be something SwiftUI owns and can write back to. A
    /// `.constant` binding never raises the alert at all (dismissal works by
    /// writing `false`, so a binding that cannot be written is one SwiftUI
    /// declines to present), and a binding computed from the trust object gets
    /// spurious `set(false)` calls during body evaluation that mark the prompt
    /// answered before the user has seen it. `@State` seeded once from `.task`
    /// avoids both.
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task {
                // Seeded once per launch, after the view is in the window —
                // presenting during the first layout pass is what the alert
                // machinery mishandles.
                if !trust.hasPromptedForPolicy { isPresented = true }
            }
            .alert("Previews run snippet code", isPresented: $isPresented) {
                // Which button is *default* is a security decision, so it is
                // stated outright rather than left to declaration order —
                // that ordering heuristic put the highlight on "Run
                // automatically" whichever way round these were listed.
                // Return must not be able to grant the broader capability.
                Button("Ask before running") {
                    trust.autoRunPreviews = false
                    trust.hasPromptedForPolicy = true
                }
                .keyboardShortcut(.defaultAction)
                Button("Run automatically") {
                    trust.autoRunPreviews = true
                    trust.hasPromptedForPolicy = true
                }
            } message: {
                Text("""
                Opening a snippet with a live preview runs it: web snippets \
                execute in a locked-down web view that cannot reach the \
                network, and shaders run on the GPU. That is exactly what you \
                want for code you wrote yourself.

                If you paste code from elsewhere, having Snippets ask first \
                means nothing runs until you say so. Swift previews always \
                ask, either way.

                You can change this any time in Settings → Preferences.
                """)
            }
    }
}

extension View {
    /// Presents the first-launch preview-execution choice. Attach once, at the
    /// app's root.
    func previewTrustPrompt() -> some View {
        modifier(PreviewTrustPrompt())
    }
}
