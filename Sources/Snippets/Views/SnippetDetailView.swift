import SwiftUI
import SwiftData
import AVKit
#if canImport(AppKit)
import AppKit
#endif

struct SnippetDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    let snippet: Snippet
    /// Whether a previously-viewed snippet exists to navigate back to; drives
    /// the back button's visibility.
    var canGoBack: Bool = false
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    var onOpenSnippet: (Snippet) -> Void = { _ in }
    var onBack: () -> Void = {}

    @State private var didCopy: Bool = false
    @State private var lightboxIndex: Int? = nil
    @State private var showPreview: Bool = false
    /// Rendered height of the code area, so the preview can track it.
    @State private var codeAreaHeight: CGFloat = 0
    @State private var paramOverrides: [String: PreviewParamValue] = [:]

    private var theme: Theme { Theme.current(colorScheme) }

    private var language: SupportedLanguage {
        SupportedLanguage(rawValue: snippet.language) ?? .unknown
    }

    private var orderedMediaItems: [MediaItem] {
        snippet.mediaItems.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .video
            }
            return lhs.addedAt < rhs.addedAt
        }
    }
    private let actionBarButtonHorizontalPadding: CGFloat = 14
    /// Fixed label band so Copy / Edit / Delete share the same height; width follows label + horizontal padding.
    private let actionBarButtonLabelHeight: CGFloat = 34

    private var showMediaLightbox: Binding<Bool> {
        Binding(
            get: { lightboxIndex != nil },
            set: { if !$0 { lightboxIndex = nil } }
        )
    }

    var body: some View {
        let mediaItems = orderedMediaItems
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock
                    if !snippet.snippetDescription.isEmpty {
                        descriptionBlock
                    }
                    if !mediaItems.isEmpty {
                        mediaSection(mediaItems)
                    }
                    codeBlock
                    metadata
                    if !snippet.dependencies.isEmpty {
                        connectedCode
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 32)
                // The back button is overlaid at the top leading corner, right
                // where the title block starts, so the content has to start
                // below it when it is there: 14 top inset + 30 button + 12 gap.
                // The close button never needs this — it sits opposite the
                // title, not on top of it.
                .padding(.top, canGoBack ? 56 : 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.text)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
                    .liquidGlassSurface(
                        in: Circle(),
                        shadowRadius: 12,
                        shadowY: 6
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.trailing, 14)
            .accessibilityLabel("Close snippet")

            if canGoBack {
                BackButton(
                    action: onBack,
                    accessibilityLabel: "Back to previous snippet",
                    style: .circle
                )
                    .padding(.top, 14)
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // 0.94 matches the scale the modals and move sheet enter
                    // at; 0.8 read as a pop next to the rest of the chrome.
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }

        .sheet(isPresented: showMediaLightbox, onDismiss: { lightboxIndex = nil }) {
            if let index = lightboxIndex {
                MediaAttachmentLightbox(items: orderedMediaItems, initialIndex: index)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("//")
                            .font(Mono.font(size: 13, weight: .semibold))
                            .foregroundStyle(theme.comment)
                        Text("snippet")
                            .font(Mono.font(size: 13, weight: .semibold))
                            .foregroundStyle(theme.comment)
                    }
                    Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                        .font(Sans.font(size: 28, weight: .bold))
                        .foregroundStyle(theme.text)
                }
                
                Spacer(minLength: 16)
            }
            
            HStack(spacing: 10) {
                LanguageBadge(language: language)
                
                if let firstCollection = snippet.collections.min(by: { $0.name < $1.name }) {
                    let collectionColor = Color(hex: firstCollection.colorHex) ?? theme.accent
                    let fillOpacity = colorScheme == .dark ? 0.20 : 0.12
                    HStack(spacing: 5) {
                        Image(systemName: firstCollection.displayIconName)
                            .symbolRenderingMode(.hierarchical)
                            .font(Mono.font(size: 10, weight: .semibold))
                        Text(firstCollection.name.lowercased())
                            .font(Mono.font(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .foregroundStyle(colorScheme == .dark ? .white : collectionColor.blended(with: .black, ratio: 0.45))
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(collectionColor.opacity(fillOpacity))
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(collectionColor.opacity(0.50), lineWidth: 1)
                            }
                    }
                }
                
                Spacer(minLength: 16)

                actionBar
            }

            if !snippet.dependencies.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("uses")
                        .font(Mono.font(size: 11, weight: .semibold))
                        .foregroundStyle(theme.comment)
                    FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(snippet.dependencies) { dependency in
                            FilterTag(
                                label: dependency.title.lowercased(),
                                icon: "link",
                                accent: theme.textMuted,
                                isSelected: false
                            ) {
                                onOpenSnippet(dependency)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            FilterTag(
                label: didCopy ? "copied" : "copy",
                icon: didCopy ? "checkmark" : "doc.on.doc",
                accent: didCopy ? .blue : theme.textMuted,
                isSelected: didCopy
            ) {
                Clipboard.copy(snippet.code)
                snippet.copyCount += 1
                didCopy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    didCopy = false
                }
            }

            FilterTag(
                label: "edit",
                icon: "pencil",
                accent: theme.textMuted,
                isSelected: false
            ) {
                onEdit()
            }

            FilterTag(
                label: snippet.isFavorite ? "favorited" : "favorite",
                icon: snippet.isFavorite ? "star.fill" : "star",
                accent: snippet.isFavorite ? Color(red: 1.0, green: 0.80, blue: 0.20) : theme.textMuted,
                isSelected: snippet.isFavorite
            ) {
                snippet.isFavorite.toggle()
            }

            FilterTag(
                label: "delete",
                icon: "trash",
                accent: .red,
                selectedFillAccent: .red,
                isSelected: true
            ) {
                onDelete()
            }
        }
    }

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("description")
            Text(snippet.snippetDescription)
                .font(Sans.font(size: 14))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DSToken.Spacing.md)
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    shadowRadius: 6,
                    shadowY: 3
                )
        }
    }

    /// The preview occupies exactly the code window's footprint, so toggling
    /// between source and preview swaps the contents without resizing the pane.
    /// Falls back to the code view's own minimum height until it has been
    /// measured (the source view is shown first, so this is only the very
    /// first layout pass).
    private var previewHeight: CGFloat {
        codeAreaHeight > 0 ? codeAreaHeight : Self.codeMinHeight
    }

    private static let codeMinHeight: CGFloat = 240
    private static let codeMaxHeight: CGFloat = 520

    /// Base colour the preview panel paints before its content is on screen.
    ///
    /// The source panel is deliberately transparent — `HighlightedCodeView`
    /// draws no background, so the panel's background *is* the Liquid Glass
    /// behind it. Without an opaque backdrop of its own, that bright glass
    /// stayed visible for the whole toggle animation and compile, which is the
    /// white flash before a (usually dark) preview appears. `canvasDeep` is
    /// near-white in light mode, so a shader canvas has to be black rather than
    /// simply "the deep canvas colour".
    private var previewBackdrop: Color {
        switch language.previewKind {
        case .metal: .black // matches the shader canvas and the MTKView clear colour
        case .web, .swiftUI, .none: theme.canvasDeep
        }
    }

    private var codeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            let resolution = showPreview ? SnippetLinker.resolve(entry: snippet) : nil
            // Once configurations exist the dropdown stays available in source
            // view too, so switching between them doesn't require flipping to
            // the preview first — which needs a resolution the preview-only
            // binding above doesn't provide.
            let configResolution = resolution
                ?? (snippet.paramConfigs.isEmpty ? nil : SnippetLinker.resolve(entry: snippet))
            // Detection is by far the most expensive thing in this body — it
            // runs regexes over the whole linked source — and this body is
            // re-evaluated on every frame of a parameter-slider drag. Derive it
            // once here and hand it to everything below rather than letting the
            // config control, the parameter panel and the preview each ask
            // again.
            let detected = configResolution.map(detectedParams) ?? []
            HStack(spacing: 8) {
                SectionHeader(showPreview ? "preview" : "source")
                if let resolution, !resolution.excluded.isEmpty {
                    Text("\(resolution.excluded.count) connected not previewable")
                        .font(Mono.font(size: 10))
                        .foregroundStyle(theme.textMuted)
                }
                Spacer(minLength: 16)
                if let configResolution,
                   !snippet.paramConfigs.isEmpty || !detected.isEmpty {
                    PreviewConfigControl(
                        configs: snippet.paramConfigs,
                        activeID: snippet.activeParamConfigID,
                        isDirty: !paramOverrides.isEmpty,
                        accent: Color(hex: language.accentHex) ?? theme.accent,
                        theme: theme,
                        onSave: { saveConfig(named: $0, resolution: configResolution) },
                        onUpdate: { updateConfig(id: $0, resolution: configResolution) },
                        onSelect: { selectConfig(id: $0, resolution: configResolution) },
                        onDelete: { deleteConfig(id: $0) }
                    )
                }
                if language.previewKind != nil {
                    FilterTag(
                        label: showPreview ? "code" : "preview",
                        icon: showPreview ? "chevron.left.forwardslash.chevron.right" : "play.rectangle",
                        accent: theme.accent,
                        isSelected: showPreview
                    ) {
                        withAnimation(DSToken.Motion.reveal) {
                            showPreview.toggle()
                        }
                    }
                }
            }
            Group {
                if let resolution, language.previewKind != nil {
                    SnippetPreviewView(
                        resolution: resolution, language: language, theme: theme,
                        params: detected.map(\.param),
                        snippetID: snippet.uuid,
                        paramOverrides: $paramOverrides
                    )
                    .frame(height: previewHeight)
                    // Instant swap, never a cross-fade. Every preview engine is
                    // an NSViewRepresentable, and fading one in forces SwiftUI
                    // to rasterise the AppKit-hosted subtree to apply group
                    // opacity — that snapshot composites as a white frame over
                    // everything, including the backdrop below, which is the
                    // white flash on toggling. See `previewBackdrop`.
                    .transition(.identity)
                } else {
                    HighlightedCodeView(
                        code: snippet.code,
                        language: language,
                        theme: theme,
                        fontSize: 13
                    )
                    .frame(minHeight: Self.codeMinHeight, maxHeight: Self.codeMaxHeight)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        codeAreaHeight = height
                    }
                    // Same reason as the preview branch: HighlightedCodeView is
                    // an NSScrollView, so fading it out rasterises it too.
                    .transition(.identity)
                }
            }
            .background {
                // The backdrop must be opaque from the very first frame of the
                // toggle: letting it fade in would reopen the exact gap it
                // exists to close, since the content fading in over it is
                // transparent for the length of the animation. `.identity`
                // plus a nil animation scoped to just this layer pins it,
                // without touching the content's own cross-fade.
                Group {
                    if showPreview, language.previewKind != nil {
                        previewBackdrop.transition(.identity)
                    }
                }
                .animation(nil, value: showPreview)
            }
            // A *well*, not a surface: `liquidGlassSurface` composites the glass
            // backdrop and a full-area white fill (16% in light mode) over its
            // content. With no preview frame yet drawn there is nothing to
            // dominate that stack, so the panel reads as a bright rectangle
            // until the engine's first frame lands — the white flash before the
            // preview starts. A well puts the same material strictly behind,
            // leaving only the hairline rim on top.
            .liquidGlassWell(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                tint: (Color(hex: language.accentHex) ?? theme.accent).opacity(0.08),
                shadowRadius: 10,
                shadowY: 5
            )

            // Parameter controls are their own collapsible panel below the
            // preview, not stacked inside its fixed-height frame — so expanding
            // them grows this column downward instead of shrinking the preview.
            if resolution != nil, showPreview, language.previewKind != nil {
                let params = detected.map(\.param)
                if !params.isEmpty {
                    PreviewParamControls(params: params, overrides: $paramOverrides, theme: theme)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .liquidGlassSurface(
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                            tint: (Color(hex: language.accentHex) ?? theme.accent).opacity(0.08),
                            shadowRadius: 6,
                            shadowY: 3
                        )
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: snippet.persistentModelID) {
            showPreview = false
            codeAreaHeight = 0
            paramOverrides = [:]
        }
        // Editing the source (or applying a config, which rewrites it) drops
        // stale overrides; dragging a slider changes overrides only, not the
        // code, so it never triggers this and dirty state survives.
        .onChange(of: snippet.code) {
            paramOverrides = [:]
        }
    }

    /// Params the previewed source currently declares.
    ///
    /// A connected usage snippet sets props explicitly on the component it
    /// mounts, and those beat the component's defaults in the preview — so
    /// where one exists it, not the entry, states the parameter's current
    /// value. Reporting the entry's default here would show the controls one
    /// value while the preview rendered another.
    private func detectedParams(_ resolution: SnippetLinker.Resolution) -> [DetectedParam] {
        let declared = PreviewParamDetector.detect(for: language, resolution: resolution)
        guard let usage = usageSnippet(resolution) else { return declared }
        return PreviewParamDetector.merging(
            usage: PreviewParamDetector.detectJSXUsage(in: usage.code), into: declared
        )
    }

    /// The connected snippet whose JSX mounts the entry component, if any.
    /// Matched against the resolved sources so it is the same snippet the
    /// preview builder routes into the mount position.
    private func usageSnippet(_ resolution: SnippetLinker.Resolution) -> Snippet? {
        guard language.previewKind == .web(.react) else { return nil }
        let usageCode = Set(
            resolution.sources.dropLast()
                .filter { WebPreviewHTMLBuilder.isJSXUsage($0.code) }
                .map(\.code)
        )
        guard !usageCode.isEmpty else { return nil }
        return snippet.dependencies.first { usageCode.contains($0.code) }
    }

    /// Rewrites the source so it declares `values`, then clears the live
    /// overrides — the code now *is* the config, so nothing is overridden.
    ///
    /// Values a usage snippet pins are written *there*: rewriting only the
    /// component's defaults left them shadowed, so a saved config appeared to
    /// do nothing. Params the usage does not mention still go to the entry.
    private func applyValues(
        _ values: [String: PreviewParamValue], resolution: SnippetLinker.Resolution
    ) {
        if let usage = usageSnippet(resolution) {
            let usageParams = PreviewParamDetector.detectJSXUsage(in: usage.code)
            let pinned = Set(usageParams.map(\.param.name))
            if !pinned.isEmpty {
                usage.code = PreviewParamWriter.apply(
                    values.filter { pinned.contains($0.key) }, to: usage.code, params: usageParams
                )
                usage.updatedAt = .now
            }
            let rest = values.filter { !pinned.contains($0.key) }
            if !rest.isEmpty {
                snippet.code = PreviewParamWriter.apply(
                    rest, to: snippet.code,
                    params: PreviewParamDetector.detect(for: language, resolution: resolution)
                )
            }
            snippet.updatedAt = .now
            paramOverrides = [:]
            return
        }
        snippet.code = PreviewParamWriter.apply(
            values, to: snippet.code,
            params: PreviewParamDetector.detect(for: language, resolution: resolution)
        )
        snippet.updatedAt = .now
        paramOverrides = [:]
    }

    private func saveConfig(named name: String, resolution: SnippetLinker.Resolution) {
        let declared = detectedParams(resolution).map(\.param)
        snippet.paramConfigs = PreviewParamConfigStore.saving(
            current: paramOverrides, declared: declared, named: name, into: snippet.paramConfigs
        )
        if let saved = snippet.paramConfigs.last {
            snippet.activeParamConfigID = saved.id
            applyValues(saved.values, resolution: resolution)
        }
    }

    private func updateConfig(id: UUID, resolution: SnippetLinker.Resolution) {
        let declared = detectedParams(resolution).map(\.param)
        snippet.paramConfigs = PreviewParamConfigStore.updating(
            id: id, to: paramOverrides, declared: declared, in: snippet.paramConfigs
        )
        if let updated = snippet.paramConfigs.first(where: { $0.id == id }) {
            applyValues(updated.values, resolution: resolution)
        }
    }

    private func selectConfig(id: UUID, resolution: SnippetLinker.Resolution) {
        guard let config = snippet.paramConfigs.first(where: { $0.id == id }) else { return }
        snippet.activeParamConfigID = id
        let declared = detectedParams(resolution).map(\.param)
        applyValues(
            PreviewParamConfigStore.resolvedValues(for: config, declared: declared),
            resolution: resolution
        )
    }

    private func deleteConfig(id: UUID) {
        snippet.paramConfigs = PreviewParamConfigStore.deleting(id: id, from: snippet.paramConfigs)
        if snippet.activeParamConfigID == id {
            snippet.activeParamConfigID = snippet.paramConfigs.first(where: \.isDefault)?.id
        }
    }

    private func mediaSection(_ mediaItems: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("attachments") {
                Text("\(mediaItems.count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textFaint)
            }

            let layout = AttachmentStripLayout.self
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: layout.hSpacing) {
                    ForEach(Array(mediaItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            lightboxIndex = index
                        } label: {
                            MediaPreview(item: item, contentSize: layout.contentSize, innerPadding: layout.innerPadding)
                        }
                        .buttonStyle(.plain)
                        .frame(width: layout.cellWidth, height: layout.cellHeight, alignment: .center)
                        .contentShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
                        .help("View larger")
                        .accessibilityLabel("View attachment")
                    }
                }
                .padding(.horizontal, layout.trackPaddingH)
                .padding(.vertical, layout.trackPaddingV)
            }
            .frame(maxWidth: .infinity)
            .frame(height: layout.stripHeight)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                shadowRadius: 8,
                shadowY: 4
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("meta")
            HStack(spacing: 12) {
                metaPill(label: "created", value: snippet.createdAt.formatted(date: .abbreviated, time: .omitted))
                metaPill(label: "updated", value: snippet.updatedAt.formatted(date: .abbreviated, time: .omitted))
                metaPill(label: "lines", value: "\(snippet.code.split(separator: "\n").count)")
                metaPill(label: "chars", value: "\(snippet.code.count)")
                Spacer()
            }
        }
    }

    /// One syntax-highlighted "code window" per directly connected snippet,
    /// shown below the metadata. Each window mirrors the source block's chrome,
    /// scrolls its own code independently, and its header opens that snippet.
    private var connectedCode: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("connected") {
                Text("\(snippet.dependencies.count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textFaint)
            }
            ForEach(snippet.dependencies) { dependency in
                connectedCodeWindow(dependency)
            }
        }
    }

    private func connectedCodeWindow(_ dependency: Snippet) -> some View {
        let depLanguage = SupportedLanguage(rawValue: dependency.language) ?? .unknown
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                onOpenSnippet(dependency)
            } label: {
                SectionHeader(dependency.title.isEmpty ? "untitled" : dependency.title) {
                    LanguageBadge(language: depLanguage)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HighlightedCodeView(
                code: dependency.code,
                language: depLanguage,
                theme: theme,
                fontSize: 13
            )
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                tint: (Color(hex: depLanguage.accentHex) ?? theme.accent).opacity(0.08),
                shadowRadius: 10,
                shadowY: 5
            )
        }
    }

    private func metaPill(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(label):")
                .foregroundStyle(theme.comment)
            Text(value)
                .foregroundStyle(theme.text)
        }
        .font(Mono.font(size: 11, weight: .medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            shadowRadius: 4,
            shadowY: 2
        )
    }
}

