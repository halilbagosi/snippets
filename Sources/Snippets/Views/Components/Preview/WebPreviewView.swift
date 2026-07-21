import SwiftUI
import WebKit

/// Hosts the WKWebView engine for web-family snippet previews. `sources`
/// are the snippet's resolved dependencies plus the entry itself, last.
struct WebPreviewView: NSViewRepresentable {
    let sources: [LinkedSource]
    let flavor: WebPreviewFlavor
    let theme: Theme
    /// Live prop overrides from the preview's parameter controls (react
    /// flavor only). Applied by re-rendering in place — never a reload.
    var propOverrides: [String: PreviewParamValue] = [:]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let appearance = WebPreviewHTMLBuilder.Appearance(
            isDark: theme.scheme == .dark,
            backgroundHex: theme.canvasDeep.hexString(fallback: "#0E1014"),
            textHex: theme.text.hexString(fallback: "#E6E8EC")
        )
        let overridesChanged = context.coordinator.lastOverrides != propOverrides
        context.coordinator.lastOverrides = propOverrides
        let applyOverrides = {
            webView.evaluateJavaScript(
                WebPreviewHTMLBuilder.propsUpdateScript(overrides: propOverrides)
            )
        }
        switch context.coordinator.classify(sources: sources, flavor: flavor, isDark: theme.scheme == .dark) {
        case .none:
            if overridesChanged { applyOverrides() }
            return
        case .themeOnly:
            webView.evaluateJavaScript(WebPreviewHTMLBuilder.themeUpdateScript(appearance: appearance))
            if overridesChanged { applyOverrides() }
        case .sourceOnly:
            if let script = WebPreviewHTMLBuilder.sourceUpdateScript(linked: sources, entryFlavor: flavor) {
                let sources = sources, flavor = flavor
                webView.evaluateJavaScript(script) { _, error in
                    guard error != nil else { return }
                    // The incremental path failed (e.g. shell in an unexpected
                    // state) — fall back to a full reload of the same content.
                    Self.loadFullDocument(webView, sources: sources, flavor: flavor, appearance: appearance)
                }
            } else {
                Self.loadFullDocument(webView, sources: sources, flavor: flavor, appearance: appearance)
            }
        case .full:
            context.coordinator.pendingOverrides = propOverrides
            Self.loadFullDocument(webView, sources: sources, flavor: flavor, appearance: appearance)
        }
    }

    private static func loadFullDocument(
        _ webView: WKWebView,
        sources: [LinkedSource],
        flavor: WebPreviewFlavor,
        appearance: WebPreviewHTMLBuilder.Appearance
    ) {
        let document = WebPreviewHTMLBuilder.document(
            linked: sources,
            entryFlavor: flavor,
            appearance: appearance,
            runtime: WebPreviewRuntime.shared
        )
        webView.loadHTMLString(document, baseURL: nil)
    }

    enum Change {
        case none, themeOnly, sourceOnly, full
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var lastSources: [LinkedSource]?
        private var lastFlavor: WebPreviewFlavor?
        private var lastIsDark: Bool?
        var lastOverrides: [String: PreviewParamValue]?
        /// Overrides to re-apply once a full document load finishes — a
        /// reload resets `window.__snippetPropOverrides`.
        var pendingOverrides: [String: PreviewParamValue] = [:]

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !pendingOverrides.isEmpty else { return }
            webView.evaluateJavaScript(
                WebPreviewHTMLBuilder.propsUpdateScript(overrides: pendingOverrides)
            )
        }

        /// Classifies what changed since the last render so the view can pick
        /// the cheapest update: retint in place (`themeOnly`), re-run the user
        /// program in the existing shell (`sourceOnly`), or rebuild the
        /// document (`full`). Non-script helpers (CSS/HTML) live in the shell,
        /// so a change to them forces `full` even when the flavor matches.
        func classify(sources: [LinkedSource], flavor: WebPreviewFlavor, isDark: Bool) -> Change {
            defer { (lastSources, lastFlavor, lastIsDark) = (sources, flavor, isDark) }
            guard let lastSources, let lastFlavor, let lastIsDark else { return .full }

            if sources == lastSources, flavor == lastFlavor {
                return isDark == lastIsDark ? .none : .themeOnly
            }
            guard flavor == lastFlavor, isDark == lastIsDark else { return .full }

            let shellHelpers: ([LinkedSource]) -> [LinkedSource] = { linked in
                linked.dropLast().filter { [.css, .html].contains($0.language) }
            }
            guard shellHelpers(sources) == shellHelpers(lastSources) else { return .full }
            return .sourceOnly
        }

        /// Snippet JS must not navigate the preview anywhere. Only the initial
        /// `loadHTMLString` (which arrives with a nil or `about:` URL) is
        /// allowed; everything else — especially http(s) — is cancelled. This
        /// also constrains full-document passthrough snippets, which bypass the
        /// skeleton CSP; subresource fetches inside such documents remain a
        /// known residual gap.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            return url.scheme == "about" ? .allow : .cancel
        }
    }
}

/// Loads the vendored react/react-dom/babel scripts from the app bundle once.
enum WebPreviewRuntime {
    static let shared: WebPreviewHTMLBuilder.ReactRuntime = {
        func script(_ name: String) -> String {
            guard let url = Bundle.snippetsResources.url(forResource: name, withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                return "document.body.textContent = 'Missing bundled runtime: \(name).js';"
            }
            return source
        }
        return .init(
            react: script("react.production.min"),
            reactDOM: script("react-dom.production.min"),
            babel: script("babel.min")
        )
    }()
}
