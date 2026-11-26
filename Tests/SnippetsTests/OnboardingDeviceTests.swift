import AppKit
import SwiftUI
import XCTest
@testable import Snippets

/// Which Mac the welcome tour draws, and how its desktop and zoom fit that
/// Mac's screen.
final class OnboardingDeviceTests: XCTestCase {

    // MARK: Model from the product name

    func test_productName_picksFamilyAndSize() {
        let cases: [(String, OnboardingDevice)] = [
            ("MacBook Pro (14-inch, 2021)", .macBookPro14),
            ("MacBook Pro (16-inch, 2021)", .macBookPro16),
            ("MacBook Pro (14-inch, M3, Nov 2023)", .macBookPro14),
            ("MacBook Pro (16-inch, M5 Max, 2026)", .macBookPro16),
            ("MacBook Pro (13-inch, M2, 2022)", .macBookPro14),
            ("MacBook Air (M1, 2020)", .macBookAir13),
            ("MacBook Air (13-inch, M4, 2025)", .macBookAir13),
            ("MacBook Air (15-inch, M3, 2024)", .macBookAir15),
            ("MacBook Neo (13-inch, A18 Pro, 2026)", .macBookNeo),
            ("iMac (24-inch, M4, 2024)", .iMac),
            ("Mac mini (2024)", .studioDisplay),
            ("Mac Studio (2025)", .studioDisplayXDR),
            ("Mac Pro (2023)", .studioDisplayXDR),
            ("Some Future Mac", .studioDisplay),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(OnboardingDevice(productName: name, modelIdentifier: nil), expected, name)
        }
    }

    func test_macBookProFromM6On_isTheTouchModel() {
        XCTAssertEqual(OnboardingDevice(productName: "MacBook Pro (14-inch, M6, 2026)", modelIdentifier: nil), .macBookProOLED14)
        XCTAssertEqual(OnboardingDevice(productName: "MacBook Pro (16-inch, M6 Max, 2026)", modelIdentifier: nil), .macBookProOLED16)
        XCTAssertEqual(OnboardingDevice(productName: "MacBook Pro (14-inch, M12 Pro, 2032)", modelIdentifier: nil), .macBookProOLED14)
    }

    func test_productName_winsOverIdentifier() {
        XCTAssertEqual(OnboardingDevice(productName: "MacBook Air (15-inch, M2, 2023)", modelIdentifier: "Mac14,15"), .macBookAir15)
    }

    // MARK: Model from the identifier

    func test_identifier_isTheFallbackWithoutAName() {
        let cases: [(String, OnboardingDevice)] = [
            ("MacBookPro16,1", .macBookPro16),
            ("MacBookPro16,4", .macBookPro16),
            ("MacBookPro16,2", .macBookPro14),
            ("MacBookAir10,1", .macBookAir13),
            ("iMac20,1", .iMac),
            ("MacPro7,1", .studioDisplayXDR),
            ("Macmini9,1", .studioDisplay),
            ("Mac99,9", .macBookPro14),
        ]
        for (identifier, expected) in cases {
            XCTAssertEqual(OnboardingDevice(productName: nil, modelIdentifier: identifier), expected, identifier)
            XCTAssertEqual(OnboardingDevice(productName: "", modelIdentifier: identifier), expected, identifier)
        }
    }

    func test_nothingKnown_fallsBackToTheMacBookPro() {
        XCTAssertEqual(OnboardingDevice(productName: nil, modelIdentifier: nil), .macBookPro14)
    }

    // MARK: Pictures

    @MainActor
    func test_everyDevice_hasAPictureOfTheMeasuredShape() throws {
        for device in OnboardingDevice.allCases {
            let image = try XCTUnwrap(NSImage(named: device.imageName), device.imageName)
            let shipped = image.size.width / image.size.height
            let measured = device.artworkSize.width / device.artworkSize.height
            XCTAssertEqual(shipped, measured, accuracy: 0.005, device.imageName)
        }
    }

    func test_everyScreen_liesInsideItsPicture() {
        for device in OnboardingDevice.allCases {
            let bounds = CGRect(origin: .zero, size: device.artworkSize)
            XCTAssertTrue(bounds.contains(device.artworkScreen), device.rawValue)
        }
    }

    func test_fittedSize_keepsShapeAndStaysInTheBox() {
        let box = CGSize(width: 530, height: 324)
        for device in OnboardingDevice.allCases {
            let size = device.fittedSize(in: box)
            XCTAssertLessThanOrEqual(size.width, box.width + 0.001, device.rawValue)
            XCTAssertLessThanOrEqual(size.height, box.height + 0.001, device.rawValue)
            XCTAssertTrue(abs(size.width - box.width) < 0.001 || abs(size.height - box.height) < 0.001, device.rawValue)
            XCTAssertEqual(size.width / size.height, device.artworkSize.width / device.artworkSize.height, accuracy: 0.0001)
        }
    }

