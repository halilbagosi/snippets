import SwiftUI

/// The one back button in the app.
///
/// Both back affordances — the gallery's, which sits next to the search bar
/// when a collection is open, and the detail view's, which returns to the
/// snippet you came from after following a connection — render through this
/// view so they stay identical.
struct BackButton: View {
    let action: () -> Void
    var accessibilityLabel: String
    /// Namespace of the enclosing `GlassEffectContainer`, when there is one.
    /// Supplying it makes the container morph the button's glass in as a single
    /// member instead of resolving its material a frame behind the rim.
    var glassNamespace: Namespace.ID? = nil

    @Environment(\.colorScheme) private var colorScheme
    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 32, height: 32)
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous),
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private static let glassID = "BackButton"
}
