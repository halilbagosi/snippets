import Foundation

/// What fills the quick-copy panel before the user types anything.
///
/// Case order is the on-screen order of the segmented control and defines the
/// ⌘1–⌘4 shortcuts, so reordering these cases reorders the UI.
enum QuickCopyScope: String, CaseIterable, Identifiable {
    case favorites
    case frequent
    case recent
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .frequent: "Frequent"
        case .recent: "Recent"
        case .all: "All"
        }
    }

    var symbolName: String {
        switch self {
        case .favorites: "star"
        case .frequent: "flame"
        case .recent: "clock"
        case .all: "square.grid.2x2"
        }
    }

    /// 1-based position, used for the ⌘1–⌘4 shortcut.
    var shortcutIndex: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    static func scope(forShortcutIndex index: Int) -> QuickCopyScope? {
        guard index >= 1, index <= allCases.count else { return nil }
        return allCases[index - 1]
    }
}
