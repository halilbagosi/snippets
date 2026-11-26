import CryptoKit
import Foundation

/// Bumping this marks every stored rating stale.
enum EfficiencyRubric {
    static let version = 1
}

enum EfficiencyBand: Equatable {
    case excellent, good, fair, poor

    init(score: Int) {
        switch score {
        case 90...: self = .excellent
        case 75...: self = .good
        case 50...: self = .fair
        default: self = .poor
        }
    }

    var label: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Poor"
        }
    }
}

/// One agent-produced efficiency rating of a snippet's code.
struct EfficiencyReview: Codable, Equatable, Identifiable {
    enum Impact: String, Codable { case high, medium, low }

    struct Suggestion: Codable, Equatable, Identifiable {
        let id: UUID
        var title: String
        var impact: Impact
        var explanation: String
        var before: String
        var after: String
    }

    let id: UUID
    /// SHA-256 of `ratedCode`, lowercase hex.
    var codeHash: String
    var ratedCode: String
    var rubricVersion: Int
    /// Nil when the agent answered "not applicable".
    var score: Int?
    var notApplicableReason: String?
    var summary: String
    var suggestions: [Suggestion]
    /// `AgentClient.rawValue`.
    var agent: String
    var model: String?
    var date: Date
}

/// Pure rules over a snippet's rating list, free of SwiftData and SwiftUI.
enum EfficiencyReviewStore {
    enum MatchState: Equatable { case applies, noLongerApplies }

    static func hash(of code: String) -> String {
        SHA256.hash(data: Data(code.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The most recent rating of exactly this code under this rubric version.
    static func review(
        matching code: String, rubricVersion: Int, in reviews: [EfficiencyReview]
    ) -> EfficiencyReview? {
        let codeHash = hash(of: code)
        return reviews
            .filter { $0.codeHash == codeHash && $0.rubricVersion == rubricVersion }
            .max { $0.date < $1.date }
    }

    /// The most recent rating of any code — what the stale state shows.
    static func latest(in reviews: [EfficiencyReview]) -> EfficiencyReview? {
        reviews.max { $0.date < $1.date }
    }

    /// Stale when the rated code or the rubric changed; nothing else.
    static func isStale(_ review: EfficiencyReview, currentCode: String) -> Bool {
        review.codeHash != hash(of: currentCode)
            || review.rubricVersion != EfficiencyRubric.version
    }

    /// Keeps the most recent rating, any rating whose hash matches a config's
    /// code or the current code, and any rating a config names as its source.
    static func pruned(
        _ reviews: [EfficiencyReview],
        configs: [PreviewParamConfig],
        currentCode: String
    ) -> [EfficiencyReview] {
        var keptHashes: Set<String> = [hash(of: currentCode)]
        for code in configs.compactMap(\.code) { keptHashes.insert(hash(of: code)) }
        let sourceIDs = Set(configs.compactMap(\.sourceReviewID))
        let newestID = latest(in: reviews)?.id
        return reviews.filter {
            $0.id == newestID || keptHashes.contains($0.codeHash) || sourceIDs.contains($0.id)
        }
    }

    /// A suggestion applies only if its `before` occurs exactly once.
    static func matchState(of suggestion: EfficiencyReview.Suggestion, in code: String) -> MatchState {
        occurrenceRanges(of: suggestion.before, in: code).count == 1 ? .applies : .noLongerApplies
    }

    /// `code` with the single occurrence of `before` replaced by `after`;
    /// nil unless the suggestion applies.
    static func applying(_ suggestion: EfficiencyReview.Suggestion, to code: String) -> String? {
        let ranges = occurrenceRanges(of: suggestion.before, in: code)
        guard ranges.count == 1 else { return nil }
        var result = code
        result.replaceSubrange(ranges[0], with: suggestion.after)
        return result
    }

    /// Occurrences including overlapping ones, so ambiguity is never missed.
    private static func occurrenceRanges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var start = haystack.startIndex
        while start < haystack.endIndex,
              let range = haystack.range(of: needle, range: start..<haystack.endIndex) {
            ranges.append(range)
            start = haystack.index(after: range.lowerBound)
        }
        return ranges
    }
}
