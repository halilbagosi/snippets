import SwiftUI

/// Shows the licence notices for the bundled preview runtimes
/// (`ThirdPartyNotices.txt`). Their MIT licences require the notice to ship
/// with every copy of the app.
struct ThirdPartyNoticesView: View {
    static let windowID = "third-party-notices"

    var body: some View {
        BundledTextView(
            resource: "ThirdPartyNotices", withExtension: "txt",
            missingMessage: "Third-party notices are missing from this copy of Snippets."
        )
    }
}

/// Shows Snippets' end user licence agreement (`EULA.txt`). The app is
/// closed source, so this is the licence users get it under.
struct LicenseAgreementView: View {
    static let windowID = "license-agreement"

    var body: some View {
        BundledTextView(
            resource: "EULA", withExtension: "txt",
            missingMessage: "The licence agreement is missing from this copy of Snippets."
        )
    }
}

/// A scrollable, selectable monospaced view of a plain-text bundle resource.
private struct BundledTextView: View {
    private let text: String

    init(resource: String, withExtension ext: String?, missingMessage: String) {
        if let url = Bundle.main.url(forResource: resource, withExtension: ext),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            text = contents
        } else {
            text = missingMessage
        }
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 360, idealHeight: 560)
    }
}