private enum AttachmentStripLayout {
    static let contentSize = CGSize(width: 300, height: 200)
    static let innerPadding: CGFloat = 10
    static let cornerRadius: CGFloat = 16
    static let hSpacing: CGFloat = 16
    static let trackPaddingH: CGFloat = 16
    static let trackPaddingV: CGFloat = 16

    static var cellWidth: CGFloat { contentSize.width }
    static var cellHeight: CGFloat { contentSize.height }
    static var stripHeight: CGFloat { cellHeight + trackPaddingV * 2 }
}

private struct MediaPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: MediaItem
    var contentSize: CGSize
    var innerPadding: CGFloat

    private var innerCornerRadius: CGFloat {
        max(6, cornerRadius - innerPadding * 0.5)
    }

    private var innerSize: CGSize {
        CGSize(
            width: max(1, contentSize.width - innerPadding * 2),
            height: max(1, contentSize.height - innerPadding * 2)
        )
    }

    private let cornerRadius: CGFloat = AttachmentStripLayout.cornerRadius

    var body: some View {
        let theme = Theme.current(colorScheme)
        ZStack(alignment: .topTrailing) {
            Group {
                switch item.kind {
                case .image:
                    ImageMediaView(item: item)
                case .video:
                    // Hit-transparent so the click reaches the strip's button —
                    // the AVPlayer's NSView would otherwise swallow it.
                    VideoMediaView(item: item)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: innerSize.width, height: innerSize.height)
            .clipShape(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous))

            if item.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(DSToken.Spacing.xs)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(innerPadding + 4)
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
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.16), radius: 16, x: 0, y: 8)
        .compositingGroup()
    }
}

