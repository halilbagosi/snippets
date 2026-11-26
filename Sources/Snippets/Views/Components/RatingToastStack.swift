#if !APP_STORE
import SwiftUI
import SwiftData

/// The toasts for efficiency ratings that run (or just ran) with their detail
/// view closed: one row per job, in the bottom toast stack of the gallery
/// column, just above the app's other toasts. Which rows appear, and their words, come from `RatingToastModel`.
struct RatingToastStack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The snippet whose detail card is open; its panel already shows the run.
    let presentedSnippetID: PersistentIdentifier?
    /// Snippets in Trash: their failed rows offer no Retry.
    var trashedIDs: Set<PersistentIdentifier> = []
    /// Opens the snippet in the gallery (the same path a card click takes).
    let onOpen: (PersistentIdentifier) -> Void
    /// Collapsed: the rows give way to a small pill in the same spot.
    @Binding var isCollapsed: Bool
    var center: EfficiencyRatingCenter = .shared

    var body: some View {
        let model = RatingToastModel(jobs: center.jobs, hiding: presentedSnippetID, trashed: trashedIDs)
        VStack(spacing: 8) {
            if isCollapsed {
                // In the toasts' own spot, so collapsing reads as the rows
                // shrinking into it and expanding as them growing back out.
                if !model.isEmpty {
                    RatingToastPill(model: model) { isCollapsed = false }
                        .transition(collapseTransition)
                }
            } else if !model.rows.isEmpty {
                VStack(alignment: .trailing, spacing: 8) {
                    collapseButton
                    ForEach(model.rows) { row in
                        RatingToastRow(
                            row: row,
                            onOpen: { onOpen(row.id) },
                            onCancel: { center.cancel(row.id) },
                            onRetry: { retry(row.id) },
                            onDismiss: { center.dismiss(row.id) }
                        )
                        .transition(rowTransition)
                    }
                    if let more = model.overflowText {
                        Text(more)
                            .foregroundStyle(.secondary)
                            .toastPill()
                            .transition(rowTransition)
                    }
                }
                .transition(collapseTransition)
            }
        }
        // Scoped to the stack: an ambient `withAnimation` would reach the gallery.
        .animation(DSToken.Motion.toastIn, value: model)
        .animation(DSToken.Motion.toastIn, value: isCollapsed)
    }

    /// Rows and pill swap around their shared bottom edge.
    private var collapseTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity)
    }

    private var collapseButton: some View {
        Button { isCollapsed = true } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
                .liquidGlassSurface(
                    in: Circle(), interactive: true,
                    borderOpacity: 0, shadowRadius: 0, shadowY: 0, drawsFills: false
                )
        }
        .buttonStyle(GlassPressButtonStyle())
        .help("Collapse rating toasts")
        .accessibilityLabel("Collapse rating toasts")
    }

    /// Rows rise from the bottom and leave by fading, like the app's other
    /// toasts; Reduce Motion fades both.
    private var rowTransition: AnyTransition {
        let out = AnyTransition.opacity.animation(DSToken.Motion.toastOut)
        guard !reduceMotion else { return .asymmetric(insertion: .opacity, removal: out) }
        return .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: out)
    }

    /// Retry needs the same consent as Rate. The sheet lives on the panel, so
    /// when consent is missing (the agent changed since the run) the snippet
    /// opens instead; its panel then shows the failure with Retry, and that
    /// Retry goes through consent.
    private func retry(_ id: PersistentIdentifier) {
        if center.needsConsent(for: center.settings.agent) {
            onOpen(id)
        } else {
            center.retry(id)
        }
    }
}

/// The collapsed rating toasts: a small pill in the toasts' spot. While a run
/// is going it shows the agent's mark pulsing; clicking it brings the full
/// toasts back.
private struct RatingToastPill: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: RatingToastModel
    let onExpand: () -> Void

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 7) {
                mark
                Text(model.miniText)
                    .foregroundStyle(theme.text)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .toastPill()
        }
        .buttonStyle(GlassPressButtonStyle())
        .help("Show rating toasts")
        .accessibilityLabel("Show rating toasts, \(model.miniText)")
    }

    @ViewBuilder
    private var mark: some View {
        if let agent = model.runningAgent {
            AgentMark(agent: agent, isPulsing: true)
        } else if model.failedCount > 0 {
            ToastIcon(systemName: "exclamationmark.circle.fill", color: .red)
        } else {
            ToastIcon(systemName: "checkmark.circle.fill", color: theme.accent)
        }
    }
}

private struct RatingToastRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let row: RatingToastModel.Row
    let onOpen: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        HStack(spacing: 10) {
            AgentMark(agent: row.agent, isPulsing: row.kind == .running)
            // Never truncated: the row hugs its text, and only when the
            // column is too narrow does the text wrap instead.
            Text(row.text)
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if row.kind == .failed, row.canRetry {
                ToastActionButton(title: "Retry", accent: theme.accent, action: onRetry)
            }
            // A running row's ✕ stops the run; a finished one's dismisses it.
            if row.kind == .running {
                ToastCloseButton(accessibilityLabel: "Stop rating", action: onCancel)
                    .help("Stop rating")
            } else {
                ToastCloseButton(accessibilityLabel: "Dismiss", action: onDismiss)
            }
        }
        .toastPill()
        .onTapGesture(perform: onOpen)
    }
}

/// A rating toast's leading mark: the agent's logo in its colour, pulsing
/// while the run is going (`ratingPulse` repeats forever).
private struct AgentMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let agent: AgentClient
    let isPulsing: Bool

    @State private var pulsing = false

    private var dimmed: Bool { isPulsing && !reduceMotion && !pulsing }

    var body: some View {
        agent.logo
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: ToastPillModifier.iconSize, height: ToastPillModifier.iconSize)
            .foregroundStyle(agent.color)
            .frame(width: ToastPillModifier.iconSize + 2, height: ToastPillModifier.iconSize + 2)
            .opacity(dimmed ? 0.85 : 1)
            .scaleEffect(dimmed ? 0.94 : 1)
            // A finished run settles on a plain curve: re-animating with
            // the repeating one would keep it pulsing forever.
            .animation(isPulsing ? DSToken.Motion.ratingPulse : DSToken.Motion.toggle, value: pulsing)
            .onAppear { if isPulsing, !reduceMotion { pulsing = true } }
            .onChange(of: isPulsing) { _, running in pulsing = running && !reduceMotion }
    }
}
#endif
