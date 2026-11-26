#if !APP_STORE
import SwiftUI
import SwiftData

/// The efficiency rating of a snippet, below its code. Rating is on demand;
/// applying a suggestion saves a new named config and never overwrites code.
struct EfficiencyPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snippet: Snippet
    let isPreviewExpanded: Bool
    let defersHeavyContent: Bool
    let accent: Color
    var center: EfficiencyRatingCenter = .shared
    let onSaveAsNew: (EfficiencyReview.Suggestion, EfficiencyReview, String, EfficiencyFixApplier.Base) -> Void
    let onAddToActive: (EfficiencyReview.Suggestion, EfficiencyReview) -> Void

    @State private var suggestionsOpen = false
    @State private var inheritedOpen = false
    @State private var namingID: UUID?
    @State private var showsConsent = false

    private var theme: Theme { Theme.current(colorScheme) }
    private var settings: EfficiencySettings { center.settings }
    private var activeConfig: PreviewParamConfig? {
        snippet.paramConfigs.first { $0.id == snippet.activeParamConfigID }
    }
    private var language: SupportedLanguage { SupportedLanguage(rawValue: snippet.language) ?? .unknown }

    var body: some View {
        // The CLI lookup is not started here: a hidden panel has no view, so a
        // `.task` on it would never run. See `refreshesEfficiencyCLI()`.
        Group {
            if EfficiencyPanelState.isVisible(
                language: language, enabled: settings.enabled,
                cliFound: settings.cliPath != nil, previewExpanded: isPreviewExpanded) {
                content
            }
        }
    }

    private var content: some View {
        let reviews = snippet.efficiencyReviews
        let id = snippet.persistentModelID
        let fresh = EfficiencyReviewStore.review(
            matching: snippet.code, rubricVersion: EfficiencyRubric.version, in: reviews)
        let state = EfficiencyPanelState.derive(
            job: center.jobs[id]?.state, fresh: fresh,
            latest: EfficiencyReviewStore.latest(in: reviews),
            activeConfig: activeConfig, reviews: reviews)

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("efficiency") { headerAction(state, id: id) }
            VStack(alignment: .leading, spacing: 10) {
                stateContent(for: state)
                if let failure = state.failure { failureRow(failure, id: id) }
                if let inherited = state.inherited { inheritedSection(inherited) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassWell(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sheet(isPresented: $showsConsent) {
            EfficiencyConsentSheet(
                agent: settings.agent,
                onContinue: {
                    showsConsent = false
                    center.grantConsent(for: settings.agent)
                    center.start(for: snippet)
                },
                onCancel: { showsConsent = false })
        }
    }

    // MARK: Header

    @ViewBuilder
    private func headerAction(_ state: EfficiencyPanelState, id: PersistentIdentifier) -> some View {
        switch state.content {
        case .rating:
            textButton("Cancel") { center.cancel(id) }
        case .notRated:
            textButton("Rate") { rate() }
        case .rated, .notApplicable, .stale:
            textButton("Re-rate") { rate() }
        }
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Mono.font(size: 11, weight: .semibold)).foregroundStyle(accent)
        }
        .buttonStyle(.plain)
    }

    /// Rate and Retry both go through consent: the agent may have changed.
    private func retry(_ id: PersistentIdentifier) {
        if center.needsConsent(for: settings.agent) { showsConsent = true } else { center.retry(id) }
    }

    private func rate() {
        if center.needsConsent(for: settings.agent) {
            showsConsent = true
        } else {
            center.start(for: snippet)
        }
    }

    // MARK: Content

    @ViewBuilder
    private func stateContent(for state: EfficiencyPanelState) -> some View {
        switch state.content {
        case .notRated:
            if state.inherited == nil {
                mutedLine("Not rated yet. The agent scores this snippet's efficiency and suggests fixes.")
            } else {
                mutedLine("This config has no rating of its own.")
            }
        case .rating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                mutedLine("Rating with \(settings.agent.name)…")
            }
        case .rated(let review):
            ratedHeader(review)
            suggestionsFold(review, context: .fresh, open: $suggestionsOpen)
            provenance(review)
        case .notApplicable(let review):
            notApplicableLine(review)
            provenance(review)
        case .stale(let review):
            VStack(alignment: .leading, spacing: 8) {
                if review.score == nil { notApplicableLine(review) } else { ratedHeader(review) }
                mutedLine("Code changed — Re-rate")
                suggestionsFold(review, context: .stale, open: $suggestionsOpen)
            }
            .opacity(0.55)
        }
    }

    private func notApplicableLine(_ review: EfficiencyReview) -> some View {
        Text(review.notApplicableReason ?? "Not applicable").font(Mono.font(size: 12))
            .foregroundStyle(theme.text)
    }

    private func ratedHeader(_ review: EfficiencyReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let score = review.score {
                let band = EfficiencyBand(score: score)
                Text("\(score) · \(band.label)")
                    .font(Mono.font(size: 12, weight: .bold))
                    .foregroundStyle(tint(for: band))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(tint(for: band).opacity(0.16)))
            }
            if !review.summary.isEmpty {
                Text(review.summary).font(Mono.font(size: 12)).foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tint(for band: EfficiencyBand) -> Color {
        switch band {
        case .excellent: theme.trafficGreen
        case .good: theme.accent
        case .fair: theme.trafficYellow
        case .poor: theme.trafficRed
        }
    }

    private func provenance(_ review: EfficiencyReview) -> some View {
        let agent = AgentClient(rawValue: review.agent)?.name ?? review.agent
        let model = review.model ?? "default model"
        return Text("\(agent) · \(model) — the score is the agent's assessment against a rubric, not a measurement.")
            .font(Mono.font(size: 10)).foregroundStyle(theme.textFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func mutedLine(_ text: String) -> some View {
        Text(text).font(Mono.font(size: 11)).foregroundStyle(theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func failureRow(_ error: EfficiencyRatingError, id: PersistentIdentifier) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(theme.trafficYellow)
            Text(EfficiencyPanelState.failureLine(error))
                .font(Mono.font(size: 11)).foregroundStyle(theme.textMuted)
                .lineLimit(2)
            Spacer(minLength: 8)
            textButton("Retry") { retry(id) }
        }
    }

    // MARK: Suggestions

    @ViewBuilder
    private func suggestionsFold(
        _ review: EfficiencyReview, context: EfficiencyPanelState.Context,
        open: Binding<Bool>
    ) -> some View {
        let suggestions = review.suggestions
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : DSToken.Motion.reveal) { open.wrappedValue.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                        Text("\(suggestions.count) suggestion\(suggestions.count == 1 ? "" : "s")")
                            .font(Mono.font(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
                if open.wrappedValue && !defersHeavyContent {
                    ForEach(suggestions) { suggestion in
                        suggestionRow(suggestion, in: review, context: context)
                    }
                }
            }
        }
    }

    private func suggestionRow(
        _ suggestion: EfficiencyReview.Suggestion, in review: EfficiencyReview,
        context: EfficiencyPanelState.Context
    ) -> some View {
        let canAdd = EfficiencyFixApplier.canAddToActive(snippet: snippet, review: review, suggestion: suggestion)
        let action = EfficiencyPanelState.action(
            for: suggestion, in: review, context: context, activeCode: snippet.code, canAddToActive: canAdd)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(suggestion.impact.rawValue)
                    .font(Mono.font(size: 9, weight: .bold)).textCase(.uppercase)
                    .foregroundStyle(impactColor(suggestion.impact))
                Text(suggestion.title).font(Mono.font(size: 12, weight: .semibold)).foregroundStyle(theme.text)
            }
            Text(suggestion.explanation).font(Mono.font(size: 11)).foregroundStyle(theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            codeBlock("before", suggestion.before)
            codeBlock("after", suggestion.after)
            actionRow(suggestion, review: review, context: context, action: action)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.inset.opacity(0.5)))
    }

    private func impactColor(_ impact: EfficiencyReview.Impact) -> Color {
        switch impact {
        case .high: theme.trafficRed
        case .medium: theme.trafficYellow
        case .low: theme.textMuted
        }
    }

    /// Read-only plain text: a fading AppKit code view would flash white.
    private func codeBlock(_ label: String, _ code: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Mono.font(size: 9, weight: .semibold)).foregroundStyle(theme.textFaint)
            Text(code)
                .font(Mono.font(size: 11)).foregroundStyle(theme.text)
                .lineLimit(12).textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.canvasDeep.opacity(0.5)))
        }
    }

    @ViewBuilder
    private func actionRow(
        _ suggestion: EfficiencyReview.Suggestion, review: EfficiencyReview,
        context: EfficiencyPanelState.Context, action: EfficiencyPanelState.SuggestionAction
    ) -> some View {
        switch action {
        case .applied:
            mutedLine("Applied")
        case .noLongerApplies:
            mutedLine("no longer applies — Re-rate")
        case .offer(let addToActive):
            if namingID == suggestion.id {
                ConfigNameField(
                    initialName: suggestion.title, accent: accent, theme: theme,
                    onSave: { name in
                        namingID = nil
                        onSaveAsNew(suggestion, review, name, EfficiencyPanelState.saveBase(for: context))
                    },
                    onCancel: { namingID = nil })
                .id(suggestion.id)
            } else {
                HStack(spacing: 14) {
                    textButton("Save as new config…") { namingID = suggestion.id }
                    if addToActive {
                        textButton("Add to \(activeConfig?.name ?? "active")") { onAddToActive(suggestion, review) }
                    }
                }
            }
        }
    }

    // MARK: From the rating of ‹config›

    private func inheritedSection(_ inherited: EfficiencyPanelState.Inherited) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From the rating of \(inherited.configName)")
                .font(Mono.font(size: 11, weight: .semibold)).foregroundStyle(theme.textMuted)
            suggestionsFold(inherited.review, context: .inherited, open: $inheritedOpen)
        }
    }
}

extension View {
    /// Locates the rating agent's CLI whenever a detail view appears or the
    /// agent changes (the locator caches). Lives on an always-present view:
    /// the panel itself is absent until the CLI is found.
    func refreshesEfficiencyCLI() -> some View {
        task(id: EfficiencyRatingCenter.shared.settings.agent) {
            await EfficiencyRatingCenter.shared.settings.refreshCLIPath()
        }
    }
}
#else
import SwiftUI

extension View {
    func refreshesEfficiencyCLI() -> some View { self }
}
#endif
