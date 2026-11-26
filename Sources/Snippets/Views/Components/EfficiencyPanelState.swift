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

    enum SuggestionAction: Equatable {
        /// The change is already in the active code.
        case applied
        /// "Save as new config…", plus "Add to ‹active›" when allowed.
        case offer(addToActive: Bool)
        case noLongerApplies
    }

    /// Where a suggestion is listed, which decides the code it is checked against.
    enum Context: Equatable {
        /// Rating of exactly the current code.
        case fresh
        /// Rating of code that has since changed; changes go onto the current code.
        case stale
        /// "From the rating of ‹config›": the active config came from this rating.
        case inherited
    }

    /// The code "Save as new config…" builds from for this context.
    static func saveBase(for context: Context) -> EfficiencyFixApplier.Base {
        context == .stale ? .currentCode : .ratedCode
    }

    static func action(
        for suggestion: EfficiencyReview.Suggestion, in review: EfficiencyReview,
        context: Context, activeCode: String, canAddToActive: Bool
    ) -> SuggestionAction {
        func applies(_ code: String) -> Bool {
            EfficiencyReviewStore.matchState(of: suggestion, in: code) == .applies
        }
        switch context {
        case .fresh:
            return applies(review.ratedCode) ? .offer(addToActive: canAddToActive) : .noLongerApplies
        case .stale:
            return applies(activeCode) ? .offer(addToActive: false) : .noLongerApplies
        case .inherited:
            if !activeCode.contains(suggestion.before) {
                if !suggestion.after.isEmpty, activeCode.contains(suggestion.after) { return .applied }
                // A deletion leaves nothing to find: it is applied once `before`
                // (which the rating saw exactly once) is gone from the active code.
                if suggestion.after.isEmpty, review.ratedCode.components(separatedBy: suggestion.before).count == 2 {
                    return .applied
                }
            }
            if applies(activeCode) { return .offer(addToActive: canAddToActive) }
            return applies(review.ratedCode) ? .offer(addToActive: false) : .noLongerApplies
        }
    }
}
#endif
