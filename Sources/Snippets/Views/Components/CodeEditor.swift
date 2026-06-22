import SwiftUI
#if canImport(AppKit)
import AppKit

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let language: SupportedLanguage
    let theme: Theme
    var fontSize: CGFloat = 13
    var minHeight: CGFloat = 240

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        configure(textView: textView, scrollView: scrollView)

        textView.delegate = context.coordinator
        textView.string = text

        if let storage = textView.textStorage {
            SyntaxHighlighter.applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
            context.coordinator.markHighlighted(language: language, theme: theme, fontSize: fontSize)
        }

        let ruler = LineNumberRulerView(textView: textView, theme: theme)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.observe(textView: textView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.applyCachedColors(to: textView, scrollView: nsView, theme: theme)

        textView.backgroundColor = .clear
        nsView.backgroundColor = .clear

        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.update(theme: theme)
        }

        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            if let storage = textView.textStorage {
                SyntaxHighlighter.applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
                coordinator.markHighlighted(language: language, theme: theme, fontSize: fontSize)
            }
            (nsView.verticalRulerView as? LineNumberRulerView)?.updateText(text)
            let length = (text as NSString).length
            if NSMaxRange(selected) <= length {
                textView.setSelectedRange(selected)
            } else {
                textView.setSelectedRange(NSRange(location: length, length: 0))
            }
        } else if coordinator.needsHighlight(language: language, theme: theme, fontSize: fontSize),
                  let storage = textView.textStorage {
            SyntaxHighlighter.applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
            coordinator.markHighlighted(language: language, theme: theme, fontSize: fontSize)
        } else if coordinator.isInternalUpdate {
            coordinator.isInternalUpdate = false
        }

        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.needsDisplay = true
        }
    }

    private func configure(textView: NSTextView, scrollView: NSScrollView) {
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor(theme.text)
        textView.insertionPointColor = NSColor(theme.accent)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(theme.accent).withAlphaComponent(0.28)
        ]
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        fileprivate var parent: CodeEditor
        fileprivate var isInternalUpdate = false
        private var highlightedLanguage: SupportedLanguage?
        private var highlightedThemeScheme: ColorScheme?
        private var highlightedFontSize: CGFloat?
        private var cachedThemeSignature: String?
        private var cachedTextColor: NSColor?
        private var cachedAccentColor: NSColor?

        init(_ parent: CodeEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func observe(textView: NSTextView) {
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(handleBeginEditing(_:)), name: NSText.didBeginEditingNotification, object: textView)
            center.addObserver(self, selector: #selector(handleEndEditing(_:)), name: NSText.didEndEditingNotification, object: textView)
        }

        @objc private func handleBeginEditing(_ note: Notification) {
            parent.isFocused = true
        }

        @objc private func handleEndEditing(_ note: Notification) {
            parent.isFocused = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isInternalUpdate = true
            parent.text = textView.string
            if let storage = textView.textStorage {
                SyntaxHighlighter.applyAttributes(to: storage, language: parent.language, theme: parent.theme, fontSize: parent.fontSize)
                markHighlighted(language: parent.language, theme: parent.theme, fontSize: parent.fontSize)
            }
            if let scroll = textView.enclosingScrollView,
               let ruler = scroll.verticalRulerView as? LineNumberRulerView {
                ruler.updateText(textView.string)
                ruler.needsDisplay = true
            }
        }

        func needsHighlight(language: SupportedLanguage, theme: Theme, fontSize: CGFloat) -> Bool {
            highlightedLanguage != language ||
            highlightedThemeScheme != theme.scheme ||
            highlightedFontSize != fontSize
        }

        func markHighlighted(language: SupportedLanguage, theme: Theme, fontSize: CGFloat) {
            highlightedLanguage = language
            highlightedThemeScheme = theme.scheme
            highlightedFontSize = fontSize
        }

        func applyCachedColors(to textView: NSTextView, scrollView: NSScrollView, theme: Theme) {
            let signature = "\(theme.scheme)-\(theme.text)-\(theme.accent)"
            if cachedThemeSignature != signature {
                cachedThemeSignature = signature
                cachedTextColor = NSColor(theme.text)
                cachedAccentColor = NSColor(theme.accent)
            }

            let textColor = cachedTextColor ?? NSColor(theme.text)
            let accentColor = cachedAccentColor ?? NSColor(theme.accent)
            textView.textColor = textColor
            textView.insertionPointColor = accentColor
            textView.selectedTextAttributes = [
                .backgroundColor: accentColor.withAlphaComponent(0.28)
            ]
            scrollView.backgroundColor = .clear
        }
    }
}

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var theme: Theme
    private var newlineIndexes: [Int] = []

    init(textView: NSTextView, theme: Theme) {
        self.theme = theme
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.textView = textView
        self.clientView = textView
        self.ruleThickness = 44
        updateText(textView.string)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(theme: Theme) {
        self.theme = theme
    }

    func updateText(_ text: String) {
        let nsString = text as NSString
        var indexes: [Int] = []
        indexes.reserveCapacity(max(8, text.utf8.count / 40))
        for idx in 0..<nsString.length where nsString.character(at: idx) == 0x0A {
            indexes.append(idx)
        }
        newlineIndexes = indexes
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(theme.canvasDeep).setFill()
        bounds.fill()

        let borderColor = NSColor(theme.border)
        borderColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        path.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        path.lineWidth = 1
        path.stroke()

        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = scrollView
        else { return }

        let visibleRect = scrollView.contentView.bounds
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)

        let nsString = textView.string as NSString
        let firstCharIndex = layoutManager.characterIndexForGlyph(at: visibleGlyphRange.location)
        var lineNumber = computeLineNumber(at: firstCharIndex)

        let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor(theme.textFaint)
        ]
        let activeAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor(theme.textMuted)
        ]

        let inset = textView.textContainerInset.height
        let selectedRange = textView.selectedRange()
        let selectedLine = computeLineNumber(at: selectedRange.location)

        var glyphIndex = visibleGlyphRange.location
        while glyphIndex < NSMaxRange(visibleGlyphRange) {
            var lineRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let isLineStart: Bool
            if charIndex == 0 {
                isLineStart = true
            } else {
                let prev = nsString.character(at: charIndex - 1)
                isLineStart = prev == 0x0A
            }

            if isLineStart || glyphIndex == visibleGlyphRange.location {
                let label = "\(lineNumber)" as NSString
                let attrs = (lineNumber == selectedLine) ? activeAttrs : labelAttrs
                let labelSize = label.size(withAttributes: attrs)
                let yPos = lineRect.minY - visibleRect.minY + inset + (lineRect.height - labelSize.height) / 2
                label.draw(
                    at: NSPoint(x: bounds.maxX - labelSize.width - 8, y: yPos),
                    withAttributes: attrs
                )
                lineNumber += 1
            }

            glyphIndex = NSMaxRange(lineRange)
        }
    }

    private func computeLineNumber(at characterIndex: Int) -> Int {
        let length = textView?.string.utf16.count ?? 0
        let safe = min(max(characterIndex, 0), length)
        guard safe > 0 else { return 1 }

        var low = 0
        var high = newlineIndexes.count
        while low < high {
            let mid = (low + high) / 2
            if newlineIndexes[mid] < safe {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low + 1
    }
}
#endif

#Preview("CodeEditor") {
    struct PreviewWrapper: View {
        @State private var text = "func hello() {\n    print(\"Hello\")\n}"
        @State private var isFocused = false
        var body: some View {
            CodeEditor(
                text: $text,
                isFocused: $isFocused,
                language: .swift,
                theme: Theme.current(.dark)
            )
            .padding()
        }
    }
    return PreviewWrapper()
}
