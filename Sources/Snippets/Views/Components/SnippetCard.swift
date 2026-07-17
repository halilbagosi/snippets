import SwiftUI
import AVKit
#if canImport(AppKit)
import AppKit
#endif
import SwiftData

struct SnippetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppearanceSettings.self) private var appearanceSettings
    let snippet: Snippet
    var isSelected: Bool = false
    var inTrashView: Bool = false
    var isSelectionMode: Bool = false
    var onRestore: (() -> Void)? = nil
    var onPermanentDelete: (() -> Void)? = nil
    /// When > 0, renders an inline "N linked" chip in the footer row — the
    /// gallery's toggle for the connected-snippet stack behind this card.
    var linkedCount: Int = 0
    var isStackExpanded: Bool = false
    var onToggleStack: (() -> Void)? = nil
    /// Marks a card revealed from another card's connected-snippet stack;
    /// renders a "connected" chip on the title row.
    var isConnected: Bool = false

    @State private var didCopy: Bool = false
    @State private var copyResetTask: Task<Void, Never>? = nil
    @State private var isHovered: Bool = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var cardSize: CGSize = .zero
    @State private var didAppear: Bool = false
    @State private var isShowingActionDialog: Bool = false

    private var language: SupportedLanguage {
        SupportedLanguage(rawValue: snippet.language) ?? .unknown
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            didCopy = true
        }
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if !Task.isCancelled {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    didCopy = false
                }
            }
        }
    }

    @ViewBuilder
    private func copyButton(theme: Theme, languageAccent: Color) -> some View {
        let fgColor = colorScheme == .dark ? .white : languageAccent.blended(with: .black, ratio: 0.45)
        let strokeColor = languageAccent.saturation(3.0).brightness(colorScheme == .dark ? 0.22 : -0.15).opacity(0.50)
        let fillColor = languageAccent.saturation(2.5).brightness(0.15).opacity(colorScheme == .dark ? 0.20 : 0.12)
        
        Button(action: performCopy) {
            HStack(spacing: 5) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .symbolRenderingMode(.hierarchical)
                    .font(Mono.font(size: 9, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(didCopy ? "copied" : "copy")
                    .font(Mono.font(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(didCopy ? (colorScheme == .dark ? .white : languageAccent) : fgColor)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(didCopy ? languageAccent.opacity(colorScheme == .dark ? 0.40 : 0.25) : fillColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(didCopy ? languageAccent.opacity(0.8) : strokeColor, lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy snippet code")
        .accessibilityLabel(didCopy ? "Copied" : "Copy code")
    }

    /// Footer chip toggling the connected-snippet stack. Same metrics and
    /// color recipe as `copyButton` so the footer chips read as one family.
    @ViewBuilder
    private func linkedChip(theme: Theme, languageAccent: Color) -> some View {
        let fgColor = colorScheme == .dark ? .white : languageAccent.blended(with: .black, ratio: 0.45)
        let strokeColor = languageAccent.saturation(3.0).brightness(colorScheme == .dark ? 0.22 : -0.15).opacity(0.50)
        let fillColor = languageAccent.saturation(2.5).brightness(0.15).opacity(colorScheme == .dark ? 0.20 : 0.12)

        Button { onToggleStack?() } label: {
            HStack(spacing: 5) {
                Image(systemName: isStackExpanded ? "chevron.up" : "square.3.layers.3d.down.right")
                    .symbolRenderingMode(.hierarchical)
                    .font(Mono.font(size: 9, weight: .semibold))
                Text(isStackExpanded ? "hide" : "\(linkedCount) linked")
                    .font(Mono.font(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(fgColor)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isStackExpanded ? languageAccent.opacity(colorScheme == .dark ? 0.40 : 0.25) : fillColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isStackExpanded ? languageAccent.opacity(0.8) : strokeColor, lineWidth: 1)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isStackExpanded ? "Hide connected snippets" : "Show the snippets stacked behind this one")
        .accessibilityLabel("\(linkedCount) connected snippets")
    }

    /// Title-row chip marking a card revealed from a connected-snippet stack.
    @ViewBuilder
    private func connectedChip(theme: Theme) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
                .font(Mono.font(size: 9, weight: .semibold))
            Text("connected")
                .font(Mono.font(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(theme.accent)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme.accent.opacity(colorScheme == .dark ? 0.20 : 0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(theme.accent.opacity(0.5), lineWidth: 1)
                }
        }
        .accessibilityLabel("Connected snippet")
    }

    private var formattedDate: String {
        Self.dateFormatter.string(from: snippet.createdAt)
    }

    @MainActor
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        let theme = Theme.current(colorScheme)
        let languageAccent = theme.accentColor(for: language).saturation(10)
        let effectiveIsHovered = (isSelectionMode || appearanceSettings.disableHoverEffects) ? false : isHovered
        let mediaItems = snippet.mediaItems.sorted { $0.addedAt < $1.addedAt }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                        .font(Sans.font(size: 15, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)

                    Spacer()

                    if isConnected {
                        connectedChip(theme: theme)
                    }
                }

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
                if !mediaItems.isEmpty {
                    let mediaCount = mediaItems.count
                    if mediaCount == 1, let media = mediaItems.first {
                        GeometryReader { geo in
                            GalleryAttachmentPreview(
                                item: media,
                                contentSize: CGSize(width: geo.size.width, height: geo.size.height),
                                innerPadding: GalleryCardAttachmentLayout.innerPadding,
                                cornerRadius: GalleryCardAttachmentLayout.singleCornerRadius
                            )
                        }
                    } else {
                        CardMediaGrid(items: mediaItems)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(snippet.code)
                            .font(Mono.font(size: 10))
                            .foregroundStyle(theme.text.opacity(0.72))
                            .lineLimit(10)
                            .padding(DSToken.Spacing.sm)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(theme.canvasDeep)
                }
            }
            // Preview area is locked to 16:9 so image/video attachments keep a
            // familiar aspect; the card grows slightly taller with its width.
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            }
            .overlay {
                if effectiveIsHovered {
                    CardPreviewShaderOverlay(
                        accent: languageAccent,
                        isActive: true,
                        hoverPoint: hoverUnitPoint,
                        colorScheme: colorScheme
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .opacity(didAppear ? 1 : 0)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 8) {
                LanguageBadge(language: language, compact: true)
                if !mediaItems.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                        Text("\(mediaItems.count)")
                    }
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                }
                copyButton(theme: theme, languageAccent: languageAccent)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        snippet.isFavorite.toggle()
                    }
                } label: {
                    Image(systemName: snippet.isFavorite ? "star.fill" : "star")
                        .font(Mono.font(size: 14, weight: .semibold))
                        .foregroundStyle(
                            snippet.isFavorite
                                ? Color(red: 1.0, green: 0.80, blue: 0.20)
                                : theme.textFaint
                        )
                        .padding(DSToken.Spacing.xxs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(snippet.isFavorite ? "Remove from favorites" : "Add to favorites")
                if linkedCount > 0 {
                    linkedChip(theme: theme, languageAccent: languageAccent)
                }
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
                    Text("\(formattedDate)")
                        .font(Mono.font(size: 10, weight: .medium))
                        .foregroundStyle(theme.textFaint)
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
                            // Dark mode only adds a soft top-left highlight that
                            // fades out — never re-darkens the center — so the
                            // card reads as a uniform surface like the light one.
                            // (The old middle stop was dark `surface`, which
                            // stacked into a diagonal shadow band in dark mode.)
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [
                                        .white.opacity(0.10),
                                        .white.opacity(0.03),
                                        languageAccent.opacity(0.03)
                                      ]
                                    : [
                                        .white.opacity(0.24),
                                        theme.surface.opacity(0.42),
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
                .overlay {
                    if effectiveIsHovered {
                        CardHoverShaderOverlay(
                            accent: languageAccent,
                            isActive: true,
                            hoverPoint: hoverUnitPoint,
                            hoverVector: hoverVector,
                            colorScheme: colorScheme
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? languageAccent.opacity(0.85) : (colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.08)),
                    lineWidth: isSelected ? 1.35 : 1
                )
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
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .rotation3DEffect(
            .degrees(effectiveIsHovered ? -Double(hoverVector.dy) * 1.5 : 0),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.72
        )
        .rotation3DEffect(
            .degrees(effectiveIsHovered ? Double(hoverVector.dx) * 2.0 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.72
        )
        .offset(
            x: effectiveIsHovered ? hoverVector.dx * 1.5 : 0,
            y: effectiveIsHovered ? hoverVector.dy * 1.0 : 0
        )
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 10)
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
        .trashDoubleTap(inTrash: inTrashView) {
            isShowingActionDialog = true
        }
        .confirmationDialog("Snippet", isPresented: $isShowingActionDialog, titleVisibility: .visible) {
            Button("Put back") { onRestore?() }
            Button("Delete snippet", role: .destructive) { onPermanentDelete?() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct CardHoverShaderOverlay: View {
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
                        .white.opacity(isActive ? 0.04 : 0.0),
                        accent.opacity(isActive ? (colorScheme == .dark ? 0.03 : 0.02) : 0.0),
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
                        accent.opacity(isActive ? 0.01 + shimmer * 0.005 : 0),
                        .white.opacity(isActive ? 0.01 : 0),
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

struct CardPreviewShaderOverlay: View {
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
                    .padding(DSToken.Spacing.xs)
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
    @State private var imageLoadTask: Task<Void, Never>? = nil
    #endif

    var body: some View {
        let theme = Theme.current(colorScheme)
        ZStack {
            theme.inset
            #if canImport(AppKit)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    // Fit so a portrait attachment shows whole, centered inside
                    // its (bounded) preview slot; a landscape attachment whose
                    // slot matches its aspect fills exactly with no bars.
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
        .onAppear(perform: loadImage)
        .onDisappear {
            #if canImport(AppKit)
            imageLoadTask?.cancel()
            #endif
        }
    }

    private func loadImage() {
        #if canImport(AppKit)
        guard image == nil else { return }
        imageLoadTask?.cancel()
        let url = MediaManager.resolvedURL(for: item.fileName)
        imageLoadTask = Task { @MainActor in
            let thumbnail = await CardImageFileLoader.thumbnail(from: url)
            guard !Task.isCancelled else { return }
            image = thumbnail.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
        #endif
    }
}

private struct CardVideoPreview: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            LoopingVideoPlayerView(fileName: item.fileName, videoGravity: .resizeAspect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if canImport(AppKit)
private enum CardImageFileLoader {
    /// Card preview slots top out around 360pt wide, so 800px covers Retina
    /// without decoding the full-resolution attachment into memory.
    private static let maxThumbnailPixelSize: CGFloat = 800

    static func thumbnail(from url: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) else { return nil }
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxThumbnailPixelSize
            ] as CFDictionary
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        }.value
    }
}
#endif

private extension View {
    @ViewBuilder
    func trashDoubleTap(inTrash: Bool, action: @escaping () -> Void) -> some View {
        if inTrash {
            self.onTapGesture(count: 2, perform: action)
        } else {
            self
        }
    }
}
