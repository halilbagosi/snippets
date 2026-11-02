#if !APP_STORE
import SwiftUI

/// Snippets ▸ Check for Updates…, under About, where Mac apps keep it.
struct UpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { UpdateController.shared.checkForUpdates() }
                .disabled(!UpdateController.shared.canCheckForUpdates)
        }
    }
}
#endif
