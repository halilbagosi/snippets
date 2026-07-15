import SwiftUI

/// Dispatches a snippet's resolved sources (dependencies + entry, see
/// `SnippetLinker`) to the preview engine for its language.
/// Only shown when `language.previewKind` is non-nil.
struct SnippetPreviewView: View {
    let resolution: SnippetLinker.Resolution
    let language: SupportedLanguage
    let theme: Theme

    private var entryCode: String { resolution.sources.last?.code ?? "" }
    private var helperCodes: [String] { resolution.sources.dropLast().map(\.code) }

    var body: some View {
        switch language.previewKind {
        case .web(let flavor):
            WebPreviewView(sources: resolution.sources, flavor: flavor, theme: theme)
        case .metal:
            MetalShaderPreviewView(entry: entryCode, helpers: helperCodes, theme: theme)
        case .swiftUI:
            SwiftPreviewHostView(entry: entryCode, helpers: helperCodes, theme: theme)
        case nil:
            PreviewUnavailableView(message: "No live preview for \(language.rawValue).", theme: theme)
        }
    }
}

/// Shared empty/error state used by the preview engines.
struct PreviewUnavailableView: View {
    let message: String
    let theme: Theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(theme.textMuted)
            Text(message)
                .font(Mono.font(size: 12))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSToken.Spacing.md)
    }
}
