// Renders the DMG window background (background.png, background@2x.png)
// with the onboarding tour's wallpaper, so the installer looks like the app.
//
//   swift scripts/dmg/render-background.swift
//
// The layout constants must match scripts/dmg/settings.py: Finder places
// the icons there, and this draws the wells and arrow around those spots.

import AppKit
import SwiftUI

enum Layout {
    static let window = CGSize(width: 640, height: 400)
    static let iconSize: CGFloat = 144
    static let app = CGPoint(x: 172, y: 206)
    static let applications = CGPoint(x: 468, y: 206)
    static let well = CGSize(width: 184, height: 222)
    /// Finder draws the icon's name about this far below its centre.
    static let wellOffset: CGFloat = 14
}

/// Same mesh as `Wallpaper` in OnboardingView.swift.
struct Wallpaper: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.55], [0.6, 0.45], [1, 0.6],
                [0, 1], [0.45, 1], [1, 1],
            ],
            colors: [
                Color(red: 0.12, green: 0.08, blue: 0.55), Color(red: 0.30, green: 0.14, blue: 0.80), Color(red: 0.16, green: 0.22, blue: 0.85),
                Color(red: 0.32, green: 0.24, blue: 0.92), Color(red: 0.52, green: 0.62, blue: 0.98), Color(red: 0.22, green: 0.30, blue: 0.86),
                Color(red: 0.10, green: 0.10, blue: 0.48), Color(red: 0.36, green: 0.40, blue: 0.92), Color(red: 0.14, green: 0.12, blue: 0.58),
            ]
        )
    }
}

/// A glass well behind an icon and its name. Finder colours the name for
/// the system appearance (black in light mode, white in dark), so the well
/// is a mid-tone both read on, not a translucent veil over the mesh.
struct Well: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color(red: 0.42, green: 0.45, blue: 0.86).opacity(0.86))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.12)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color(red: 0.05, green: 0.03, blue: 0.30).opacity(0.35), radius: 18, y: 10)
            .frame(width: Layout.well.width, height: Layout.well.height)
    }
}

/// A shallow arc from the app's well to the Applications well.
struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX, y: rect.midY + 6)
        let end = CGPoint(x: rect.maxX, y: rect.midY + 6)
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(x: rect.midX, y: rect.midY - 26))
        // Head, aligned with the curve's direction at `end`.
        let angle = atan2(end.y - (rect.midY - 26), end.x - rect.midX)
        for side in [-1.0, 1.0] {
            let a = angle + .pi + side * .pi / 5
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x + 13 * cos(a), y: end.y + 13 * sin(a)))
        }
        return path
    }
}

struct Background: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper()

            Text("Drag Snippets into Applications")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                .frame(width: Layout.window.width)
                .position(x: Layout.window.width / 2, y: 54)

            ForEach([Layout.app, Layout.applications], id: \.x) { center in
                Well().position(x: center.x, y: center.y + Layout.wellOffset)
            }

            let gap = (Layout.applications.x - Layout.app.x) - Layout.well.width
            Arrow()
                .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .frame(width: gap - 28, height: 40)
                .position(x: (Layout.app.x + Layout.applications.x) / 2, y: Layout.app.y - 4)

            Text("// snippets for macOS")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: Layout.window.width)
                .position(x: Layout.window.width / 2, y: Layout.window.height - 30)
        }
        .frame(width: Layout.window.width, height: Layout.window.height)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
func render(scale: CGFloat, to url: URL) throws {
    let renderer = ImageRenderer(content: Background())
    renderer.scale = scale
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = Layout.window  // 72 dpi at 1x, 144 at 2x: Finder reads this
    guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
try MainActor.assumeIsolated {
    try render(scale: 1, to: dir.appendingPathComponent("background.png"))
    try render(scale: 2, to: dir.appendingPathComponent("background@2x.png"))
}
print("wrote background.png, background@2x.png in \(dir.path)")
