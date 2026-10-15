import SwiftUI

/// Shows the licence notices for the bundled preview runtimes
/// (`ThirdPartyNotices.txt`). Their MIT licences require the notice to ship
/// with every copy of the app.
struct ThirdPartyNoticesView: View {
    static let windowID = "third-party-notices"

    private let notices: String = {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Third-party notices are missing from this copy of Snippets."
        }
        return text
    }()

    var body: some View {
        ScrollView {
            Text(notices)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 360, idealHeight: 560)
    }
}
