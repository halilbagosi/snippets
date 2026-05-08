import SwiftUI
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
                    let mediaCount = orderedMediaItems.count
                    if mediaCount == 1, let media = primaryMedia {
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
                    VStack(alignment: .leading, spacing: 0) {
                        Text(snippet.code)
                            .font(Mono.font(size: 10))
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(10)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(theme.canvasDeep)
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