private struct MediaAttachmentLightbox: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let items: [MediaItem]
    @State private var index: Int

    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @State private var pinchBaseScale: CGFloat? = nil
    @State private var dragBaseOffset: CGSize? = nil
    /// Width / height of the current attachment once known, so the sheet
    /// itself goes wide for landscape media and tall for portrait.
    @State private var contentAspect: CGFloat? = nil

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 6

    init(items: [MediaItem], initialIndex: Int) {
        self.items = items
        _index = State(initialValue: min(max(initialIndex, 0), max(items.count - 1, 0)))
    }

    private var theme: Theme { Theme.current(colorScheme) }
    private var item: MediaItem { items[index] }

    var body: some View {
        ZStack {
            theme.canvas
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // Clicking the empty area around the media closes the viewer;
                // clicks on the media itself are caught by it and don't fall through.
                .onTapGesture { dismiss() }
            Group {
                switch item.kind {
                case .image:
                    LightboxImageView(
                        fileName: item.fileName,
                        zoomScale: zoomScale,
                        zoomOffset: zoomOffset,
                        onAspectResolved: { contentAspect = $0 }
                    )
                case .video:
                    LightboxVideoView(
                        fileName: item.fileName,
                        zoomScale: zoomScale,
                        zoomOffset: zoomOffset,
                        onAspectResolved: { contentAspect = $0 }
                    )
                }
            }
            // Reset the loaded content when paging to another attachment.
            .id(item.fileName)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let base = pinchBaseScale ?? zoomScale
                        pinchBaseScale = base
                        setZoom(base * value)
                    }
                    .onEnded { _ in pinchBaseScale = nil }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard zoomScale > 1 else { return }
                        let base = dragBaseOffset ?? zoomOffset
                        dragBaseOffset = base
                        zoomOffset = CGSize(
                            width: base.width + value.translation.width,
                            height: base.height + value.translation.height
                        )
                    }
                    .onEnded { _ in dragBaseOffset = nil }
            )
            .onTapGesture(count: 2) {
                withAnimation(DSToken.Motion.reveal) {
                    setZoom(zoomScale > 1 ? 1 : 2.5)
                }
            }
            .onChange(of: index) { _, _ in
                zoomScale = 1
                zoomOffset = .zero
                contentAspect = nil
            }
            // Keep the media clear of the chevrons, close button, and counter:
            // the AVPlayer's NSView paints above SwiftUI content, so any chrome
            // overlapping a video would be hidden behind it.
            .padding(.horizontal, 64)
            .padding(.top, 52)
            .padding(.bottom, 52)

            if items.count > 1 {
                HStack {
                    pagingButton(systemName: "chevron.left", key: .leftArrow, isEnabled: index > 0) {
                        index -= 1
                    }
                    Spacer()
                    pagingButton(systemName: "chevron.right", key: .rightArrow, isEnabled: index < items.count - 1) {
                        index += 1
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.text)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
                    .liquidGlassSurface(
                        in: Circle(),
                        shadowRadius: 12,
                        shadowY: 6
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(14)
            .accessibilityLabel("Close attachment viewer")
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 6) {
                zoomButton(systemName: "minus", key: "-", isEnabled: zoomScale > minZoom) {
                    withAnimation(DSToken.Motion.reveal) {
                        setZoom(zoomScale / 1.4)
                    }
                }
                Text(items.count > 1 ? "\(index + 1) / \(items.count)" : "\(Int((zoomScale * 100).rounded()))%")
                    .font(Mono.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 6)
                zoomButton(systemName: "plus", key: "=", isEnabled: zoomScale < maxZoom) {
                    withAnimation(DSToken.Motion.reveal) {
                        setZoom(zoomScale * 1.4)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassSurface(in: Capsule())
            .padding(.bottom, 14)
        }
        .frame(minWidth: 560, idealWidth: sheetSize.width, minHeight: 440, idealHeight: sheetSize.height)
        // Fitted sizing tracks the ideal size as the media's aspect ratio
        // resolves, while the flexible frame keeps the sheet user-resizable.
        .presentationSizing(.fitted)
        .animation(DSToken.Motion.reveal, value: contentAspect)
    }

    /// Sheet dimensions derived from the media's aspect ratio: the frame goes
    /// wide for landscape content and tall for portrait, so the media itself
    /// can render as large as possible inside the chrome gutters.
    private var sheetSize: CGSize {
        let aspect = contentAspect ?? 16.0 / 10.0
        let gutterWidth: CGFloat = 64 * 2
        let gutterHeight: CGFloat = 52 * 2
        let maxMediaWidth: CGFloat = 1000
        let maxMediaHeight: CGFloat = 560

        var mediaWidth = maxMediaWidth
        var mediaHeight = mediaWidth / aspect
        if mediaHeight > maxMediaHeight {
            mediaHeight = maxMediaHeight
            mediaWidth = mediaHeight * aspect
        }
        return CGSize(
            width: max(mediaWidth + gutterWidth, 560),
            height: max(mediaHeight + gutterHeight, 440)
        )
    }

    private func setZoom(_ scale: CGFloat) {
        zoomScale = min(max(scale, minZoom), maxZoom)
        if zoomScale <= 1.001 {
            zoomScale = 1
            zoomOffset = .zero
        }
    }

    private func zoomButton(
        systemName: String,
        key: KeyEquivalent,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(systemName == "plus" ? "Zoom in" : "Zoom out")
    }

    private func pagingButton(
        systemName: String,
        key: KeyEquivalent,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
                .liquidGlassSurface(
                    in: Circle(),
                    interactive: true,
                    shadowRadius: 12,
                    shadowY: 6
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .accessibilityLabel(key == .leftArrow ? "Previous attachment" : "Next attachment")
    }
}

private struct LightboxImageView: View {
    @Environment(\.colorScheme) private var colorScheme
    let fileName: String
    var zoomScale: CGFloat = 1
    var zoomOffset: CGSize = .zero
    var onAspectResolved: ((CGFloat) -> Void)? = nil
    #if canImport(AppKit)
    @State private var image: NSImage? = nil
    @State private var imageLoadTask: Task<Void, Never>? = nil
    @State private var loadFailed: Bool = false
    #endif

    /// Width / height of the loaded image, so the card hugs the picture and
    /// portrait or landscape shots show at full size; placeholder until loaded.
    private var cardAspectRatio: CGFloat {
        #if canImport(AppKit)
        if let image, image.size.height > 0, image.size.width > 0 {
            return image.size.width / image.size.height
        }
        #endif
        return 16.0 / 10.0
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
        ZStack {
            theme.inset
            Group {
                #if canImport(AppKit)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(zoomScale)
                        .offset(zoomOffset)
                } else if loadFailed {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Missing File")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                } else {
                    ProgressView()
                }
                #else
                if loadFailed {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Missing File")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
                #endif
            }
        }
        .aspectRatio(cardAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DSToken.Motion.reveal, value: cardAspectRatio)
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
        loadFailed = false
        let url = MediaManager.resolvedURL(for: fileName)
        imageLoadTask = Task { @MainActor in
            let data = await ImageFileLoader.data(from: url)
            guard !Task.isCancelled else { return }
            if let data, let nsImage = NSImage(data: data) {
                image = nsImage
                if nsImage.size.width > 0, nsImage.size.height > 0 {
                    onAspectResolved?(nsImage.size.width / nsImage.size.height)
                }
            } else {
                loadFailed = true
            }
        }
        #else
        loadFailed = true // Simulate failure on non-AppKit for missing ImageFileLoader
        #endif
    }
}

private struct LightboxVideoView: View {
    let fileName: String
    var zoomScale: CGFloat = 1
    var zoomOffset: CGSize = .zero
    var onAspectResolved: ((CGFloat) -> Void)? = nil

    /// Width / height of the video's display size; 16:9 placeholder until the
    /// asset's track dimensions have loaded.
    @State private var aspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        ZStack {
            Color.black
            // Hit-transparent: the player has no controls, and the AVPlayer's
            // NSView would otherwise swallow clicks meant for the chevrons.
            LoopingVideoPlayerView(
                fileName: fileName,
                videoGravity: .resizeAspect,
                zoomScale: zoomScale,
                zoomOffset: zoomOffset
            )
            .allowsHitTesting(false)
        }
        // Box matches the video's own aspect ratio, sized to the available
        // space inside the lightbox gutters.
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: fileName) { await loadAspectRatio() }
    }

    private func loadAspectRatio() async {
        let asset = AVURLAsset(url: MediaManager.resolvedURL(for: fileName))
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (naturalSize, transform) = try? await track.load(.naturalSize, .preferredTransform) else {
            return
        }
        let size = naturalSize.applying(transform)
        let width = abs(size.width)
        let height = abs(size.height)
        guard width > 0, height > 0 else { return }
        withAnimation(DSToken.Motion.reveal) {
            aspectRatio = width / height
        }
        onAspectResolved?(width / height)
    }
}

private struct ImageMediaView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: MediaItem
    #if canImport(AppKit)
    @State private var image: NSImage? = nil
    @State private var imageLoadTask: Task<Void, Never>? = nil
    @State private var loadFailed: Bool = false
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
            } else if loadFailed {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Missing File")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            #else
            if loadFailed {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Missing File")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
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
        loadFailed = false
        let url = MediaManager.resolvedURL(for: item.fileName)
        imageLoadTask = Task { @MainActor in
            // 2048px covers the detail pane at Retina; full res stays in the lightbox.
            let cgImage = await ImageFileLoader.downsampledImage(from: url, maxPixelSize: 2048)
            guard !Task.isCancelled else { return }
            if let cgImage {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } else {
                loadFailed = true
            }
        }
        #else
        loadFailed = true // Simulate failure on non-AppKit for missing ImageFileLoader
        #endif
    }
}

