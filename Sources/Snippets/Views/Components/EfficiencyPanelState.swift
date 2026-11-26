#if !APP_STORE
import Foundation

/// What the efficiency panel shows, derived from plain values so the rules are
/// testable without SwiftUI: the running job, the rating of exactly this code,
/// the most recent rating of any code, and the active config's source rating.
struct EfficiencyPanelState: Equatable {
    enum Content: Equatable {
        case notRated
        case rating
        case rated(EfficiencyReview)
        case notApplicable(EfficiencyReview)
        /// The latest rating, for code that has since changed.
        case stale(EfficiencyReview)
    }

    /// The rating the active config was created from, when the active code has
    /// no rating of its own: its remaining suggestions are offered below.
    struct Inherited: Equatable {
        var review: EfficiencyReview
        var configName: String
    }

    var content: Content
    /// A failed run; the previous rating in `content` stays visible beside it.
    var failure: EfficiencyRatingError?
    var inherited: Inherited?

    static func derive(
        job: EfficiencyRatingCenter.Job.State?,
        fresh: EfficiencyReview?,
        latest: EfficiencyReview?,
        activeConfig: PreviewParamConfig?,
        reviews: [EfficiencyReview]
    ) -> EfficiencyPanelState {
        var failure: EfficiencyRatingError?
        switch job {
        case .running:
            return EfficiencyPanelState(content: .rating, failure: nil, inherited: nil)
        case .failed(let error): failure = error
        case .succeeded, nil: break
        }

        if let fresh {
            return EfficiencyPanelState(
                content: fresh.score == nil ? .notApplicable(fresh) : .rated(fresh),
                failure: failure, inherited: nil)
        }
        if let activeConfig, let sourceID = activeConfig.sourceReviewID,
           let source = reviews.first(where: { $0.id == sourceID }) {
            return EfficiencyPanelState(
                content: .notRated, failure: failure,
                inherited: Inherited(review: source, configName: activeConfig.name))
        }
        return EfficiencyPanelState(
            content: latest.map(Content.stale) ?? .notRated, failure: failure, inherited: nil)
    }

    /// Hidden for JSON/Unknown, with the feature off, with no agent CLI found,
    /// and while the preview fills the window.
    static func isVisible(
        language: SupportedLanguage, enabled: Bool, cliFound: Bool, previewExpanded: Bool
    ) -> Bool {
        switch language {
        case .json, .unknown: return false
        default: return enabled && cliFound && !previewExpanded
        }
    }

    /// One plain line per failure.
    static func failureLine(_ error: EfficiencyRatingError) -> String {
        switch error {
        case .agentNotFound: return "Agent not installed"
        case .notSignedIn: return "Not signed in to the agent"
        case .timedOut: return "Timed out"
        case .invalidResponse: return "Invalid response from the agent"
        case .cancelled: return "Cancelled"
        case .failed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            if first.isEmpty { return "Rating failed" }
            return first.count > 90 ? String(first.prefix(90)) + "…" : first
        }
    }

    /// A rating's suggestions the active code can still take (the "From the
    /// rating of …" list). Those whose `before` no longer matches are dropped.
    static func remainingSuggestions(
        of review: EfficiencyReview, in activeCode: String
    ) -> [EfficiencyReview.Suggestion] {
        review.suggestions.filter {
            EfficiencyReviewStore.matchState(of: $0, in: activeCode) == .applies
        }
    }

    enum SuggestionAction: Equatable {
        case offer(addToActive: Bool)
        case noLongerApplies
    }

    /// "Save as new config…" needs `before` to occur exactly once in the rated
    /// code; "Add to ‹active›" additionally needs the active config's approval.
    static func action(
        for suggestion: EfficiencyReview.Suggestion, in review: EfficiencyReview, canAddToActive: Bool
    ) -> SuggestionAction {
        EfficiencyReviewStore.matchState(of: suggestion, in: review.ratedCode) == .applies
            ? .offer(addToActive: canAddToActive) : .noLongerApplies
    }
}
#endif
