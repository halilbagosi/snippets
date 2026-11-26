#if !APP_STORE
import Foundation
import SwiftData

/// What the rating toast stack shows: pure derivation from the center's jobs,
/// so which rows appear, in what order and with which words is testable
/// without a view.
struct RatingToastModel: Equatable {
    struct Row: Identifiable, Equatable {
        enum Kind: Equatable { case running, succeeded, failed }
        let id: PersistentIdentifier
        let kind: Kind
        let text: String
        let agent: AgentClient
        /// False for a snippet in Trash: a rerun would rate something the user deleted.
        var canRetry = true
    }

    static let visibleLimit = 3

    let rows: [Row]
    /// Jobs past the limit, collapsed into one "+N more" row.
    let overflow: Int

    var overflowText: String? { overflow > 0 ? "+\(overflow) more" : nil }

    /// Every job the stack covers, shown or folded into "+N more".
    let runningCount: Int
    let failedCount: Int
    let totalCount: Int
    /// The agent of the oldest running job, for the mini view's mark.
    let runningAgent: AgentClient?

    var isEmpty: Bool { totalCount == 0 }

    /// The collapsed mini view's words: what is still going on first, then
    /// what went wrong, then what finished.
    var miniText: String {
        if runningCount > 0 { return runningCount == 1 ? "rating 1" : "rating \(runningCount)" }
        if failedCount > 0 { return "\(failedCount) failed" }
        return "\(totalCount) rated"
    }

    /// - Parameter trashed: snippets currently in Trash.
    /// - Parameter presented: the snippet whose detail card is open. Its panel
    ///   already shows the run, so it has no toast.
    init(
        jobs: [PersistentIdentifier: EfficiencyRatingCenter.Job],
        hiding presented: PersistentIdentifier?,
        trashed: Set<PersistentIdentifier> = [],
        limit: Int = RatingToastModel.visibleLimit
    ) {
        let visible = jobs
            .filter { id, job in
                guard id != presented else { return false }
                // A user cancel is already visible where it was made.
                return job.state != .failed(.cancelled)
            }
            .sorted { lhs, rhs in
                lhs.value.startedAt != rhs.value.startedAt
                    ? lhs.value.startedAt < rhs.value.startedAt
                    : lhs.value.snippetTitle < rhs.value.snippetTitle
            }
        rows = visible.prefix(limit).map { id, job in
            Row(id: id, kind: Self.kind(of: job.state), text: Self.text(for: job), agent: job.agent,
                canRetry: !trashed.contains(id))
        }
        overflow = max(visible.count - limit, 0)
        totalCount = visible.count
        runningCount = visible.filter { $0.value.state == .running }.count
        failedCount = visible.filter { if case .failed = $0.value.state { true } else { false } }.count
        runningAgent = visible.first { $0.value.state == .running }?.value.agent
    }

    private static func kind(of state: EfficiencyRatingCenter.Job.State) -> Row.Kind {
        switch state {
        case .running: .running
        case .succeeded: .succeeded
        case .failed: .failed
        }
    }

    static func text(for job: EfficiencyRatingCenter.Job) -> String {
        let title = "\u{201C}\(job.snippetTitle)\u{201D}"
        switch job.state {
        case .running:
            return "Rating \(title)…"
        case .succeeded(let score?, let band):
            let label = (band ?? EfficiencyBand(score: score)).label
            return "Rated \(title) · \(score) \(label)"
        case .succeeded(nil, _):
            return "Rated \(title) · not applicable"
        case .failed:
            return "Couldn\u{2019}t rate \(title)"
        }
    }
}
#endif
