import SwiftUI
import AVKit
#if canImport(AppKit)
import AppKit
#endif

struct SnippetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let snippet: Snippet
    var isSelected: Bool = false
    var inTrashView: Bool = false
    var isSelectionMode: Bool = false
    var onRestore: (() -> Void)? = nil
    var onPermanentDelete: (() -> Void)? = nil

    @State private var didCopy: Bool = false
    @State private var copyResetTask: Task<Void, Never>? = nil
    @State private var isHovered: Bool = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var cardSize: CGSize = .zero
    @State private var didAppear: Bool = false
    @State private var isShowingActionDialog: Bool = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter
    }()

    private var language: SupportedLanguage {
        SupportedLanguage(rawValue: snippet.language) ?? .unknown
    }

    private var primaryMedia: MediaItem? {
        snippet.mediaItems.sorted { $0.addedAt < $1.addedAt }.first
    }

    private var orderedMediaItems: [MediaItem] {
        snippet.mediaItems.sorted { $0.addedAt < $1.addedAt }
    }

    private var hoverCenter: CGPoint {
        CGPoint(x: max(cardSize.width, 1) * 0.5, y: max(cardSize.height, 1) * 0.5)
    }

    private var hoverUnitPoint: UnitPoint {
        guard cardSize.width > 0, cardSize.height > 0 else { return .center }
        return UnitPoint(
            x: min(max(hoverLocation.x / cardSize.width, 0), 1),
            y: min(max(hoverLocation.y / cardSize.height, 0), 1)
        )
    }

    private var hoverVector: CGVector {
        guard cardSize.width > 0, cardSize.height > 0 else { return .zero }
        return CGVector(
            dx: min(max((hoverLocation.x / cardSize.width - 0.5) * 2, -1), 1),
            dy: min(max((hoverLocation.y / cardSize.height - 0.5) * 2, -1), 1)
        )
    }

    private func performCopy() {
        Clipboard.copy(snippet.code)
        snippet.copyCount += 1
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
        let effectiveIsHovered = isSelectionMode ? false : isHovered
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
                            .foregroundStyle(theme.text.opacity(0.72))
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
            .overlay {
                CardPreviewShaderOverlay(
                    accent: languageAccent,
                    isActive: effectiveIsHovered,
                    hoverPoint: hoverUnitPoint,
                    colorScheme: colorScheme
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(effectiveIsHovered ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: effectiveIsHovered)
                .allowsHitTesting(false)
            }
            .opacity(didAppear ? 1 : 0)
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
                if inTrashView {
                    let days = snippet.daysUntilPermanentDeletion
                    let deletionBadgeColor = days <= 3
                        ? (colorScheme == .dark ? Color.red : Color(red: 0.68, green: 0.05, blue: 0.06))
                        : (colorScheme == .dark ? Color.orange.opacity(0.82) : Color(red: 0.72, green: 0.29, blue: 0.0))
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(Mono.font(size: 10, weight: .semibold))
                        Text("\(days) day\(days == 1 ? "" : "s") remaining")
                            .font(Mono.font(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(deletionBadgeColor)
                } else {
                    Text("Created at: \(Self.dateFormatter.string(from: snippet.createdAt))")
                        .font(Mono.font(size: 10))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surface.opacity(colorScheme == .dark ? 0.4 : 0.3))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(colorScheme == .dark ? 0.08 : 0.24),
                                    theme.surface.opacity(colorScheme == .dark ? 0.58 : 0.42),
                                    languageAccent.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(languageAccent.opacity(colorScheme == .dark ? 0.13 : 0.09))
                        .opacity(isHovered ? 1 : 0)
                        .animation(.easeOut(duration: 0.12), value: isHovered)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? languageAccent.opacity(0.85) : .white.opacity(colorScheme == .dark ? 0.14 : 0.40),
                    lineWidth: isSelected ? 1.35 : 1
                )
                .shadow(
                    color: languageAccent.opacity(effectiveIsHovered ? (colorScheme == .dark ? 0.56 : 0.35) : 0),
                    radius: isHovered ? 18 : 0
                )
        }
        .overlay {
            CardHoverShaderOverlay(
                accent: languageAccent,
                isActive: effectiveIsHovered,
                hoverPoint: hoverUnitPoint,
                hoverVector: hoverVector,
                colorScheme: colorScheme
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(effectiveIsHovered ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: effectiveIsHovered)
            .allowsHitTesting(false)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        cardSize = proxy.size
                        hoverLocation = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        cardSize = newSize
                        if !isHovered {
                            hoverLocation = CGPoint(x: newSize.width * 0.5, y: newSize.height * 0.5)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(effectiveIsHovered ? 1.01 : 1.0)
        .rotation3DEffect(
            .degrees(isHovered ? -Double(hoverVector.dy) * 5.5 : 0),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.72
        )
        .rotation3DEffect(
            .degrees(isHovered ? Double(hoverVector.dx) * 6.5 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.72
        )
        .offset(
            x: isHovered ? hoverVector.dx * 3.5 : 0,
            y: isHovered ? hoverVector.dy * 2.5 : 0
        )
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 10)
        .shadow(
            color: .black.opacity(colorScheme == .dark ? (effectiveIsHovered ? 0.32 : 0.22) : (effectiveIsHovered ? 0.09 : 0.06)),
            radius: effectiveIsHovered ? 24 : 18,
            x: 0,
            y: effectiveIsHovered ? 12 : 8
        )
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                didAppear = true
            }
        }
        .onContinuousHover { phase in
            guard !isSelectionMode else { return }
            switch phase {
            case .active(let location):
                hoverLocation = CGPoint(
                    x: min(max(location.x, 0), max(cardSize.width, 1)),
                    y: min(max(location.y, 0), max(cardSize.height, 1))
                )
                if !isHovered {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isHovered = true
                    }
                }
            case .ended:
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    isHovered = false
                    hoverLocation = hoverCenter
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: isHovered)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.74), value: hoverLocation)
        .onTapGesture(count: 2) {
            if inTrashView {
                isShowingActionDialog = true
            }
        }
        .confirmationDialog("Snippet", isPresented: $isShowingActionDialog, titleVisibility: .visible) {
            Button("Put back") { onRestore?() }
            Button("Delete snippet", role: .destructive) { onPermanentDelete?() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct CardHoverShaderOverlay: View {
    let accent: Color
    let isActive: Bool
    let hoverPoint: UnitPoint
    let hoverVector: CGVector
    let colorScheme: ColorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let x = min(max(hoverPoint.x + hoverVector.dx * 0.04, 0), 1)
            let y = min(max(hoverPoint.y + hoverVector.dy * 0.04, 0), 1)
            let shimmer = 0.5 + 0.5 * sin(elapsed * 1.6)

            ZStack {
                LinearGradient(
                    colors: [
                        .white.opacity(isActive ? 0.07 : 0.05),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        .white.opacity(isActive ? 0.09 : 0.0),
                        accent.opacity(isActive ? (colorScheme == .dark ? 0.07 : 0.045) : 0.0),
                        .clear
                    ],
                    center: UnitPoint(x: x, y: y),
                    startRadius: 6,
                    endRadius: isActive ? 92 + shimmer * 14 : 1
                )
                .blur(radius: 18)
                .blendMode(colorScheme == .dark ? .plusLighter : .screen)

                LinearGradient(
                    colors: [
                        .clear,
                        accent.opacity(isActive ? 0.025 + shimmer * 0.012 : 0),
                        .white.opacity(isActive ? 0.025 : 0),
                        .clear
                    ],
                    startPoint: UnitPoint(x: max(0, x - 0.18), y: max(0, y - 0.24)),
                    endPoint: UnitPoint(x: min(1, x + 0.18), y: min(1, y + 0.24))
                )
                .blur(radius: 24)
                .opacity(isActive ? 0.72 : 0)
            }
        }
    }
}

private struct CardPreviewShaderOverlay: View {
    let accent: Color
    let isActive: Bool
    let hoverPoint: UnitPoint
    let colorScheme: ColorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let sweep = isActive ? (elapsed.truncatingRemainder(dividingBy: 2.4) / 2.4) : 0.5
            let shiftedX = min(max(hoverPoint.x * 0.88 + sweep * 0.12, 0), 1)

            ZStack {
                RadialGradient(
                    colors: [
                        accent.opacity(isActive ? (colorScheme == .dark ? 0.065 : 0.04) : 0),
                        .clear
                    ],
                    center: UnitPoint(x: hoverPoint.x, y: hoverPoint.y),
                    startRadius: 10,
                    endRadius: 82
                )
                .blur(radius: 16)

                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(isActive ? 0.035 : 0),
                        accent.opacity(isActive ? 0.03 : 0),
                        .clear
                    ],
                    startPoint: UnitPoint(x: shiftedX - 0.12, y: 0.12),
                    endPoint: UnitPoint(x: shiftedX + 0.12, y: 0.88)
                )
                .blur(radius: 22)
            }
            .opacity(isActive ? 0.68 : 0)
            .blendMode(colorScheme == .dark ? .plusLighter : .screen)
            .allowsHitTesting(false)
        }
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