private struct VideoMediaView: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            LoopingVideoPlayerView(fileName: item.fileName, videoGravity: .resizeAspect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if canImport(AppKit)
private enum ImageFileLoader {
    static func data(from url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
    }

    /// Downsampled decode for inline display; the lightbox keeps the
    /// full-resolution path above for zooming.
    static func downsampledImage(from url: URL, maxPixelSize: CGFloat) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(
                url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) else { return nil }
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as CFDictionary
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        }.value
    }
}
#endif

#if canImport(AppKit)
private struct HighlightedCodeView: NSViewRepresentable {
    let code: String
    let language: SupportedLanguage
    let theme: Theme
    var fontSize: CGFloat = 13

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        // Wrap to the visible width instead of scrolling horizontally. Leaving
        // the text view horizontally resizable made it wider than the area left
        // by the line-number ruler, so it opened scrolled right and hid the
        // first characters. Mirrors the editable CodeEditor's configuration.
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.usesFindBar = true
        textView.string = code

        if let storage = textView.textStorage {
            SyntaxHighlighter.applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
            context.coordinator.mark(code: code, language: language, theme: theme, fontSize: fontSize)
        }

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let ruler = LineNumberRulerView(textView: textView, theme: theme)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textColor = NSColor(theme.text)
        textView.backgroundColor = .clear
        nsView.backgroundColor = .clear

