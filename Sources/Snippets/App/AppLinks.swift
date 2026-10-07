import Foundation

/// Public pages the app links to from the Help menu. The same URLs go into
/// App Store Connect (Privacy Policy URL, Support URL), so keep them stable —
/// changing one here means changing it there too.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://halilbagosi.github.io/snippets/privacy/")!
    static let support = URL(string: "https://halilbagosi.github.io/snippets/support/")!
}
