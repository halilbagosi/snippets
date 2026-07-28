import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

/// The quick-copy panel: search, scope picker, results, footer.
///
/// Deliberately not animated on query changes — results re-rank on every
/// keystroke, and animating that reflow reads as lag on the one interaction
/// that most needs to feel instant. The highlight animates; the rows do not.
struct QuickCopyPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @Namespace private var selectionNamespace

    @Bindable var model: QuickCopyViewModel

    /// Where the panel grows from, in its own unit space. The controller
    /// computes it from the status item's position so the panel visibly hangs
    /// off the thing that was clicked rather than blooming from its own middle.
    let scaleAnchor: UnitPoint

    let onDismiss: () -> Void
    /// Passed the snippet to reveal, or nil for a plain "open the app".
    let onOpenMainWindow: (Snippet?) -> Void
    let onQuit: () -> Void

    @State private var hasEntered = false

    /// Non-nil while a copy confirmation is on screen.
    @State private var confirmingID: PersistentIdentifier?

    static let panelWidth: CGFloat = 340
    static let panelHeight: CGFloat = 420

    var body: some View {
        VStack(spacing: 0) {
            searchField
            scopePicker
            Divider().opacity(0.5)
            results
            Divider().opacity(0.5)
            footer
        }
        .frame(width: Self.panelWidth, height: Self.panelHeight)
        .liquidGlassSurface(in: RoundedRectangle(cornerRadius: DSToken.Radius.md, style: .continuous))
        // Reduced motion keeps the opacity change and drops the scale, which is
        // the vestibular part.
        .scaleEffect(hasEntered || reduceMotion ? 1 : 0.96, anchor: scaleAnchor)
        .opacity(hasEntered ? 1 : 0)
        .onAppear {
            model.reload()
            searchFocused = true
            withAnimation(reduceMotion ? DSToken.Motion.popoverOut : DSToken.Motion.popover) {
                hasEntered = true
            }
        }
        .onKeyPress(.upArrow) { model.move(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.move(by: 1); return .handled }
        .onKeyPress(.escape) {
            if model.handleEscape() == .dismiss { onDismiss() }
            return .handled
        }
        .onKeyPress(.return) { handleReturn() }
    }

    // MARK: Regions

    private var searchField: some View {
        HStack(spacing: DSToken.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search snippets", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
        }
        .padding(.horizontal, DSToken.Spacing.sm)
        .padding(.vertical, DSToken.Spacing.xs)
    }

    private var scopePicker: some View {
        HStack(spacing: DSToken.Spacing.xxs) {
            ForEach(QuickCopyScope.allCases) { scope in
                Button {
                    model.scope = scope
                } label: {
                    HStack(spacing: DSToken.Spacing.xxs) {
                        Image(systemName: scope.symbolName).font(.system(size: 9))
                        Text(scope.title).font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, DSToken.Spacing.xs)
                    .padding(.vertical, DSToken.Spacing.xxs)
                    .background {
                        if model.scope == scope {
                            Capsule()
                                .fill(Color.primary.opacity(0.12))
                                // Sliding indicator, not a cross-fade.
                                .matchedGeometryEffect(id: "quickCopyScope", in: selectionNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(
                    KeyEquivalent(Character("\(scope.shortcutIndex)")),
                    modifiers: .command
                )
                .accessibilityLabel(Text(scope.title))
            }
            Spacer()
        }
        .padding(.horizontal, DSToken.Spacing.sm)
        .padding(.bottom, DSToken.Spacing.xs)
        .animation(reduceMotion ? nil : DSToken.Motion.selection, value: model.scope)
    }

    @ViewBuilder
    private var results: some View {
        if model.flatResults.isEmpty {
            VStack(spacing: DSToken.Spacing.xs) {
                Spacer()
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(model.sections.enumerated()), id: \.offset) { _, section in
                            if let heading = section.title {
                                Text(heading.uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, DSToken.Spacing.sm)
                                    .padding(.top, DSToken.Spacing.xs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(section.items, id: \.persistentModelID) { snippet in
                                QuickCopyRow(
                                    snippet: snippet,
                                    isSelected: model.selectedSnippet === snippet,
                                    isConfirming: confirmingID == snippet.persistentModelID,
                                    namespace: selectionNamespace
                                )
                                .id(snippet.persistentModelID)
                                .onTapGesture {
                                    model.select(snippet)
                                    _ = handleReturn()
                                }
                            }
                        }
                        .padding(.vertical, DSToken.Spacing.xxs)
                    }
                }
                .animation(reduceMotion ? nil : DSToken.Motion.selection, value: model.selectedIndex)
                .onChange(of: model.selectedIndex) { _, _ in
                    guard let id = model.selectedSnippet?.persistentModelID else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DSToken.Spacing.md) {
            Button("Open Snippets") { onOpenMainWindow(nil) }
                .buttonStyle(.plain)
            Spacer()
            Button("Quit Snippets") { onQuit() }
                .buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, DSToken.Spacing.sm)
        .padding(.vertical, DSToken.Spacing.xs)
    }

    private var emptyMessage: String {
        if !model.query.isEmpty { return "No matches" }
        switch model.scope {
        case .favorites: return "No favorites yet"
        case .frequent: return "Nothing copied yet"
        case .recent, .all: return "No snippets yet"
        }
    }

    // MARK: Actions

    /// ⏎ copies; ⌘⏎ reveals in the main window instead.
    private func handleReturn() -> KeyPress.Result {
        guard let selected = model.selectedSnippet else { return .handled }

        #if canImport(AppKit)
        let wantsReveal = NSEvent.modifierFlags.contains(.command)
        #else
        let wantsReveal = false
        #endif

        if wantsReveal {
            onOpenMainWindow(selected)
            onDismiss()
            return .handled
        }

        guard let copied = model.copySelected() else { return .handled }
        confirmingID = copied.persistentModelID

        // Feedback is visible before the surface leaves, then the panel goes.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            confirmingID = nil
            onDismiss()
        }
        return .handled
    }
}
