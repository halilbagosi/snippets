import Foundation
import Observation
import SwiftUI

/// Whether the welcome tour is showing, and whether it has ever been seen.
///
/// Presentation is driven from `.task` rather than seeded in `init`: raising a
/// sheet during the window's first layout pass is the same thing the
/// preview-trust alert found SwiftUI mishandles.
@MainActor
@Observable
final class Onboarding {
    static let completedDefaultsKey = "onboarding.hasCompleted"

    /// True once the tour has been closed, by any route — finishing, skipping
    /// or Escape. Persisted, so the tour shows once per install.
    private(set) var hasCompleted: Bool

    var isPresented = false

    @ObservationIgnored private let defaults: UserDefaults

    /// `defaults` is injectable so tests do not mark the real app's tour seen.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompleted = defaults.bool(forKey: Self.completedDefaultsKey)
    }

    /// First launch.
    func presentIfNeeded() {
        if !hasCompleted { isPresented = true }
    }

    /// Help ▸ Welcome to Snippets.
    func present() {
        isPresented = true
    }

    /// Called once the sheet has gone, so anything waiting on the tour (the
    /// preview-trust prompt) presents into a window that has no sheet.
    func complete() {
        isPresented = false
        guard !hasCompleted else { return }
        hasCompleted = true
        defaults.set(true, forKey: Self.completedDefaultsKey)
    }
}

/// Page arithmetic for the tour's back and continue buttons and page dots.
struct OnboardingPager: Equatable {
    let pageCount: Int
    private(set) var index = 0

    init(pageCount: Int) {
        precondition(pageCount > 0)
        self.pageCount = pageCount
    }

    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == pageCount - 1 }

    /// Returns false on the last page, where Continue becomes Get Started.
    @discardableResult
    mutating func advance() -> Bool {
        guard !isLast else { return false }
        index += 1
        return true
    }

    @discardableResult
    mutating func goBack() -> Bool {
        guard !isFirst else { return false }
        index -= 1
        return true
    }

    /// The page dots. Returns false for the current page or one out of range.
    @discardableResult
    mutating func go(to page: Int) -> Bool {
        guard (0..<pageCount).contains(page), page != index else { return false }
        index = page
        return true
    }
}

/// A looping screen recording laid over a window shot, so a feature that
/// moves is shown moving.
///
/// Recorded from the same window the shot was taken of, just after it, so it
/// lines up with the still underneath — which stays in place as the poster
/// before the first frame decodes, and as the whole picture under Reduce
/// Motion. Each recording ends where it began and dissolves its last second
/// into its first, so the loop has no seam.
struct OnboardingClip: Sendable {
    /// Bundled as `<name>-light.<fileExtension>` and `<name>-dark.…`.
    let name: String
    /// `mov` for a whole-window recording, whose alpha carries the window's
    /// rounded corners; `mp4` for a rectangle inside it.
    let fileExtension: String
    /// Where the recording sits in the window, in the shot's points.
    var frame = CGRect(x: 0, y: 0, width: 1216, height: 772)

    func url(for colorScheme: ColorScheme) -> URL? {
        let variant = colorScheme == .dark ? "dark" : "light"
        return Bundle.main.url(forResource: "\(name)-\(variant)", withExtension: fileExtension)
    }
}

/// One stop on the tour: copy, and a shot of the app on a Mac screen that the
/// device zooms toward.
///
/// Screenshots are real captures of the app running a demo library, placed
/// on a drawn desktop at the size and position they were captured at (in
/// points on a 1512×982 screen), so the window stays put while the zoom
/// moves around it.
struct OnboardingPage: Identifiable, Sendable {
    let id: String
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    /// The main window, floating on the wallpaper.
    let windowImage: String
    /// A recording of the part of the window that moves, played over the
    /// still.
    var windowClip: OnboardingClip? = nil
    /// A menu bar panel over the window, hanging from the status item.
    let panelImage: String?
    /// How far the device is magnified…
    let zoom: CGFloat
    /// …and the point of the device (frame included) that stays put while it
    /// is. Picking the feature's own position keeps it in view.
    let focus: UnitPoint
    /// Settings the page lets you change on the spot, drawn between the Mac
    /// and the copy. Pages with controls shrink the Mac to make room.
    var controls: Controls? = nil

    enum Controls: Sendable {
        /// Agent access over MCP, with the setup to copy into an agent; an
        /// agent session is drawn over the window. Not in App Store builds.
        case agents
        /// Colour scheme and accent colour, applied as they are picked.
        case appearance
    }

    static let all: [OnboardingPage] = {
        var pages = features
        #if !APP_STORE
        pages.append(agents)
        #endif
        pages.append(appearance)
        return pages
    }()

