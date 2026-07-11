import SwiftUI
import WebKit

/// Hosts the WKWebView engine for web-family snippet previews. `sources`
/// are the snippet's resolved dependencies plus the entry itself, last.
struct WebPreviewView: NSViewRepresentable {
    let sources: [LinkedSource]
    let flavor: WebPreviewFlavor
    let theme: Theme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.needsReload(sources: sources, flavor: flavor, isDark: theme.scheme == .dark) else {
            return
        }
        let appearance = WebPreviewHTMLBuilder.Appearance(
            isDark: theme.scheme == .dark,
            backgroundHex: theme.canvasDeep.hexString(fallback: "#0E1014"),
            textHex: theme.text.hexString(fallback: "#E6E8EC")
        )
        let document = WebPreviewHTMLBuilder.document(
            linked: sources,
            entryFlavor: flavor,
            appearance: appearance,
            runtime: WebPreviewRuntime.shared
        )
        webView.loadHTMLString(document, baseURL: nil)
    }

    final class Coordinator {
        private var lastSources: [LinkedSource]?
        private var lastFlavor: WebPreviewFlavor?
        private var lastIsDark: Bool?

        func needsReload(sources: [LinkedSource], flavor: WebPreviewFlavor, isDark: Bool) -> Bool {
            if lastSources == sources, lastFlavor == flavor, lastIsDark == isDark { return false }
            (lastSources, lastFlavor, lastIsDark) = (sources, flavor, isDark)
            return true
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
