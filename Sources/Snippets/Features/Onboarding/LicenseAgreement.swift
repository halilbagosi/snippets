import Foundation
import Observation

/// Whether the user has agreed to the license (`EULA.txt`), and whether the
/// agreement is on screen asking them to.
///
/// Snippets ships outside the App Store, so no store accepts its terms on the
/// user's behalf: the app asks once, on first launch, before the welcome tour.
/// Agreeing records which terms were accepted; disagreeing quits.
@MainActor
@Observable
final class LicenseAgreement {
    /// Bump when the terms change in substance, to ask everyone again.
    /// Wording or link fixes don't need a new version.
    static let currentVersion = 1
    static let acceptedVersionDefaultsKey = "license.acceptedVersion"

    /// The agreement's text, as bundled.
    static let text: String = {
        guard let url = Bundle.main.url(forResource: "EULA", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The licence agreement is missing from this copy of Snippets."
        }
        return text
    }()

    /// The text reflowed for a view that wraps it itself. `EULA.txt` is
    /// hard-wrapped at ~77 columns for plain-text readers; in a narrower
    /// view those breaks land mid-line, so each paragraph and list item is
    /// joined back into one line.
    static let displayText: String = reflowed(text)

    static func reflowed(_ text: String) -> String {
        var lines: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // A list item ("  a. copy, …") starts a line of its own; its
            // continuation lines are indented further and join it.
            let startsItem = raw.hasPrefix("  ") && !raw.hasPrefix("   ")
            if line.isEmpty {
                lines.append("")
            } else if let last = lines.last, !last.isEmpty, !startsItem {
                lines[lines.count - 1] = last + " " + line
            } else {
                lines.append(startsItem ? "    " + line : line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// True once the current terms have been accepted. Persisted.
    private(set) var isAccepted: Bool

    var isPresented = false

    @ObservationIgnored private let defaults: UserDefaults

    /// `defaults` is injectable so tests do not accept the real app's terms.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isAccepted = Self.isAccepted(in: defaults)
    }

    /// For code that runs before any view, such as installing the menu bar
    /// item at launch.
    static func isAccepted(in defaults: UserDefaults) -> Bool {
        defaults.integer(forKey: acceptedVersionDefaultsKey) >= currentVersion
    }

    var needsAnswer: Bool { !isAccepted }

    /// First launch, or the first launch after the terms changed.
    func presentIfNeeded() {
        if needsAnswer { isPresented = true }
    }

    func accept() {
        defaults.set(Self.currentVersion, forKey: Self.acceptedVersionDefaultsKey)
        isAccepted = true
        isPresented = false
    }
}
