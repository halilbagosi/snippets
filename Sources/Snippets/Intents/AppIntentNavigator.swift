import Foundation
import Observation

/// One-way bridge from the app's intents into the running UI. `OpenSnippetIntent`
/// sets `pendingOpenSnippetUUID`; `NewSnippetIntent` sets `pendingNewSnippet`.
/// `ContentView` observes both, acts, and clears them.
@MainActor
@Observable
final class AppIntentNavigator {
    static let shared = AppIntentNavigator()

    /// A snippet the UI should open, requested by `OpenSnippetIntent`.
    var pendingOpenSnippetUUID: UUID?

    /// Set by `NewSnippetIntent` to ask the UI to present the new-snippet editor.
    var pendingNewSnippet = false

    private init() {}
}
