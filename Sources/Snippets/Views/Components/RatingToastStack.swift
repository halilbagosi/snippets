#if !APP_STORE
import SwiftUI
import SwiftData

/// The toasts for efficiency ratings that run (or just ran) with their detail
/// view closed: one row per job, stacked downward from the top of the gallery
/// column. Which rows appear, and their words, come from `RatingToastModel`.
struct RatingToastStack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The snippet whose detail card is open; its panel already shows the run.
    let presentedSnippetID: PersistentIdentifier?
    /// Snippets in Trash: their failed rows offer no Retry.
    var trashedIDs: Set<PersistentIdentifier> = []
    /// Opens the snippet in the gallery (the same path a card click takes).
    let onOpen: (PersistentIdentifier) -> Void
    var center: EfficiencyRatingCenter = .shared

    var body: some View {
        let model = RatingToastModel(jobs: center.jobs, hiding: presentedSnippetID, trashed: trashedIDs)
        VStack(spacing: 8) {
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
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .liquidGlassSurface(in: Capsule())
                    .transition(rowTransition)
            }
        }
        // Scoped to the stack: an ambient `withAnimation` would reach the gallery.
        .animation(DSToken.Motion.toastIn, value: model)
        .padding(.top, 12)
        .padding(.horizontal, 16)
    }

    /// Rows come down from the top and leave by fading; Reduce Motion fades both.
    private var rowTransition: AnyTransition {
        let out = AnyTransition.opacity.animation(DSToken.Motion.toastOut)
        guard !reduceMotion else { return .asymmetric(insertion: .opacity, removal: out) }
        return .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: out)
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

private struct RatingToastRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let row: RatingToastModel.Row
    let onOpen: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        HStack(spacing: 12) {
            Text(row.text)
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            switch row.kind {
            case .running:
                StopMark(agent: row.agent, action: onCancel)
            case .succeeded:
                EmptyView()
            case .failed:
                if row.canRetry {
                    Button("Retry", action: onRetry)
                        .bold()
                        .foregroundStyle(theme.accent)
                        .buttonStyle(.plain)
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 380)
        .fixedSize(horizontal: false, vertical: true)
        .liquidGlassSurface(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onOpen)
    }
}

/// The running row's trailing mark: the agent's logo, pulsing in its colour.
/// Hovering cross-fades it to an ✕ in the same frame; clicking stops the run.
private struct StopMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let agent: AgentClient
    let action: () -> Void

    @State private var hovering = false
    @State private var pulsing = false

    var body: some View {
        Button(action: action) {
            ZStack {
                agent.logo
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(agent.color)
                    .opacity(reduceMotion || pulsing ? 1 : 0.85)
                    .scaleEffect(reduceMotion || pulsing ? 1 : 0.94)
                    .animation(DSToken.Motion.ratingPulse, value: pulsing)
                    .opacity(hovering ? 0 : 1)
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: 20, height: 20)
            .animation(DSToken.Motion.hover, value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onAppear { if !reduceMotion { pulsing = true } }
        .accessibilityLabel("Stop rating")
    }
}
#endif