    // MARK: Screen layout

    func test_capturedShape_layoutIsTheCapturedScreen() {
        let layout = OnboardingScreenLayout(aspectRatio: 1512 / 982)
        XCTAssertEqual(layout.size.width, 1512, accuracy: 0.001)
        XCTAssertEqual(layout.size.height, 982, accuracy: 0.001)
        XCTAssertEqual(layout.place(CGPoint(x: 100, y: 200), .centre), CGPoint(x: 100, y: 200))
        XCTAssertEqual(layout.place(CGPoint(x: 100, y: 200), .trailing), CGPoint(x: 100, y: 200))
    }

    func test_widerScreen_centresTheWindowAndKeepsExtrasTrailing() {
        let layout = OnboardingScreenLayout(aspectRatio: 16 / 9)
        XCTAssertEqual(layout.size.height, 982, accuracy: 0.001)
        let extra = layout.size.width - 1512
        XCTAssertGreaterThan(extra, 200)

        let window = layout.place(CGPoint(x: 148, y: 105), .centre)
        XCTAssertEqual(window.x, 148 + extra / 2, accuracy: 0.001)
        XCTAssertEqual(window.y, 105, accuracy: 0.001)

        let panel = layout.place(CGPoint(x: 1047, y: 37), .trailing)
        XCTAssertEqual(layout.size.width - panel.x, 1512 - 1047, accuracy: 0.001, "Same distance from the trailing edge")
        XCTAssertEqual(panel.y, 37, accuracy: 0.001)
    }

    func test_tallerScreen_centresTheWindowVertically() {
        let layout = OnboardingScreenLayout(aspectRatio: 3024 / 1986)
        XCTAssertEqual(layout.size.width, 1512, accuracy: 0.001)
        let extra = layout.size.height - 982
        XCTAssertGreaterThan(extra, 0)
        XCTAssertEqual(layout.place(CGPoint(x: 148, y: 105), .centre).y, 105 + extra / 2, accuracy: 0.001)
        XCTAssertEqual(layout.place(CGPoint(x: 1047, y: 37), .trailing).y, 37, accuracy: 0.001, "The menu bar stays at the top")
    }

    // MARK: Framing

    func test_deviceFocus_scalesTheDeviceAboutItsOwnPoint() {
        let framing = OnboardingFraming(
            zoom: 0.7,
            focus: .device(.top),
            frameSize: CGSize(width: 530, height: 320),
            screen: CGRect(x: 50, y: 10, width: 420, height: 273),
            tunedScreenWidth: 462.7
        )
        XCTAssertEqual(framing.scale, 0.7)
        XCTAssertEqual(framing.anchor, .top)
    }

    func test_screenFocus_magnifiesToTheTunedScreenSize() {
        for device in OnboardingDevice.allCases {
            let size = device.fittedSize(in: CGSize(width: 530, height: 324))
            let screen = device.screenRect(in: size)
            let framing = OnboardingFraming(
                zoom: 2,
                focus: .window(CGPoint(x: 756, y: 491)),
                frameSize: size,
                screen: screen,
                tunedScreenWidth: 462.7
            )
            XCTAssertEqual(screen.width * framing.scale, 2 * 462.7, accuracy: 0.001, device.rawValue)
        }
    }

    func test_screenFocus_anchorsOnThatPointOfTheScreen() {
        let size = CGSize(width: 1000, height: 800)
        // A screen of the captured shape at half scale, inset in the frame.
        let screen = CGRect(x: 100, y: 50, width: 756, height: 491)
        let framing = OnboardingFraming(
            zoom: 2,
            focus: .window(CGPoint(x: 1512, y: 982)),
            frameSize: size,
            screen: screen,
            tunedScreenWidth: 756
        )
        XCTAssertEqual(framing.anchor.x, (100 + 756) / 1000, accuracy: 0.0001)
        XCTAssertEqual(framing.anchor.y, (50 + 491) / 800, accuracy: 0.0001)
    }

    func test_menuBarFocus_followsTheTrailingEdgeOnAWideScreen() throws {
        let device = OnboardingDevice.studioDisplay
        let size = device.fittedSize(in: CGSize(width: 530, height: 324))
        let screen = device.screenRect(in: size)
        let point = CGPoint(x: 1383, y: 21)
        let framing = OnboardingFraming(zoom: 2, focus: .menuBarExtra(point), frameSize: size, screen: screen, tunedScreenWidth: 462.7)

        let layout = OnboardingScreenLayout(aspectRatio: screen.width / screen.height)
        let pointsPerScreenPoint = screen.width / layout.size.width
        let fromTrailingEdge = (screen.maxX - framing.anchor.x * size.width) / pointsPerScreenPoint
        XCTAssertEqual(fromTrailingEdge, 1512 - point.x, accuracy: 0.01)
    }
}
