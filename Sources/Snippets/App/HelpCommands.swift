import SwiftUI

/// The Help menu: where macOS users look for support, the privacy policy and
/// licence notices. An empty Help menu leaves none of them discoverable.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link("Snippets Support", destination: AppLinks.support)
            Link("Privacy Policy", destination: AppLinks.privacyPolicy)
            Divider()
            Button("Third-Party Notices") {
                openWindow(id: ThirdPartyNoticesView.windowID)
            }
        }
    }
}
