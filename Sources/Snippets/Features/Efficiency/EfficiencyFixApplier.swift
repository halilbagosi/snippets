import Foundation

/// Config switching and fix-application rules that touch `snippet.code`.
///
/// Applying a suggested fix never overwrites code: it becomes a new named
/// config, like changed parameters. `snippet.code` is always the active
/// config's code, so every writer (editor, MCP, parameter writes) keeps
/// working; a config's stored `code` is refreshed only when it is switched
/// away from, another config is deleted, or on export.
///
/// Not agent-specific, so it compiles in every build: the select/delete rules
/// apply to anyone whose configs carry code.
enum EfficiencyFixApplier {
    /// "Save as new config…": rated code + this one change, saved under `name`
    /// and made active. Returns false (changing nothing) when the suggestion's
    /// `before` no longer occurs exactly once in `review.ratedCode`.
    ///
    /// `declared` reads the params the snippet's code declares *now*; it is
    /// asked before the swap (for `Default`) and after (for the new config), so
    /// the saved values never revert a literal the fix changed.
    @discardableResult
    static func saveAsNew(
        snippet: Snippet,
        review: EfficiencyReview,
        suggestion: EfficiencyReview.Suggestion,
        name: String,
        overrides: [String: PreviewParamValue],
        declared: () -> [PreviewParam],
        applyValues: ([String: PreviewParamValue]) -> Void,
        forgetTrust: (UUID?) -> Void
    ) -> Bool {
        guard let newCode = EfficiencyReviewStore.applying(suggestion, to: review.ratedCode) else {
            return false
        }
        let before = snippet.code
        let declaredBefore = declared()
        let flushed = PreviewParamConfigStore.storingActiveCode(
            before, activeID: snippet.activeParamConfigID, in: snippet.paramConfigs
        )
        let saved = PreviewParamConfigStore.savingCodeVariant(
            code: newCode, values: overrides, named: name, sourceReviewID: review.id,
            currentCode: before, declared: declaredBefore, into: flushed
        )
        snippet.code = newCode
        var configs = saved.configs
        if let index = configs.firstIndex(where: { $0.id == saved.newID }) {
            var values = PreviewParamConfigStore.declaredValues(declared())
            for (key, value) in overrides where values[key] != nil { values[key] = value }
            configs[index].values = values
        }
        snippet.paramConfigs = configs
        snippet.activeParamConfigID = saved.newID
        if let config = configs.first(where: { $0.id == saved.newID }) {
            applyValues(PreviewParamConfigStore.resolvedValues(for: config, declared: declared()))
        }
        finishCodeWrite(snippet, forgetTrust: forgetTrust)
        return true
    }

    /// "Add to ‹active›": applies the suggestion to the active config's code.
    /// Allowed only when the active config came from `review` and the
    /// suggestion's `before` still occurs exactly once in `snippet.code`.
    @discardableResult
    static func addToActive(
        snippet: Snippet,
        review: EfficiencyReview,
        suggestion: EfficiencyReview.Suggestion,
        forgetTrust: (UUID?) -> Void
    ) -> Bool {
        guard canAddToActive(snippet: snippet, review: review, suggestion: suggestion),
              let newCode = EfficiencyReviewStore.applying(suggestion, to: snippet.code) else {
            return false
        }
        snippet.code = newCode
        finishCodeWrite(snippet, forgetTrust: forgetTrust)
        return true
    }

    static func canAddToActive(
        snippet: Snippet, review: EfficiencyReview, suggestion: EfficiencyReview.Suggestion
    ) -> Bool {
        guard let active = snippet.paramConfigs.first(where: { $0.id == snippet.activeParamConfigID }),
              active.sourceReviewID == review.id else { return false }
        return EfficiencyReviewStore.matchState(of: suggestion, in: snippet.code) == .applies
    }

    /// Switching configs: store the outgoing config's code, restore the
    /// incoming one's (or `Default`'s), then apply its values.
    static func select(
        id: UUID,
        in snippet: Snippet,
        declared: () -> [PreviewParam],
        applyValues: ([String: PreviewParamValue]) -> Void
    ) {
        guard let config = snippet.paramConfigs.first(where: { $0.id == id }) else { return }
        snippet.paramConfigs = PreviewParamConfigStore.storingActiveCode(
            snippet.code, activeID: snippet.activeParamConfigID, in: snippet.paramConfigs
        )
        snippet.activeParamConfigID = id
        if let code = PreviewParamConfigStore.codeToActivate(for: id, in: snippet.paramConfigs) {
            snippet.code = code
        }
        applyValues(PreviewParamConfigStore.resolvedValues(for: config, declared: declared()))
    }

    /// Deleting a config. Deleting the active one falls back to `Default`,
    /// code included; deleting another first stores the active config's code.
    static func delete(id: UUID, from snippet: Snippet) {
        let wasActive = snippet.activeParamConfigID == id
        let remaining = PreviewParamConfigStore.deleting(id: id, from: snippet.paramConfigs)
        guard remaining.count != snippet.paramConfigs.count else { return }
        if wasActive {
            snippet.paramConfigs = remaining
            let fallback = remaining.first(where: \.isDefault)
            snippet.activeParamConfigID = fallback?.id
            if let fallback,
               let code = PreviewParamConfigStore.codeToActivate(for: fallback.id, in: remaining) {
                snippet.code = code
            }
        } else {
            snippet.paramConfigs = PreviewParamConfigStore.storingActiveCode(
                snippet.code, activeID: snippet.activeParamConfigID, in: remaining
            )
        }
    }

    /// AI-written code is now running: revoke approvals at every depth, stamp
    /// the edit, and drop ratings no config or current code needs.
    private static func finishCodeWrite(_ snippet: Snippet, forgetTrust: (UUID?) -> Void) {
        snippet.uuidsRunningThisCode.forEach(forgetTrust)
        snippet.updatedAt = .now
        snippet.efficiencyReviews = EfficiencyReviewStore.pruned(
            snippet.efficiencyReviews, configs: snippet.paramConfigs, currentCode: snippet.code
        )
    }
}
