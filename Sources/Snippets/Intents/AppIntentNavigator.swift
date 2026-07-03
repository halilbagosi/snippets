import Foundation
import Observation

/// One-way bridge from `OpenSnippetIntent` into the running UI. The intent sets
/// `pendingOpenSnippetUUID`; `ContentView` observes it, opens the snippet, and
/// clears it back to `nil`.
@MainActor
@Observable
final class AppIntentNavigator {
    static let shared = AppIntentNavigator()
    var pendingOpenSnippetUUID: UUID?
    private init() {}
}
