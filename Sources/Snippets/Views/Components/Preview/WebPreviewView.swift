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
    /// What this snippet has been granted. Denied unless the user said
    /// otherwise; a change forces a full reload because the policy is
    /// expressed as a CSP in the document head, which cannot be edited in
    /// place once parsed.
    var policy: WebPreviewHTMLBuilder.Policy = .denied

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // Matches the background the generated document paints. Leaving this
        // clear let the bright Liquid Glass panel behind the web view show
        // through until the first paint landed, flashing on every load.
        webView.underPageBackgroundColor = NSColor(theme.canvasDeep)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.underPageBackgroundColor = NSColor(theme.canvasDeep)
        // Backstop under the documents' CSP: a WebKit-level rule that drops
        // remote loads whatever the markup asks for. Driven from here rather
        // than `makeNSView` because the list depends on the policy, which can
        // change while the same web view stays mounted. Compilation is async,
        // so it attaches a runloop turn later — the CSP holds the line in the
        // meantime, and the policy change itself forces a full reload below.
        if context.coordinator.installedPolicy != policy {
            context.coordinator.installedPolicy = policy
            PreviewContentRules.install(on: webView, policy: policy)
        }
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
        switch context.coordinator.classify(
            sources: sources, flavor: flavor, isDark: theme.scheme == .dark, policy: policy
        ) {
        case .none:
            if overridesChanged { applyOverrides() }
            return
        case .themeOnly:
            webView.evaluateJavaScript(WebPreviewHTMLBuilder.themeUpdateScript(appearance: appearance))
            if overridesChanged { applyOverrides() }
        case .sourceOnly:
            if let script = WebPreviewHTMLBuilder.sourceUpdateScript(
                linked: sources, entryFlavor: flavor, policy: policy
            ) {
                let sources = sources, flavor = flavor, policy = policy
                webView.evaluateJavaScript(script) { _, error in
                    guard error != nil else { return }
                    // The incremental path failed (e.g. shell in an unexpected
                    // state) — fall back to a full reload of the same content.
                    Self.loadFullDocument(
                        webView, sources: sources, flavor: flavor,
                        appearance: appearance, policy: policy
                    )
                }
            } else {
                Self.loadFullDocument(
                    webView, sources: sources, flavor: flavor,
                    appearance: appearance, policy: policy
                )
            }
        case .full:
            context.coordinator.pendingOverrides = propOverrides
            Self.loadFullDocument(
                webView, sources: sources, flavor: flavor,
                appearance: appearance, policy: policy
            )
        }
    }

    private static func loadFullDocument(
        _ webView: WKWebView,
        sources: [LinkedSource],
        flavor: WebPreviewFlavor,
        appearance: WebPreviewHTMLBuilder.Appearance,
        policy: WebPreviewHTMLBuilder.Policy
    ) {
        let document = WebPreviewHTMLBuilder.document(
            linked: sources,
            entryFlavor: flavor,
            appearance: appearance,
            runtime: WebPreviewRuntime.shared,
            policy: policy
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
        private var lastPolicy: WebPreviewHTMLBuilder.Policy?
        var lastOverrides: [String: PreviewParamValue]?
        /// Which policy's rule list is currently attached; nil until the first
        /// install. Distinct from `lastPolicy`, which tracks what was rendered.
        var installedPolicy: WebPreviewHTMLBuilder.Policy?
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
        ///
        /// A policy change is always `full`: the grant is carried by the CSP in
        /// the document head, and a document already parsed under the closed
        /// policy cannot be widened by any amount of scripting.
        func classify(
            sources: [LinkedSource],
            flavor: WebPreviewFlavor,
            isDark: Bool,
            policy: WebPreviewHTMLBuilder.Policy
        ) -> Change {
            defer {
                (lastSources, lastFlavor, lastIsDark) = (sources, flavor, isDark)
                lastPolicy = policy
            }
            guard let lastSources, let lastFlavor, let lastIsDark, let lastPolicy else { return .full }
            guard policy == lastPolicy else { return .full }

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

/// WebKit-level block on remote loads in the preview, under the documents' own
/// CSP.
///
/// The CSP is the primary control and every document path now emits one. This
/// exists because that guarantee lives in string-building code that is edited
/// often: a content rule list is enforced by the networking layer regardless of
/// what the markup says, so a document path that someday forgets the meta tag
/// still cannot reach the network.
///
/// Only http/https/ws/wss are blocked — `about:`, `data:` and `blob:` are left
/// alone so the CSP's `img-src data: blob:` keeps working.
enum PreviewContentRules {
    private static let blockRemote = """
    [{"trigger": {"url-filter": "^https?://", "url-filter-is-case-sensitive": false},
      "action": {"type": "block"}},
     {"trigger": {"url-filter": "^wss?://", "url-filter-is-case-sensitive": false},
      "action": {"type": "block"}}]
    """

    /// Same, minus esm.sh — installed only for a snippet the user granted npm
    /// imports to, so the block list never contradicts the widened CSP.
    private static let blockRemoteExceptCDN = """
    [{"trigger": {"url-filter": "^https?://", "url-filter-is-case-sensitive": false},
      "action": {"type": "block"}},
     {"trigger": {"url-filter": "^wss?://", "url-filter-is-case-sensitive": false},
      "action": {"type": "block"}},
     {"trigger": {"url-filter": "^https://esm\\\\.sh/", "url-filter-is-case-sensitive": false},
      "action": {"type": "ignore-previous-rules"}}]
    """

    private static func identifier(for policy: WebPreviewHTMLBuilder.Policy) -> String {
        policy.allowsCDNModules ? "snippet-preview-allow-esm" : "snippet-preview-block-remote"
    }

    private static func source(for policy: WebPreviewHTMLBuilder.Policy) -> String {
        policy.allowsCDNModules ? blockRemoteExceptCDN : blockRemote
    }

    /// Compiles (WebKit caches by identifier, so this is cheap after the first
    /// call) and attaches the list for `policy`. Best-effort by design: a
    /// compile failure leaves the CSP as the only control, which is the same
    /// position every document was in before this type existed — so it must
    /// never block or fail a preview.
    static func install(on webView: WKWebView, policy: WebPreviewHTMLBuilder.Policy) {
        let store = WKContentRuleListStore.default()
        let identifier = identifier(for: policy)
        let source = source(for: policy)
        store?.compileContentRuleList(
            forIdentifier: identifier, encodedContentRuleList: source
        ) { list, _ in
            guard let list else { return }
            // The previous policy's list must go, or a revoked grant would
            // leave its esm.sh exception attached.
            webView.configuration.userContentController.removeAllContentRuleLists()
            webView.configuration.userContentController.add(list)
        }
    }
}

/// Loads the vendored preview runtimes (react/react-dom/babel, Tailwind,
/// Bootstrap) from the app bundle once.
enum WebPreviewRuntime {
    static let shared: WebPreviewHTMLBuilder.PreviewRuntime = {
        func asset(_ name: String, _ ext: String, missing: String) -> String {
            guard let url = Bundle.snippetsResources.url(forResource: name, withExtension: ext),
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                return missing
            }
            return source
        }
        func script(_ name: String) -> String {
            asset(name, "js", missing: "document.body.textContent = 'Missing bundled runtime: \(name).js';")
        }
        return .init(
            react: script("react.production.min"),
            reactDOM: script("react-dom.production.min"),
            babel: script("babel.min"),
            tailwind: script("tailwind.browser.min"),
            bootstrapCSS: asset("bootstrap.min", "css", missing: ""),
            bootstrapJS: script("bootstrap.bundle.min")
        )
    }()
}
