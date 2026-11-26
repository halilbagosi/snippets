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
    }

    static let visibleLimit = 3

    let rows: [Row]
    /// Jobs past the limit, collapsed into one "+N more" row.
    let overflow: Int

    var overflowText: String? { overflow > 0 ? "+\(overflow) more" : nil }

    /// - Parameter presented: the snippet whose detail card is open. Its panel
    ///   already shows the run, so it has no toast.
    init(
        jobs: [PersistentIdentifier: EfficiencyRatingCenter.Job],
        hiding presented: PersistentIdentifier?,
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
            Row(id: id, kind: Self.kind(of: job.state), text: Self.text(for: job), agent: job.agent)
        }
        overflow = max(visible.count - limit, 0)
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
