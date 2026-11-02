#if !APP_STORE
import SwiftUI

/// Snippets ▸ Check for Updates…, just below Settings…, where Mac apps keep it.
///
/// `CommandGroup(after: .appSettings)` lands *above* Settings… on macOS 26,
/// and replacing that group leaves the system's own Settings… item behind,
/// so the item is anchored to the group that follows it instead.
struct UpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(before: .systemServices) {
            Button("Check for Updates…") { UpdateController.shared.checkForUpdates() }
                .disabled(!UpdateController.shared.canCheckForUpdates)
            Divider()
        }
    }
}
#endif
