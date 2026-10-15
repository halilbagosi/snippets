import SwiftUI

/// The one back button in the app.
///
/// Both back affordances — the gallery's, which sits next to the search bar
/// when a collection is open, and the detail view's, which returns to the
/// snippet you came from after following a connection — render through this
/// view, so the glyph, weight and glass treatment stay in one place. Only the
/// silhouette differs, and each caller states which one it wants: see ``Style``
/// for why they are not the same.
struct BackButton: View {
    /// The button's silhouette, which is set by what it sits beside.
    enum Style {
        /// Rounded square, 32pt. The gallery's row is a run of rectangles —
        /// the search bar and the filter tags, all on an 7–8pt radius — and a
        /// lone circle at the head of that row reads as a different kind of
        /// control rather than the first item in it.
        case square
        /// Circle, 30pt. In the detail view the back button and the close
        /// button sit in opposite top corners at once with nothing between
        /// them, so they read as a pair; the close button is a 30pt circle,
        /// and any difference in shape or size shows as a mismatch.
        case circle
    }

    let action: () -> Void
    var accessibilityLabel: String
    let style: Style
    /// Namespace of the enclosing `GlassEffectContainer`, when there is one.
    /// Supplying it makes the container morph the button's glass in as a single
    /// member instead of resolving its material a frame behind the rim.
    var glassNamespace: Namespace.ID? = nil

    @Environment(\.colorScheme) private var colorScheme
    private var theme: Theme { Theme.current(colorScheme) }

    private var side: CGFloat {
        switch style {
        case .square: 32
        case .circle: 30
        }
    }

    /// Type-erased so the two silhouettes can share one view body — the glass
    /// surface is generic over `Shape`, so a plain ternary between a
    /// `RoundedRectangle` and a `Circle` would not typecheck.
    private var silhouette: AnyShape {
        switch style {
        case .square: AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .circle: AnyShape(Circle())
        }
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: side, height: side)
                .liquidGlassSurface(
                    in: silhouette,
                    interactive: true,
                    borderOpacity: colorScheme == .dark ? 0.18 : 0.36,
                    shadowRadius: 5,
                    shadowY: 2,
                    glassID: glassNamespace.map { _ in Self.glassID },
                    glassNamespace: glassNamespace
                )
                // No .compositingGroup(): flattening the button into its own
                // offscreen layer rasterises the rim and shadow at once while
                // the material still has to come from the container's glass
                // pass, so the frame arrives before the texture.
                .contentShape(silhouette)
        }
        .buttonStyle(.plain)
        .contentShape(silhouette)
        .accessibilityLabel(accessibilityLabel)
    }

    private static let glassID = "BackButton"
}
