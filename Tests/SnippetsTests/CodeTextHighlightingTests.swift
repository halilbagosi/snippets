import XCTest
import SwiftUI
import AppKit
@testable import Snippets

/// The detail view and the editor host their code in an `NSTextView` whose
/// syntax colours live in the text storage. Setting `NSTextView.textColor`
/// recolours every character, so a representable that does that on each
/// SwiftUI update silently flattens the highlighting to plain text.
@MainActor
final class CodeTextHighlightingTests: XCTestCase {
    private let code = "let answer = 42 // comment"

    private func host<V: View>(_ view: V) -> (NSHostingView<V>, NSWindow) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for subview in view.subviews {
            if let found = textView(in: subview) { return found }
        }
        return nil
    }

    private func color(of substring: String, in textView: NSTextView) -> NSColor? {
        let range = (textView.string as NSString).range(of: substring)
        guard range.location != NSNotFound else { return nil }
        return textView.textStorage?.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    private func assertHighlighted(
        _ textView: NSTextView, scheme: ColorScheme,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let theme = Theme.current(scheme)
        XCTAssertEqual(color(of: "let", in: textView), NSColor(theme.keyword), "keyword colour", file: file, line: line)
        XCTAssertEqual(color(of: "// comment", in: textView), NSColor(theme.comment), "comment colour", file: file, line: line)
        XCTAssertEqual(color(of: "answer", in: textView), NSColor(theme.text), "plain-text colour", file: file, line: line)
    }

    // MARK: Detail view

    func testDetailCodeKeepsHighlightingAcrossUpdates() throws {
        let (hosting, window) = host(HighlightedCodeView(code: code, language: .swift, theme: .current(.dark)))
        defer { window.close() }
        let textView = try XCTUnwrap(textView(in: hosting))
        assertHighlighted(textView, scheme: .dark)

        // An unrelated parent update re-runs updateNSView with identical inputs.
        hosting.rootView = HighlightedCodeView(code: code, language: .swift, theme: .current(.dark))
        hosting.layoutSubtreeIfNeeded()
        assertHighlighted(textView, scheme: .dark)
    }

    func testDetailCodeRecoloursOnAppearanceChange() throws {
        let (hosting, window) = host(HighlightedCodeView(code: code, language: .swift, theme: .current(.dark)))
        defer { window.close() }
        let textView = try XCTUnwrap(textView(in: hosting))

        hosting.rootView = HighlightedCodeView(code: code, language: .swift, theme: .current(.light))
        hosting.layoutSubtreeIfNeeded()
        assertHighlighted(textView, scheme: .light)

        hosting.rootView = HighlightedCodeView(code: code, language: .swift, theme: .current(.dark))
        hosting.layoutSubtreeIfNeeded()
        assertHighlighted(textView, scheme: .dark)
    }

    // MARK: Editor

    private func editor(_ scheme: ColorScheme) -> CodeEditor {
        CodeEditor(
            text: .constant(code), isFocused: .constant(false),
            language: .swift, theme: .current(scheme)
        )
    }

    func testEditorKeepsHighlightingAcrossUpdates() throws {
        let (hosting, window) = host(editor(.dark))
        defer { window.close() }
        let textView = try XCTUnwrap(textView(in: hosting))
        assertHighlighted(textView, scheme: .dark)

        hosting.rootView = editor(.dark)
        hosting.layoutSubtreeIfNeeded()
        assertHighlighted(textView, scheme: .dark)
    }

    func testEditorRecoloursOnAppearanceChange() throws {
        let (hosting, window) = host(editor(.dark))
        defer { window.close() }
        let textView = try XCTUnwrap(textView(in: hosting))

        hosting.rootView = editor(.light)
        hosting.layoutSubtreeIfNeeded()
        assertHighlighted(textView, scheme: .light)
        XCTAssertEqual(
            textView.typingAttributes[.foregroundColor] as? NSColor, NSColor(Theme.current(.light).text),
            "typed text should start in the theme's text colour"
        )
    }
}
