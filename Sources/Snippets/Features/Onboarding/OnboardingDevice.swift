import CoreGraphics
import Foundation
import IOKit
import SwiftUI

/// The Mac the welcome tour is drawn on: a picture of the model it is running
/// on, with the tour's desktop showing through the screen.
///
/// Laptops and the iMac show themselves; a Mac without a screen of its own
/// shows a Studio Display. Each picture has a light finish for light mode and
/// a dark one for dark mode where the model comes in one (silver or starlight,
/// space black or midnight); the Neo and the iMac have one finish for both.
enum OnboardingDevice: String, CaseIterable, Sendable {
    /// The touch-screen MacBook Pro, from the M6 on.
    case macBookProOLED14 = "MacBookProOLED14"
    case macBookProOLED16 = "MacBookProOLED16"
    /// The notched MacBook Pro, 2021 to M5.
    case macBookPro14 = "MacBookPro14"
    case macBookPro16 = "MacBookPro16"
    case macBookAir13 = "MacBookAir13"
    case macBookAir15 = "MacBookAir15"
    case macBookNeo = "MacBookNeo"
    case iMac = "IMac"
    /// For a Mac mini, or any other Mac this doesn't know.
    case studioDisplay = "StudioDisplay"
    /// For a Mac Studio or a Mac Pro.
    case studioDisplayXDR = "StudioDisplayXDR"

    /// The Mac this is running on, read once.
    static let current = OnboardingDevice(
        productName: SystemModel.productName(),
        modelIdentifier: SystemModel.identifier()
    )

    /// Picks the picture for a Mac from the name About This Mac shows (e.g.
    /// "MacBook Pro (14-inch, M5, 2025)"), falling back to the model
    /// identifier (e.g. "MacBookPro16,1") where there is no name — Intel Macs
    /// have none. Matching the name by family and size keeps new chips
    /// working without a table to update.
    init(productName: String?, modelIdentifier: String?) {
        if let name = productName?.lowercased(), !name.isEmpty {
            self = Self.matching(name: name)
        } else if let identifier = modelIdentifier {
            self = Self.matching(identifier: identifier)
        } else {
            self = .macBookPro14
        }
    }

    private static func matching(name: String) -> OnboardingDevice {
        if name.contains("macbook neo") { return .macBookNeo }
        if name.contains("macbook air") {
            return name.contains("15-inch") ? .macBookAir15 : .macBookAir13
        }
        if name.contains("macbook pro") {
            let large = name.contains("16-inch")
            if let chip = chipGeneration(in: name), chip >= 6 {
                return large ? .macBookProOLED16 : .macBookProOLED14
            }
            return large ? .macBookPro16 : .macBookPro14
        }
        if name.contains("imac") { return .iMac }
        if name.contains("mac studio") || name.contains("mac pro") { return .studioDisplayXDR }
        if name.contains("macbook") { return .macBookPro14 }
        return .studioDisplay
    }

    private static func matching(identifier: String) -> OnboardingDevice {
        switch identifier {
        case "MacBookPro16,1", "MacBookPro16,4": return .macBookPro16
        case let id where id.hasPrefix("MacBookAir"): return .macBookAir13
        case let id where id.hasPrefix("MacBookPro"): return .macBookPro14
        case let id where id.hasPrefix("iMac"): return .iMac
        case let id where id.hasPrefix("MacPro"): return .studioDisplayXDR
        case let id where id.hasPrefix("Macmini"): return .studioDisplay
        default: return .macBookPro14
        }
    }

    /// The `5` in "M5 Pro"; nil for a name without an Apple chip in it.
    private static func chipGeneration(in name: String) -> Int? {
        guard let match = name.firstMatch(of: /\bm(\d+)\b/) else { return nil }
        return Int(match.1)
    }

    // MARK: Picture

    var imageName: String { "OnboardingDevice\(rawValue)" }

    /// The picture's size in the artwork's own pixels; the shipped image is
    /// a scaled copy of the same shape.
    var artworkSize: CGSize {
        switch self {
        case .macBookProOLED14: CGSize(width: 3664, height: 2245)
        case .macBookProOLED16: CGSize(width: 4189, height: 2537)
        case .macBookPro14: CGSize(width: 3806, height: 2296)
        case .macBookPro16: CGSize(width: 4220, height: 2577)
        case .macBookAir13: CGSize(width: 3205, height: 1941)
        case .macBookAir15: CGSize(width: 3514, height: 2134)
        case .macBookNeo: CGSize(width: 2991, height: 1824)
        case .iMac: CGSize(width: 4718, height: 3976)
        case .studioDisplay, .studioDisplayXDR: CGSize(width: 5357, height: 4115)
        }
    }

