import Foundation

/// Keyboard-navigation arithmetic for the quick-copy panel, kept separate from
/// the view model so the edge cases can be tested without a `ModelContext`.
enum QuickCopySelection {

    /// Move the highlight, clamped at both ends.
    ///
    /// Clamping rather than wrapping is deliberate: the list is a ranked set of
    /// results, so hitting the end is information ("nothing further down"),
    /// whereas silently jumping back to the top loses the user's place.
    static func moved(from index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + delta, 0), count - 1)
    }

    /// Pull an index back inside a list that has changed size underneath it.
    static func clamped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    enum EscapeOutcome: Equatable {
        case clearQuery
        case dismiss
    }

    /// Escape clears a typed query first and only dismisses once there is
    /// nothing to clear, so a mistyped search costs one key rather than a
    /// reopen. Whitespace counts as nothing to clear.
    static func escape(query: String) -> EscapeOutcome {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .dismiss : .clearQuery
    }
}
