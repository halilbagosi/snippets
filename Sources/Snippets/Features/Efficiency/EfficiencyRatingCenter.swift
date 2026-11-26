#if !APP_STORE
import Foundation
import Observation
import SwiftData

/// Owns every rating run, so a run outlives the detail view that started it.
/// Jobs are keyed by the snippet's `PersistentIdentifier` (`Snippet.uuid` is
/// optional).
@MainActor @Observable
final class EfficiencyRatingCenter {
    struct Job: Equatable {
        enum State: Equatable {
            case running
            case succeeded(score: Int?, band: EfficiencyBand?)
            case failed(EfficiencyRatingError)
        }
        var snippetTitle: String
        var agent: AgentClient
        var state: State
    }

    static let shared = EfficiencyRatingCenter()

    private(set) var jobs: [PersistentIdentifier: Job] = [:]
    let settings: EfficiencySettings

    @ObservationIgnored private let makeRater: (AgentClient) -> EfficiencyRater?
    @ObservationIgnored private let succeededLinger: Duration
    @ObservationIgnored private var runs: [PersistentIdentifier: Run] = [:]

    private struct Run {
        var token = UUID()
        var task: Task<Void, Never>?
        let context: ModelContext
    }

    init(
        settings: EfficiencySettings = EfficiencySettings(),
        succeededLinger: Duration = .seconds(3),
        makeRater: @escaping (AgentClient) -> EfficiencyRater? = EfficiencyRatingCenter.productionRater
    ) {
        self.settings = settings
        self.succeededLinger = succeededLinger
        self.makeRater = makeRater
    }

    nonisolated static func productionRater(for agent: AgentClient) -> EfficiencyRater? {
        agent == .claudeCode ? ClaudeCodeRater() : nil
    }

    // MARK: Consent (the panel shows the sheet)

    func needsConsent(for agent: AgentClient) -> Bool { !settings.isConsented(agent) }
    func grantConsent(for agent: AgentClient) { settings.grantConsent(for: agent) }

    // MARK: Jobs

    func isRunning(_ id: PersistentIdentifier) -> Bool { jobs[id]?.state == .running }

    /// No-op while this snippet already has a run. Replaces a finished job.
    func start(for snippet: Snippet) {
        let id = snippet.persistentModelID
        guard !isRunning(id), let context = snippet.modelContext else { return }
        let agent = settings.agent
        let title = snippet.title

        guard let rater = makeRater(agent) else {
            jobs[id] = Job(snippetTitle: title, agent: agent, state: .failed(.agentNotFound))
            runs[id] = Run(context: context)
            return
        }

        // Flush rule: the active config's stored code is refreshed before rating.
        let flushed = PreviewParamConfigStore.storingActiveCode(
            snippet.code, activeID: snippet.activeParamConfigID, in: snippet.paramConfigs)
        if flushed != snippet.paramConfigs { snippet.paramConfigs = flushed }

        let code = snippet.code
        let language = SupportedLanguage(stored: snippet.language)
        let request = EfficiencyRequest(
            title: title, language: language, code: code,
            dependencies: SnippetLinker.orderedDependencies(of: snippet).dependencies.map { ($0.title, $0.language, $0.code) })
        let model = settings.modelOverride(for: agent)

        var run = Run(context: context)
        let token = run.token
        jobs[id] = Job(snippetTitle: title, agent: agent, state: .running)
        run.task = Task { [weak self] in
            let outcome: Result<EfficiencyReport, EfficiencyRatingError>
            do {
                outcome = .success(try await rater.rate(request, model: model))
            } catch let error as EfficiencyRatingError {
                outcome = .failure(error)
            } catch is CancellationError {
                outcome = .failure(.cancelled)
            } catch {
                outcome = .failure(.failed(error.localizedDescription))
            }
            self?.finish(id: id, token: token, agent: agent, model: model, code: code, outcome: outcome)
        }
        runs[id] = run
    }

    /// Re-runs a job (typically a failed one) without needing the caller to
    /// hold the snippet.
    func retry(_ id: PersistentIdentifier) {
        guard !isRunning(id), let context = runs[id]?.context,
              let snippet = Self.fetchSnippet(id, in: context) else { return }
        start(for: snippet)
    }

    /// Ends the run immediately and nothing is saved. The job stays as
    /// `.failed(.cancelled)` (so the panel can offer Retry) until dismissed.
    func cancel(_ id: PersistentIdentifier) {
        guard isRunning(id), let run = runs[id] else { return }
        run.task?.cancel()
        // A fresh token makes the cancelled task's late completion a no-op.
        runs[id] = Run(task: nil, context: run.context)
        jobs[id]?.state = .failed(.cancelled)
    }

    /// App quit: every run is stopped, nothing is saved.
    func cancelAll() {
        for run in runs.values { run.task?.cancel() }
        runs.removeAll()
        jobs.removeAll()
    }

    /// Removes a finished job (the toast's dismiss).
    func dismiss(_ id: PersistentIdentifier) {
        guard !isRunning(id) else { return }
        jobs[id] = nil
        runs[id] = nil
    }

    // MARK: Completion

    private func finish(
        id: PersistentIdentifier, token: UUID, agent: AgentClient, model: String?,
        code: String, outcome: Result<EfficiencyReport, EfficiencyRatingError>
    ) {
        // Cancelled or superseded runs have already been removed.
        guard let run = runs[id], run.token == token, var job = jobs[id] else { return }

        switch outcome {
        case .failure(let error):
            job.state = .failed(error)
            jobs[id] = job
        case .success(let report):
            guard let snippet = Self.fetchSnippet(id, in: run.context) else {
                // Deleted mid-run: drop the result.
                jobs[id] = nil
                runs[id] = nil
                return
            }
            let review = EfficiencyReview(
                id: UUID(), codeHash: EfficiencyReviewStore.hash(of: code), ratedCode: code,
                rubricVersion: EfficiencyRubric.version, score: report.score,
                notApplicableReason: report.notApplicableReason, summary: report.summary,
                suggestions: report.suggestions, agent: agent.rawValue, model: model, date: .now)
            let previous = snippet.efficiencyReviews
            snippet.efficiencyReviews = EfficiencyReviewStore.pruned(
                snippet.efficiencyReviews + [review],
                configs: snippet.paramConfigs, currentCode: snippet.code)
            do {
                try run.context.save()
            } catch {
                snippet.efficiencyReviews = previous
                job.state = .failed(.failed("could not save the rating"))
                jobs[id] = job
                return
            }
            job.state = .succeeded(score: report.score, band: report.score.map(EfficiencyBand.init(score:)))
            jobs[id] = job
            scheduleRemoval(of: id, token: token)
        }
    }

    private func scheduleRemoval(of id: PersistentIdentifier, token: UUID) {
        let delay = succeededLinger
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.runs[id]?.token == token,
                  case .succeeded = self.jobs[id]?.state else { return }
            self.jobs[id] = nil
            self.runs[id] = nil
        }
    }

    private static func fetchSnippet(_ id: PersistentIdentifier, in context: ModelContext) -> Snippet? {
        var descriptor = FetchDescriptor<Snippet>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
#endif
