#if !APP_STORE
import Foundation

/// What the rater is asked to judge: this snippet's code, plus its
/// dependencies' code as read-only context.
struct EfficiencyRequest: Sendable {
    var title: String
    var language: SupportedLanguage
    var code: String
    var dependencies: [(title: String, language: String, code: String)]
}

/// A validated agent answer. `suggestions` already satisfy the exactly-once
/// `before` rule against the rated code.
struct EfficiencyReport: Sendable, Equatable {
    /// Nil when the agent answered "not applicable".
    var score: Int?
    var notApplicableReason: String?
    var summary: String
    var suggestions: [EfficiencyReview.Suggestion]
}

enum EfficiencyRatingError: Error, Equatable {
    case agentNotFound, notSignedIn, timedOut, invalidResponse(String), cancelled, failed(String)
}

protocol EfficiencyRater: Sendable {
    func rate(_ request: EfficiencyRequest, model: String?) async throws -> EfficiencyReport
    /// `effort` is the agent's reasoning-effort level; raters whose CLI has
    /// no such setting ignore it.
    func rate(_ request: EfficiencyRequest, model: String?, effort: String?) async throws -> EfficiencyReport
}

extension EfficiencyRater {
    func rate(_ request: EfficiencyRequest, model: String?, effort: String?) async throws -> EfficiencyReport {
        try await rate(request, model: model)
    }
}
#endif