        let codeChanged = textView.string != code
        let styleChanged = context.coordinator.needsUpdate(code: code, language: language, theme: theme, fontSize: fontSize)
        if textView.string != code {
            textView.string = code
        }
        if (codeChanged || styleChanged), let storage = textView.textStorage {
            SyntaxHighlighter.applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
            context.coordinator.mark(code: code, language: language, theme: theme, fontSize: fontSize)
        }
        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.update(theme: theme)
            if codeChanged {
                ruler.updateText(code)
            }
            ruler.needsDisplay = true
        }
        if codeChanged {
            nsView.contentView.scroll(to: .zero)
            nsView.reflectScrolledClipView(nsView.contentView)
        }
    }

    final class Coordinator {
        private var lastCodeHash: Int?
        private var lastCodeLength: Int?
        private var lastLanguage: SupportedLanguage?
        private var lastThemeScheme: ColorScheme?
        private var lastFontSize: CGFloat?

        func needsUpdate(code: String, language: SupportedLanguage, theme: Theme, fontSize: CGFloat) -> Bool {
            lastCodeHash != code.hashValue ||
            lastCodeLength != code.utf8.count ||
            lastLanguage != language ||
            lastThemeScheme != theme.scheme ||
            lastFontSize != fontSize
        }

        func mark(code: String, language: SupportedLanguage, theme: Theme, fontSize: CGFloat) {
            lastCodeHash = code.hashValue
            lastCodeLength = code.utf8.count
            lastLanguage = language
            lastThemeScheme = theme.scheme
            lastFontSize = fontSize
        }
    }
}

#else
private struct HighlightedCodeView: View {
    let code: String
    let language: SupportedLanguage
    let theme: Theme
    var fontSize: CGFloat = 13

    var body: some View {
        CodeView(code: code, showLineNumbers: true, fontSize: fontSize)
    }
}
#endif
