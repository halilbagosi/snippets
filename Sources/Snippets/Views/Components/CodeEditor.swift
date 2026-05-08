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

        textView.textColor = NSColor(theme.text)
        textView.insertionPointColor = NSColor(theme.accent)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(theme.accent).withAlphaComponent(0.28)
        ]
        textView.backgroundColor = .clear
        nsView.backgroundColor = .clear

        if let ruler = nsView.verticalRulerView as? LineNumberRulerView {
            ruler.update(theme: theme)
            ruler.needsDisplay = true
        }

        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            if let storage = textView.textStorage {
                SyntaxHighlighter.applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
            }
            let length = (text as NSString).length
            if NSMaxRange(selected) <= length {
                textView.setSelectedRange(selected)
            } else {
                textView.setSelectedRange(NSRange(location: length, length: 0))
            }
        } else if let storage = textView.textStorage {
            SyntaxHighlighter.applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
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
        fileprivate let parent: CodeEditor

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
            parent.text = textView.string
            if let storage = textView.textStorage {
                SyntaxHighlighter.applyAttributes(to: storage, language: parent.language, theme: parent.theme, fontSize: parent.fontSize)
            }
            if let scroll = textView.enclosingScrollView,
               let ruler = scroll.verticalRulerView as? LineNumberRulerView {
                ruler.needsDisplay = true
            }
        }
    }
}

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var theme: Theme

    init(textView: NSTextView, theme: Theme) {
        self.theme = theme
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.textView = textView
        self.clientView = textView
        self.ruleThickness = 44
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(theme: Theme) {
        self.theme = theme
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
        var lineNumber = computeLineNumber(at: firstCharIndex, in: nsString)

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
        let selectedLine = computeLineNumber(at: selectedRange.location, in: nsString)

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

    private func computeLineNumber(at characterIndex: Int, in nsString: NSString) -> Int {
        let safe = min(max(characterIndex, 0), nsString.length)
        guard safe > 0 else { return 1 }
        var count = 1
        var idx = 0
        while idx < safe {
            if nsString.character(at: idx) == 0x0A {
                count += 1
            }
            idx += 1
        }
        return count
    }
}
#endif
