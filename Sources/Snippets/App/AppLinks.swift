import Foundation

/// Public pages the app links to from the Help menu. The same URLs go into
/// App Store Connect (Privacy Policy URL, Support URL), so keep them stable —
/// changing one here means changing it there too.
enum AppLinks {
    static let privacyPolicy = URL(string: "https://snippets.halilbagosi.com/privacy/")!
    static let support = URL(string: "https://snippets.halilbagosi.com/support/")!

    static let feedbackAddress = "snippets.feedback@halilbagosi.com"

    /// A new email to the feedback address in the user's mail app, its
    /// subject naming the version so reports can be matched to a build.
    static func feedbackEmail(
        version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    ) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackAddress
        components.queryItems = [URLQueryItem(name: "subject", value: "Snippets Feedback (version \(version))")]
        return components.url!
    }
}
