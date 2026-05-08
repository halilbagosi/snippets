import SwiftUI
import WebKit
import AVKit
#if canImport(AppKit)
import AppKit
#endif

struct SnippetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let snippet: Snippet
    var isSelected: Bool = false

    @State private var didCopy: Bool = false
    @State private var copyResetTask: Task<Void, Never>? = nil
    @State private var isHovered: Bool = false
    @State private var didAppear: Bool = false

    private var language: SupportedLanguage {
        SupportedLanguage(rawValue: snippet.language) ?? .unknown
    }

    private var primaryMedia: MediaItem? {
        snippet.mediaItems.sorted { $0.addedAt < $1.addedAt }.first
    }

    private var orderedMediaItems: [MediaItem] {
        snippet.mediaItems.sorted { $0.addedAt < $1.addedAt }
    }

    private func performCopy() {
        Clipboard.copy(snippet.code)
        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if !Task.isCancelled { didCopy = false }
        }
    }

    @ViewBuilder
    private func copyButton(theme: Theme, languageAccent: Color) -> some View {
        Button(action: performCopy) {
            HStack(spacing: 5) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(Mono.font(size: 10, weight: .bold))
                Text(didCopy ? "copied" : "code")
                    .font(Mono.font(size: 10, weight: .semibold))
            }
            .foregroundStyle(didCopy ? languageAccent : theme.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(didCopy ? languageAccent.opacity(colorScheme == .dark ? 0.20 : 0.15) : theme.surface.opacity(0.85))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(didCopy ? languageAccent.opacity(0.48) : theme.border, lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy snippet code")
        .accessibilityLabel(didCopy ? "Copied" : "Copy code")
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
        let languageAccent = theme.accentColor(for: language)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                    .font(Sans.font(size: 15, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                if !snippet.snippetDescription.isEmpty {
                    Text(snippet.snippetDescription)
                        .font(Sans.font(size: 12))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Group {
                if !orderedMediaItems.isEmpty {
                    if orderedMediaItems.count == 1, let media = primaryMedia {
                        GeometryReader { geo in
                            GalleryAttachmentPreview(
                                item: media,
                                contentSize: CGSize(width: geo.size.width, height: geo.size.height),
                                innerPadding: GalleryCardAttachmentLayout.innerPadding,
                                cornerRadius: GalleryCardAttachmentLayout.singleCornerRadius
                            )
                        }
                    } else {
                        CardMediaGrid(items: orderedMediaItems)
                    }
                } else {
                    CardWebPreviewView(
                        code: snippet.code,
                        language: language,
                        isDark: colorScheme == .dark,
                        compact: true
                    )
                    .frame(height: 132)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 8) {
                LanguageBadge(language: language, compact: true)
                if snippet.mediaItems.count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                        Text("\(snippet.mediaItems.count)")
                    }
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                }
                copyButton(theme: theme, languageAccent: languageAccent)
                Spacer(minLength: 8)
                Text(snippet.updatedAt, format: .relative(presentation: .numeric))
                    .font(Mono.font(size: 10))
                    .foregroundStyle(theme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(colorScheme == .dark ? 0.08 : 0.24),
                                    theme.surface.opacity(colorScheme == .dark ? 0.58 : 0.42),
                                    languageAccent.opacity(isHovered ? (colorScheme == .dark ? 0.08 : 0.06) : 0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    if isHovered {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(languageAccent.opacity(colorScheme == .dark ? 0.13 : 0.09))
                            .transition(.opacity)
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? languageAccent.opacity(0.85) : .white.opacity(colorScheme == .dark ? 0.14 : 0.40),
                    lineWidth: isSelected ? 1.35 : 1
                )
                .shadow(
                    color: languageAccent.opacity(isHovered ? (colorScheme == .dark ? 0.56 : 0.35) : 0),
                    radius: isHovered ? 18 : 0
                )
        }
        .overlay(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    .white.opacity(isHovered ? 0.20 : 0.10),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .rotation3DEffect(.degrees(isHovered ? 1.8 : 0), axis: (x: -1, y: 1, z: 0))
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 10)
        .shadow(
            color: .black.opacity(colorScheme == .dark ? (isHovered ? 0.32 : 0.22) : (isHovered ? 0.09 : 0.06)),
            radius: isHovered ? 24 : 18,
            x: 0,
            y: isHovered ? 12 : 8
        )
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                didAppear = true
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: isHovered)
    }
}

private enum GalleryCardAttachmentLayout {
    static let innerPadding: CGFloat = 10
    static let singleCornerRadius: CGFloat = 10
    static let gridInnerPadding: CGFloat = 6
    static let gridCellCornerRadius: CGFloat = 8
}

private struct GalleryAttachmentPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: MediaItem
    let contentSize: CGSize
    let innerPadding: CGFloat
    let cornerRadius: CGFloat

    private var innerCornerRadius: CGFloat {
        max(4, cornerRadius - innerPadding * 0.5)
    }

    private var innerSize: CGSize {
        CGSize(
            width: max(1, contentSize.width - innerPadding * 2),
            height: max(1, contentSize.height - innerPadding * 2)
        )
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
        ZStack(alignment: .topTrailing) {
            Group {
                switch item.kind {
                case .image:
                    CardImagePreview(item: item)
                case .video:
                    CardVideoPreview(item: item)
                }
            }
            .frame(width: innerSize.width, height: innerSize.height)
            .clipShape(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous))

            if item.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(innerPadding + 3)
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(theme.borderStrong.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct CardMediaGrid: View {
    let items: [MediaItem]

    private let spacing: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let displayed = Array(items.prefix(4))
            let columns = min(2, displayed.count)
            let rows = max(Int(ceil(Double(displayed.count) / Double(columns))), 1)
            let tileWidth = (proxy.size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let tileHeight = (proxy.size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: spacing), count: columns), spacing: spacing) {
                ForEach(Array(displayed.enumerated()), id: \.element.persistentModelID) { index, item in
                    ZStack {
                        GalleryAttachmentPreview(
                            item: item,
                            contentSize: CGSize(width: tileWidth, height: tileHeight),
                            innerPadding: GalleryCardAttachmentLayout.gridInnerPadding,
                            cornerRadius: GalleryCardAttachmentLayout.gridCellCornerRadius
                        )

                        if index == displayed.count - 1, items.count > displayed.count {
                            Text("+\(items.count - displayed.count)")
                                .font(Mono.font(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.55), in: Capsule(style: .continuous))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CardImagePreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: MediaItem
    #if canImport(AppKit)
    @State private var image: NSImage? = nil
    #endif

    var body: some View {
        let theme = Theme.current(colorScheme)
        ZStack {
            theme.inset
            #if canImport(AppKit)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
            #else
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            #if canImport(AppKit)
            let url = MediaManager.resolvedURL(for: item.fileName)
            image = NSImage(contentsOf: url)
            #endif
        }
    }
}

private struct CardVideoPreview: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            AutoplayingVideoView(fileName: item.fileName, videoGravity: .resizeAspect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if canImport(AppKit)
private struct AutoplayingVideoView: NSViewRepresentable {
    let fileName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        let url = MediaManager.resolvedURL(for: fileName)
        view.configure(with: url, videoGravity: videoGravity)
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        let url = MediaManager.resolvedURL(for: fileName)
        nsView.configure(with: url, videoGravity: videoGravity)
    }

    static func dismantleNSView(_ nsView: PlayerContainerView, coordinator: ()) {
        nsView.teardown()
    }
}

final class PlayerContainerView: NSView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: NSObjectProtocol?
    private var currentURL: URL?
    private var currentGravity: AVLayerVideoGravity = .resizeAspectFill

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    func configure(with url: URL, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        if currentURL == url, currentGravity == videoGravity, player != nil { return }
        teardown()
        currentURL = url
        currentGravity = videoGravity

        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none

        let newLayer = AVPlayerLayer(player: newPlayer)
        newLayer.videoGravity = videoGravity
        newLayer.frame = bounds
        layer?.addSublayer(newLayer)

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        newPlayer.play()

        player = newPlayer
        playerLayer = newLayer
    }

    func teardown() {
        player?.pause()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        currentURL = nil
        currentGravity = .resizeAspectFill
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
}
#else
private struct AutoplayingVideoView: View {
    let fileName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var body: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 28))
            .foregroundStyle(.secondary)
    }
}
#endif
// MARK: - HTML Builder

/// Generates themed HTML preview content for every supported language.
private enum CardPreviewHTMLBuilder {

    /// Whether this language can produce a truly "runnable" preview (live DOM output).
    static func isRunnable(_ language: SupportedLanguage) -> Bool {
        switch language {
        case .html, .css, .javascript, .react, .typescript: return true
        default: return false
        }
    }

    static func html(
        for code: String,
        language: SupportedLanguage,
        isDark: Bool,
        compact: Bool
    ) -> String {
        switch language {
        case .html:       return htmlPreview(code, isDark: isDark)
        case .css:        return cssPreview(code, isDark: isDark)
        case .javascript: return jsPreview(code, isDark: isDark)
        case .react:      return reactPreview(code, isDark: isDark)
        case .typescript: return tsPreview(code, isDark: isDark)
        case .json:       return jsonPreview(code, isDark: isDark, compact: compact)
        default:          return codeCardPreview(code, language: language, isDark: isDark, compact: compact)
        }
    }

    // MARK: – Runnable previews

    private static func htmlPreview(_ code: String, isDark: Bool) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        // Inject base styles if user code doesn't set them
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: 12px; font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: \(bg); color: \(isDark ? "#e6edF3" : "#242a30"); }
        </style>
        </head>
        <body>
        \(code)
        </body>
        </html>
        """
    }

    private static func cssPreview(_ code: String, isDark: Bool) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { box-sizing: border-box; }
        body { display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; background: \(bg); color: \(fg); font-family: -apple-system, sans-serif; padding: 16px; }
        \(code)
        </style>
        </head>
        <body>
        <div class="preview">
          <h2>Heading</h2>
          <p>Preview paragraph text.</p>
          <button>Button</button>
          <a href="#">Link</a>
          <div class="box" style="width:60px;height:60px;margin-top:8px;border:1px solid currentColor;border-radius:6px;"></div>
        </div>
        </body>
        </html>
        """
    }

    private static func jsPreview(_ code: String, isDark: Bool) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        let escaped = code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: 16px; font-family: -apple-system, monospace; background: \(bg); color: \(fg); font-size: 13px; line-height: 1.5; }
        .output-line { padding: 2px 0; }
        .error { color: #ff6b6b; }
        </style>
        </head>
        <body>
        <div id="output"></div>
        <script>
        (function(){
            const out = document.getElementById('output');
            const _log = console.log;
            console.log = function() {
                const line = document.createElement('div');
                line.className = 'output-line';
                line.textContent = Array.from(arguments).map(a => {
                    if (typeof a === 'object') return JSON.stringify(a, null, 2);
                    return String(a);
                }).join(' ');
                out.appendChild(line);
                _log.apply(console, arguments);
            };
            try {
                \(escaped)
            } catch(e) {
                const line = document.createElement('div');
                line.className = 'output-line error';
                line.textContent = e.toString();
                out.appendChild(line);
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    private static func reactPreview(_ code: String, isDark: Bool) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        let escaped = code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
            .replacingOccurrences(of: "`", with: "\\`")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: 16px; font-family: -apple-system, sans-serif; background: \(bg); color: \(fg); }
        .error { color: #ff6b6b; font-family: monospace; font-size: 12px; white-space: pre-wrap; padding: 12px; }
        </style>
        <script src="https://unpkg.com/react@18/umd/react.production.min.js" crossorigin></script>
        <script src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js" crossorigin></script>
        <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
        </head>
        <body>
        <div id="root"></div>
        <script>
        (function() {
            try {
                const userCode = `\(escaped)`;
                // Strip import/export statements for in-browser eval
                const cleaned = userCode
                    .replace(/^\\s*import\\s+.*?[;\\n]/gm, '')
                    .replace(/^\\s*export\\s+default\\s+/gm, 'const __DefaultExport__ = ')
                    .replace(/^\\s*export\\s+/gm, '');
                const transpiled = Babel.transform(cleaned, {
                    presets: ['react'],
                    plugins: []
                }).code;
                const module = { exports: {} };
                const fn = new Function('React', 'ReactDOM', 'module', 'exports', 'useState', 'useEffect', 'useRef', 'useMemo', 'useCallback',
                    transpiled + ';\\nreturn typeof __DefaultExport__ !== "undefined" ? __DefaultExport__ : (typeof App !== "undefined" ? App : null);'
                );
                const { useState, useEffect, useRef, useMemo, useCallback } = React;
                const Component = fn(React, ReactDOM, module, module.exports, useState, useEffect, useRef, useMemo, useCallback);
                if (Component) {
                    const root = ReactDOM.createRoot(document.getElementById('root'));
                    root.render(React.createElement(Component));
                } else {
                    document.getElementById('root').innerHTML = '<div class="error">No default export or App component found.</div>';
                }
            } catch(e) {
                document.getElementById('root').innerHTML = '<div class="error">' + e.toString() + '</div>';
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    private static func tsPreview(_ code: String, isDark: Bool) -> String {
        // TypeScript runs as JS after stripping type annotations via regex
        let stripped = code
            .replacingOccurrences(of: #": string"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #": number"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #": boolean"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #": any"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #": void"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[A-Z]\w*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"interface \w+ \{[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"type \w+ = [^;]+;"#, with: "", options: .regularExpression)
        return jsPreview(stripped, isDark: isDark)
    }

    // MARK: – JSON viewer

    private static func jsonPreview(_ code: String, isDark: Bool, compact: Bool) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        let keyColor = isDark ? "#7ab5ff" : "#2563eb"
        let strColor = isDark ? "#f2cc60" : "#b45309"
        let numColor = isDark ? "#7ab5ff" : "#1d4ed8"
        let boolColor = isDark ? "#ff7b7b" : "#dc2626"
        let fontSize = compact ? "10px" : "12px"
        let escaped = code.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: \(compact ? "8px" : "14px"); font-family: ui-monospace, 'SF Mono', monospace; background: \(bg); color: \(fg); font-size: \(fontSize); line-height: 1.6; overflow: auto; }
        .key { color: \(keyColor); }
        .str { color: \(strColor); }
        .num { color: \(numColor); }
        .bool, .null { color: \(boolColor); }
        .bracket { color: \(isDark ? "#6e7681" : "#8b949e"); }
        .indent { margin-left: 16px; }
        .error { color: #ff6b6b; font-size: 12px; }
        </style>
        </head>
        <body>
        <div id="json-root"></div>
        <script>
        (function(){
            function renderJSON(val, depth) {
                if (val === null) return '<span class="null">null</span>';
                if (typeof val === 'boolean') return '<span class="bool">' + val + '</span>';
                if (typeof val === 'number') return '<span class="num">' + val + '</span>';
                if (typeof val === 'string') return '<span class="str">"' + val.replace(/</g,'&lt;') + '"</span>';
                if (Array.isArray(val)) {
                    if (val.length === 0) return '<span class="bracket">[]</span>';
                    let h = '<span class="bracket">[</span><br>';
                    val.forEach(function(item, i) {
                        h += '<div class="indent">' + renderJSON(item, depth+1) + (i < val.length-1 ? ',' : '') + '</div>';
                    });
                    return h + '<span class="bracket">]</span>';
                }
                if (typeof val === 'object') {
                    const keys = Object.keys(val);
                    if (keys.length === 0) return '<span class="bracket">{}</span>';
                    let h = '<span class="bracket">{</span><br>';
                    keys.forEach(function(k, i) {
                        h += '<div class="indent"><span class="key">"' + k + '"</span>: ' + renderJSON(val[k], depth+1) + (i < keys.length-1 ? ',' : '') + '</div>';
                    });
                    return h + '<span class="bracket">}</span>';
                }
                return String(val);
            }
            try {
                const data = JSON.parse('\(escaped)');
                document.getElementById('json-root').innerHTML = renderJSON(data, 0);
            } catch(e) {
                document.getElementById('json-root').innerHTML = '<div class="error">' + e.toString() + '</div>';
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    // MARK: – Themed code card (all other languages)

    private static func codeCardPreview(
        _ code: String,
        language: SupportedLanguage,
        isDark: Bool,
        compact: Bool
    ) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        let gutterColor = isDark ? "#3b4048" : "#b0b8c4"
        let keywordColor = isDark ? "#ff7b72" : "#cf222e"
        let stringColor = isDark ? "#f2cc60" : "#b45309"
        let commentColor = isDark ? "#6e8295" : "#7e8894"
        let typeColor = isDark ? "#7ab5ff" : "#1d4ed8"
        let numberColor = isDark ? "#7ab5ff" : "#1d4ed8"
        let accentHex = language.accentHex
        let fontSize = compact ? "10px" : "12.5px"
        let lineHeight = compact ? "1.5" : "1.65"
        let padding = compact ? "8px 6px" : "14px 12px"

        let keywords = languageKeywords(language)
        let escapedCode = code
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: \(bg);
            font-family: ui-monospace, 'SF Mono', 'Cascadia Code', 'Fira Code', monospace;
            font-size: \(fontSize);
            line-height: \(lineHeight);
            color: \(fg);
            padding: \(padding);
            overflow: hidden;
        }
        .line { display: flex; }
        .gutter {
            color: \(gutterColor);
            text-align: right;
            padding-right: 12px;
            min-width: \(compact ? "24px" : "32px");
            user-select: none;
            flex-shrink: 0;
        }
        .code-content { white-space: pre; flex: 1; overflow: hidden; }
        .kw { color: \(keywordColor); font-weight: 600; }
        .str { color: \(stringColor); }
        .cmt { color: \(commentColor); font-style: italic; }
        .typ { color: \(typeColor); }
        .num { color: \(numberColor); }
        .accent-bar {
            position: fixed;
            top: 0; left: 0;
            width: 3px;
            height: 100%;
            background: \(accentHex);
            opacity: 0.6;
            border-radius: 0 2px 2px 0;
        }
        </style>
        </head>
        <body>
        <div class="accent-bar"></div>
        <script>
        (function(){
            const raw = \(jsonStringLiteral(escapedCode));
            const keywords = new Set(\(jsonArrayLiteral(keywords)));
            const lines = raw.split('\\n');
            let html = '';
            for (let i = 0; i < lines.length; i++) {
                const num = i + 1;
                const highlighted = highlightLine(lines[i], keywords);
                html += '<div class="line"><span class="gutter">' + num + '</span><span class="code-content">' + highlighted + '</span></div>';
            }
            document.body.insertAdjacentHTML('beforeend', html);

            function highlightLine(line, kws) {
                // Comment detection
                if (line.trimStart().startsWith('//') || line.trimStart().startsWith('#')) {
                    return '<span class="cmt">' + line + '</span>';
                }
                // Simple token-based highlighting
                return line.replace(/(["'`])(?:(?!\\1|\\\\)[\\s\\S]|\\\\.)*?\\1|\\b(\\d+\\.?\\d*(?:[eE][+-]?\\d+)?)\\b|\\b([a-zA-Z_]\\w*)\\b/g,
                    function(m, q, num, word) {
                        if (q) return '<span class="str">' + m + '</span>';
                        if (num) return '<span class="num">' + m + '</span>';
                        if (word && kws.has(word)) return '<span class="kw">' + word + '</span>';
                        if (word && word[0] === word[0].toUpperCase() && word[0] !== word[0].toLowerCase() && word.length > 1)
                            return '<span class="typ">' + word + '</span>';
                        return m;
                    }
                );
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    private static func languageKeywords(_ language: SupportedLanguage) -> [String] {
        switch language {
        case .swift:
            return ["import","func","var","let","if","else","guard","return","while","for","in","switch","case","default","break","continue","class","struct","enum","protocol","extension","init","self","nil","true","false","throw","try","catch","do","async","await","some","any","private","public","static","override"]
        case .python:
            return ["def","class","if","elif","else","return","while","for","in","import","from","as","not","and","or","is","None","True","False","try","except","finally","raise","with","lambda","pass"]
        case .rust:
            return ["fn","let","mut","if","else","match","return","while","for","in","loop","break","continue","struct","enum","impl","pub","use","mod","self","true","false","async","await"]
        case .go:
            return ["package","import","func","var","const","if","else","return","for","range","switch","case","default","break","struct","interface","type","map","go","defer","true","false","nil"]
        case .kotlin:
            return ["fun","val","var","if","else","when","return","while","for","in","class","object","interface","data","null","true","false","this","super","import","package"]
        case .glsl, .metal, .hlsl:
            return ["void","uniform","varying","in","out","return","if","else","for","while","struct","const","fragment","vertex","kernel","true","false"]
        case .cpp:
            return ["if","else","return","while","for","do","switch","case","class","struct","enum","namespace","using","public","private","virtual","template","const","static","new","delete","this","true","false","nullptr","auto","void","include","define"]
        case .typescript:
            return ["import","export","from","function","var","let","const","if","else","return","while","for","class","new","this","null","undefined","true","false","async","await","interface","type","enum"]
        case .javascript, .react:
            return ["import","export","from","function","var","let","const","if","else","return","while","for","class","new","this","null","undefined","true","false","async","await","typeof"]
        case .css:
            return ["display","position","margin","padding","color","background","border","font","width","height","flex","grid"]
        case .html:
            return ["html","head","body","div","span","script","style","link","meta","title","class","id","src","href"]
        case .json, .unknown:
            return []
        }
    }

    private static func jsonStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func jsonArrayLiteral(_ items: [String]) -> String {
        let inner = items.map { "\"\($0)\"" }.joined(separator: ",")
        return "[\(inner)]"
    }
}

// MARK: - WebPreviewView

#if canImport(AppKit)
private struct CardWebPreviewView: NSViewRepresentable {
    let code: String
    let language: SupportedLanguage
    var isDark: Bool = true
    var compact: Bool = false

    func makeNSView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.currentCode = ""
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload if code or language actually changed
        let key = "\(language.rawValue)|\(isDark)|\(compact)|\(code)"
        guard key != context.coordinator.currentCode else { return }
        context.coordinator.currentCode = key

        let htmlContent = CardPreviewHTMLBuilder.html(
            for: code,
            language: language,
            isDark: isDark,
            compact: compact
        )
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var currentCode: String = ""
    }
}
#else
private struct CardWebPreviewView: View {
    let code: String
    let language: SupportedLanguage
    var isDark: Bool = true
    var compact: Bool = false

    var body: some View {
        Text("Preview not supported on this platform")
    }
}
#endif
