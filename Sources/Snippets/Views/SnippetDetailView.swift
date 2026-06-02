import SwiftUI
import AVKit
#if canImport(AppKit)
import AppKit
#endif

struct SnippetDetailView: View {
    @Environment(\.colorScheme) private var colorScheme

    let snippet: Snippet
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var didCopy: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var lightboxMedia: MediaItem? = nil
    @State private var isCopyPressed: Bool = false
    @State private var isEditPressed: Bool = false
    @State private var isDeletePressed: Bool = false

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
            get: { lightboxMedia != nil },
            set: { if !$0 { lightboxMedia = nil } }
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock
                    actionBar
                    if !snippet.snippetDescription.isEmpty {
                        descriptionBlock
                    }
                    if !orderedMediaItems.isEmpty {
                        mediaSection
                    }
                    codeBlock
                    metadata
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.text)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.22 : 0.34), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 12, x: 0, y: 6)
            .padding(.top, 14)
            .padding(.trailing, 14)
            .accessibilityLabel("Close snippet")
        }
        .confirmationDialog(
            "Delete this snippet?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Snippet", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes the snippet and all attached media.")
        }
        .sheet(isPresented: showMediaLightbox, onDismiss: { lightboxMedia = nil }) {
            if let item = lightboxMedia {
                MediaAttachmentLightbox(item: item)
            }
        }
    }

    private var titleBlock: some View {
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
            HStack(spacing: 10) {
                LanguageBadge(language: language)
                Text(snippet.updatedAt, format: .dateTime.month().day().year().hour().minute())
                    .font(Mono.font(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                Clipboard.copy(snippet.code)
                snippet.copyCount += 1
                didCopy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    didCopy = false
                }
            } label: {
                Label(didCopy ? "Copied" : "Copy Code", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .padding(.horizontal, actionBarButtonHorizontalPadding)
                    .frame(height: actionBarButtonLabelHeight)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .clipShape(Capsule())
            .scaleEffect(isCopyPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isCopyPressed)
            .simultaneousGesture(pressGesture(isPressed: $isCopyPressed))

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
                    .padding(.horizontal, actionBarButtonHorizontalPadding)
                    .frame(height: actionBarButtonLabelHeight)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .clipShape(Capsule())
            .scaleEffect(isEditPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isEditPressed)
            .simultaneousGesture(pressGesture(isPressed: $isEditPressed))

            Spacer()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .padding(.horizontal, actionBarButtonHorizontalPadding)
                    .frame(height: actionBarButtonLabelHeight)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.red)
            .clipShape(Capsule())
            .scaleEffect(isDeletePressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isDeletePressed)
            .simultaneousGesture(pressGesture(isPressed: $isDeletePressed))
        }
    }

    private func pressGesture(isPressed: Binding<Bool>) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPressed.wrappedValue {
                    isPressed.wrappedValue = true
                }
            }
            .onEnded { _ in
                isPressed.wrappedValue = false
            }
    }


    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("description")
            Text(snippet.snippetDescription)
                .font(Sans.font(size: 14))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(theme.border, lineWidth: 1)
                        }
                }
        }
    }

    private var codeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("source")
            HighlightedCodeView(
                code: snippet.code,
                language: language,
                theme: theme,
                fontSize: 13
            )
                .frame(minHeight: 240, maxHeight: 520)
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("attachments", trailing: AnyView(
                Text("\(orderedMediaItems.count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textFaint)
            ))

            let layout = AttachmentStripLayout.self
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: layout.hSpacing) {
                    ForEach(orderedMediaItems) { item in
                        Button {
                            lightboxMedia = item
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
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.canvasDeep)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("meta")
            HStack(spacing: 12) {
                metaPill(label: "created", value: snippet.createdAt.formatted(date: .abbreviated, time: .shortened))
                metaPill(label: "updated", value: snippet.updatedAt.formatted(date: .abbreviated, time: .shortened))
                metaPill(label: "lines", value: "\(snippet.code.split(separator: "\n").count)")
                metaPill(label: "chars", value: "\(snippet.code.count)")
                Spacer()
            }
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
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
        }
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
                    VideoMediaView(item: item)
                }
            }
            .frame(width: innerSize.width, height: innerSize.height)
            .clipShape(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous))

            if item.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(7)
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

    let item: MediaItem

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.canvas.ignoresSafeArea()
                switch item.kind {
                case .image:
                    LightboxImageView(fileName: item.fileName)
                case .video:
                    LightboxVideoView(fileName: item.fileName)
                }
            }
            .frame(minWidth: 560, minHeight: 440)
            .navigationTitle("Attachment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LightboxImageView: View {
    @Environment(\.colorScheme) private var colorScheme
    let fileName: String
    #if canImport(AppKit)
    @State private var image: NSImage? = nil
    #endif

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
                } else {
                    ProgressView()
                }
                #else
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                #endif
            }
        }
        .frame(maxWidth: 900, maxHeight: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            #if canImport(AppKit)
            let url = MediaManager.resolvedURL(for: fileName)
            image = NSImage(contentsOf: url)
            #endif
        }
    }
}

private struct LightboxVideoView: View {
    let fileName: String

    var body: some View {
        ZStack {
            Color.black
            LoopingVideoPlayerView(fileName: fileName, videoGravity: .resizeAspect)
        }
        .frame(width: 800, height: 450)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ImageMediaView: View {
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
                ProgressView().controlSize(.small)
            }
            #else
            Image(systemName: "photo")
                .font(.system(size: 32))
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
private struct HighlightedCodeView: NSViewRepresentable {
    let code: String
    let language: SupportedLanguage
    let theme: Theme
    var fontSize: CGFloat = 13

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.usesFindBar = true
        textView.string = code

        if let storage = textView.textStorage {
            SyntaxHighlighter.applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
        }

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
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
        if textView.string != code {
            textView.string = code
        }
        if let storage = textView.textStorage {
            SyntaxHighlighter.applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
        }
        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.update(theme: theme)
            ruler.needsDisplay = true
        }
        if codeChanged {
            nsView.contentView.scroll(to: .zero)
            nsView.reflectScrolledClipView(nsView.contentView)
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