    #if !APP_STORE
    static let agents = OnboardingPage(
        id: "agents",
        title: "Bring Your Agents",
        subtitle: "Claude Code, Codex, Cursor and any MCP client\ncan find and use your snippets.",
        windowImage: "OnboardingGallery",
        panelImage: nil,
        zoom: 0.7,
        focus: .top,
        controls: .agents
    )
    #endif

    static let appearance = OnboardingPage(
        id: "appearance",
        title: "Make It Yours",
        subtitle: "Pick a look and an accent colour.\nBoth are in Settings whenever you change your mind.",
        // Stands in for the default accent; the page shows the shot for the
        // accent you pick. See ``accentWindowImage(forHex:)``.
        windowImage: "OnboardingAccentBlue",
        panelImage: nil,
        zoom: 0.7,
        focus: .top,
        controls: .appearance
    )

    /// The gallery shot for an accent on the appearance page. Each preset
    /// accent has its own capture, `OnboardingAccent<Name>`, taken with the
    /// gallery's drifting gradient held still so only the accent differs
    /// between them; a custom colour gets the nearest preset's.
    @MainActor
    static func accentWindowImage(forHex hex: String) -> String {
        let presets = AppearanceView.presetColors
        let name: String
        if let rgb = rgb(hex) {
            name = presets.min { a, b in
                distance(rgb, Self.rgb(a.hex)) < distance(rgb, Self.rgb(b.hex))
            }?.name ?? presets[0].name
        } else {
            name = presets[0].name
        }
        return "OnboardingAccent\(name)"
    }

    /// `#RRGGBB` as 0–1 components; nil when it isn't one.
    private static func rgb(_ hex: String) -> SIMD3<Double>? {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return SIMD3(
            Double((value >> 16) & 0xFF),
            Double((value >> 8) & 0xFF),
            Double(value & 0xFF)
        ) / 255
    }

    private static func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>?) -> Double {
        guard let b else { return .infinity }
        let d = a - b
        return (d * d).sum()
    }

    private static let features: [OnboardingPage] = [
        OnboardingPage(
            id: "welcome",
            title: "Welcome to Snippets",
            subtitle: "Your code library, redesigned around\nLiquid Glass.",
            windowImage: "OnboardingGallery",
            panelImage: nil,
            zoom: 1,
            focus: .center
        ),
        OnboardingPage(
            id: "organize",
            title: "Organize Everything",
            subtitle: "Nest collections, pin favorites and filter\nby language in a click.",
            windowImage: "OnboardingCollections",
            windowClip: OnboardingClip(name: "OnboardingOrganize", fileExtension: "mov"),
            panelImage: nil,
            zoom: 1.9,
            focus: UnitPoint(x: 0.12, y: 0.18)
        ),
        OnboardingPage(
            id: "previews",
            title: "Live Previews",
            subtitle: "HTML, React, shaders and Swift run right\ninside the snippet.",
            windowImage: "OnboardingPreview",
            windowClip: OnboardingClip(
                name: "OnboardingPreview",
                fileExtension: "mp4",
                frame: CGRect(x: 340.5, y: 369, width: 775, height: 240)
            ),
            panelImage: nil,
            zoom: 1.55,
            focus: UnitPoint(x: 0.59, y: 0.59)
        ),
        // The same snippet as "previews", scrolled down to its parameters, so
        // the page turn reads as one preview opening up its controls.
        OnboardingPage(
            id: "parameters",
            title: "Tweak It Live",
            subtitle: "Drag a parameter and the preview follows.\nSave the look you like as a config.",
            windowImage: "OnboardingParameters",
            windowClip: OnboardingClip(
                name: "OnboardingParameters",
                fileExtension: "mp4",
                frame: CGRect(x: 325, y: 108, width: 810, height: 572)
            ),
            panelImage: nil,
            zoom: 1.5,
            focus: UnitPoint(x: 0.74, y: 0.57)
        ),
        OnboardingPage(
            id: "quick-copy",
            title: "Copy from the Menu Bar",
            subtitle: "Grab any snippet without leaving the app\nyou're working in.",
            windowImage: "OnboardingGallery",
            panelImage: "OnboardingQuickCopy",
            zoom: 2.1,
            focus: UnitPoint(x: 0.86, y: 0.04)
        ),
        OnboardingPage(
            id: "capture",
            title: "Save What You Copy",
            subtitle: "Copy code anywhere and Snippets offers\nto keep it for you.",
            windowImage: "OnboardingGallery",
            panelImage: "OnboardingCapture",
            zoom: 2.6,
            focus: UnitPoint(x: 0.86, y: 0.04)
        ),
    ]
}
