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
    let onSaveAsNew: (EfficiencyReview.Suggestion, EfficiencyReview, String) -> Void
    let onAddToActive: (EfficiencyReview.Suggestion, EfficiencyReview) -> Void

    @State private var suggestionsOpen = false
    @State private var namingID: UUID?
    @State private var showsConsent = false

    private var theme: Theme { Theme.current(colorScheme) }
    private var settings: EfficiencySettings { center.settings }
    private var language: SupportedLanguage { SupportedLanguage(rawValue: snippet.language) ?? .unknown }

    var body: some View {
        // `Group` + `.task` stays out of the stack's spacing while hidden.
        Group {
            if EfficiencyPanelState.isVisible(
                language: language, enabled: settings.enabled,
                cliFound: settings.cliPath != nil, previewExpanded: isPreviewExpanded) {
                content
            }
        }
        .task(id: settings.agent) {
            if settings.cliPath == nil { await settings.refreshCLIPath() }
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
            activeConfig: snippet.paramConfigs.first { $0.id == snippet.activeParamConfigID },
            reviews: reviews)

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("efficiency") { headerAction(state, id: id) }
            VStack(alignment: .leading, spacing: 10) {
                body(for: state)
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

    private func rate() {
        if center.needsConsent(for: settings.agent) {
            showsConsent = true
        } else {
            center.start(for: snippet)
        }
    }

    // MARK: Content

    @ViewBuilder
    private func body(for state: EfficiencyPanelState) -> some View {
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
            suggestionsFold(review, review.suggestions)
            provenance(review)
        case .notApplicable(let review):
            Text(review.notApplicableReason ?? "Not applicable").font(Mono.font(size: 12))
                .foregroundStyle(theme.text)
            provenance(review)
        case .stale(let review):
            VStack(alignment: .leading, spacing: 8) {
                ratedHeader(review)
                mutedLine("Code changed — Re-rate")
            }
            .opacity(0.55)
        }
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
        case .good: .mint
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
            textButton("Retry") { center.retry(id) }
        }
    }

    // MARK: Suggestions

    @ViewBuilder
    private func suggestionsFold(
        _ review: EfficiencyReview, _ suggestions: [EfficiencyReview.Suggestion]
    ) -> some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(reduceMotion ? nil : DSToken.Motion.reveal) { suggestionsOpen.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(suggestionsOpen ? 90 : 0))
                        Text("\(suggestions.count) suggestion\(suggestions.count == 1 ? "" : "s")")
                            .font(Mono.font(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
                if suggestionsOpen && !defersHeavyContent {
                    ForEach(suggestions) { suggestion in suggestionRow(suggestion, in: review) }
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: EfficiencyReview.Suggestion, in review: EfficiencyReview) -> some View {
        let canAdd = EfficiencyFixApplier.canAddToActive(snippet: snippet, review: review, suggestion: suggestion)
        let action = EfficiencyPanelState.action(for: suggestion, in: review, canAddToActive: canAdd)
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
            actionRow(suggestion, review: review, action: action)
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
        action: EfficiencyPanelState.SuggestionAction
    ) -> some View {
        switch action {
        case .noLongerApplies:
            mutedLine("no longer applies — Re-rate")
        case .offer(let addToActive):
            if namingID == suggestion.id {
                ConfigNameField(
                    initialName: suggestion.title, accent: accent, theme: theme,
                    onSave: { name in
                        namingID = nil
                        onSaveAsNew(suggestion, review, name)
                    },
                    onCancel: { namingID = nil })
                .id(suggestion.id)
            } else {
                HStack(spacing: 14) {
                    textButton("Save as new config…") { namingID = suggestion.id }
                    if addToActive {
                        let name = snippet.paramConfigs.first { $0.id == snippet.activeParamConfigID }?.name ?? "active"
                        textButton("Add to \(name)") { onAddToActive(suggestion, review) }
                    }
                }
            }
        }
    }

    // MARK: From the rating of ‹config›

    @ViewBuilder
    private func inheritedSection(_ inherited: EfficiencyPanelState.Inherited) -> some View {
        let remaining = EfficiencyPanelState.remainingSuggestions(of: inherited.review, in: snippet.code)
        if !remaining.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("From the rating of \(inherited.configName)")
                    .font(Mono.font(size: 11, weight: .semibold)).foregroundStyle(theme.textMuted)
                if !defersHeavyContent {
                    ForEach(remaining) { suggestion in suggestionRow(suggestion, in: inherited.review) }
                }
            }
        }
    }
}
#endif
