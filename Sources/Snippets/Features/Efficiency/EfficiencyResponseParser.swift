#if !APP_STORE
import Foundation

/// Validates the agent's report object (the JSON matching
/// `EfficiencyPrompt.schema`), independent of how the CLI wraps it.
enum EfficiencyResponseParser {
    static let maxSummary = 200, maxSuggestions = 8
    static let maxTitle = 80, maxExplanation = 600

    static func parse(_ text: String, ratedCode: String) throws -> EfficiencyReport {
        try parse(Data(text.utf8), ratedCode: ratedCode)
    }

    static func parse(_ data: Data, ratedCode: String) throws -> EfficiencyReport {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw invalid("not a JSON object")
        }
        guard let applicable = root["applicable"] as? Bool else { throw invalid("applicable missing") }
        guard let summary = root["summary"] as? String else { throw invalid("summary missing") }
        guard summary.count <= maxSummary else { throw invalid("summary too long") }

        if !applicable {
            guard let reason = (root["notApplicableReason"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty
            else { throw invalid("notApplicableReason missing") }
            guard root["score"] == nil || root["score"] is NSNull else {
                throw invalid("score present for not-applicable")
            }
            return EfficiencyReport(score: nil, notApplicableReason: reason, summary: summary, suggestions: [])
        }

        guard let number = root["score"] as? NSNumber, number !== kCFBooleanTrue, number !== kCFBooleanFalse,
              number.doubleValue == Double(number.intValue), (0...100).contains(number.intValue)
        else { throw invalid("score missing or out of range") }

        let raw = root["suggestions"] ?? []
        guard let items = raw as? [Any] else { throw invalid("suggestions not an array") }
        guard items.count <= maxSuggestions else { throw invalid("too many suggestions") }

        var suggestions: [EfficiencyReview.Suggestion] = []
        for item in items {
            guard let dict = item as? [String: Any] else { throw invalid("suggestion not an object") }
            guard let title = dict["title"] as? String, !title.isEmpty, title.count <= maxTitle,
                  let impactRaw = dict["impact"] as? String,
                  let impact = EfficiencyReview.Impact(rawValue: impactRaw),
                  let explanation = dict["explanation"] as? String, explanation.count <= maxExplanation,
                  let before = dict["before"] as? String,
                  let after = dict["after"] as? String
            else { throw invalid("suggestion malformed") }
            let suggestion = EfficiencyReview.Suggestion(
                id: UUID(), title: title, impact: impact, explanation: explanation,
                before: before, after: after
            )
            // One unusable fix must not sink the whole rating.
            guard before != after,
                  EfficiencyReviewStore.matchState(of: suggestion, in: ratedCode) == .applies
            else { continue }
            suggestions.append(suggestion)
        }
        return EfficiencyReport(score: number.intValue, notApplicableReason: nil, summary: summary, suggestions: suggestions)
    }

    private static func invalid(_ why: String) -> EfficiencyRatingError { .invalidResponse(why) }
}
#endif