    /// Where the screen shows through, in the artwork's pixels. It is the
    /// panel's real resolution, rounded corners and notch included — the
    /// picture draws those over it.
    var artworkScreen: CGRect {
        switch self {
        case .macBookProOLED14: CGRect(x: 320, y: 46, width: 3024, height: 1986)
        case .macBookProOLED16: CGRect(x: 358, y: 46, width: 3472, height: 2266)
        case .macBookPro14: CGRect(x: 391, y: 55, width: 3024, height: 1964)
        case .macBookPro16: CGRect(x: 382, y: 56, width: 3456, height: 2234)
        case .macBookAir13: CGRect(x: 323, y: 61, width: 2560, height: 1664)
        case .macBookAir15: CGRect(x: 317, y: 59, width: 2880, height: 1864)
        case .macBookNeo: CGRect(x: 292, y: 81, width: 2408, height: 1506)
        case .iMac: CGRect(x: 119, y: 118, width: 4480, height: 2520)
        case .studioDisplay, .studioDisplayXDR: CGRect(x: 119, y: 118, width: 5120, height: 2880)
        }
    }

    /// The largest size of the picture that fits `box`.
    func fittedSize(in box: CGSize) -> CGSize {
        let scale = min(box.width / artworkSize.width, box.height / artworkSize.height)
        return CGSize(width: artworkSize.width * scale, height: artworkSize.height * scale)
    }

    /// The screen in the picture drawn at `size`, grown by `bleed` on every
    /// side so the desktop runs under the bezel's soft inner edge.
    func screenRect(in size: CGSize, bleed: CGFloat = 0) -> CGRect {
        let scale = size.width / artworkSize.width
        return CGRect(
            x: artworkScreen.minX * scale,
            y: artworkScreen.minY * scale,
            width: artworkScreen.width * scale,
            height: artworkScreen.height * scale
        ).insetBy(dx: -bleed, dy: -bleed)
    }
}

// MARK: - Screen layout

/// The tour's desktop on a screen of any shape.
///
/// The shots were captured on a 1512×982 screen. A screen of another shape
/// keeps that height (or that width, if it is narrower) and grows the other
/// side, filled with wallpaper. The window stays centred, and the status item
/// and its panels stay at the trailing end of the menu bar, as they would on
/// a real Mac with that screen.
struct OnboardingScreenLayout: Equatable {
    /// The screen the shots were captured on, in points.
    static let captured = CGSize(width: 1512, height: 982)

    /// The screen, in the captured screen's points.
    let size: CGSize

    init(aspectRatio: CGFloat) {
        let captured = Self.captured
        size = aspectRatio >= captured.width / captured.height
            ? CGSize(width: captured.height * aspectRatio, height: captured.height)
            : CGSize(width: captured.width, height: captured.width / aspectRatio)
    }

    enum Anchor {
        /// Moves with the centred window.
        case centre
        /// Keeps to the menu bar's trailing end.
        case trailing
    }

    /// Where a point placed on the captured screen lands on this one.
    func place(_ point: CGPoint, _ anchor: Anchor) -> CGPoint {
        let extra = CGSize(width: size.width - Self.captured.width, height: size.height - Self.captured.height)
        switch anchor {
        case .centre: return CGPoint(x: point.x + extra.width / 2, y: point.y + extra.height / 2)
        case .trailing: return CGPoint(x: point.x + extra.width, y: point.y)
        }
    }

    func place(_ rect: CGRect, _ anchor: Anchor) -> CGRect {
        CGRect(origin: place(rect.origin, anchor), size: rect.size)
    }
}

// MARK: - Framing

/// How the device is scaled for a page, and the point of it that holds still.
struct OnboardingFraming: Equatable {
    let scale: CGFloat
    let anchor: UnitPoint

    /// - Parameters:
    ///   - zoom: the page's zoom. On a screen focus it is the magnification
    ///     of a screen `tunedScreenWidth` wide, so a feature comes out the
    ///     same size on every Mac however much frame is around its screen.
    ///   - frameSize: the device picture as drawn at rest.
    ///   - screen: its screen within that, as the desktop is laid out in it.
    init(zoom: CGFloat, focus: OnboardingFocus, frameSize: CGSize, screen: CGRect, tunedScreenWidth: CGFloat) {
        let point: CGPoint
        let anchor: OnboardingScreenLayout.Anchor
        switch focus {
        case .device(let unit):
            scale = zoom
            self.anchor = unit
            return
        case .window(let p):
            point = p
            anchor = .centre
        case .menuBarExtra(let p):
            point = p
            anchor = .trailing
        }
        let layout = OnboardingScreenLayout(aspectRatio: screen.width / screen.height)
        let placed = layout.place(point, anchor)
        let pointsPerScreenPoint = screen.width / layout.size.width
        scale = zoom * tunedScreenWidth / screen.width
        self.anchor = UnitPoint(
            x: (screen.minX + placed.x * pointsPerScreenPoint) / frameSize.width,
            y: (screen.minY + placed.y * pointsPerScreenPoint) / frameSize.height
        )
    }
}

// MARK: - System model

/// What this Mac calls itself.
private enum SystemModel {
    /// The marketing name About This Mac shows, from the device tree. Apple
    /// silicon only.
    static func productName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data
        else { return nil }
        return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// The model identifier, e.g. "MacBookPro18,3".
    static func identifier() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
