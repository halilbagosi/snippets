import Foundation

/// A plain-text legal document (`EULA.txt`, `ThirdPartyNotices.txt`) parsed
/// into blocks a view can typeset. The text files stay the source of truth —
/// they are what ships and what the licences require — so this only reads
/// their layout conventions: blank lines between paragraphs, hard-wrapped
/// lines, `1. HEADING` section titles and indented `a.` list items.
struct LegalDocument: Equatable {
    enum Block: Equatable {
        case heading(String)
        case paragraph(String)
        case listItem(marker: String, text: String)
        /// A `Copyright …` line, set apart from the body.
        case copyright(String)
    }

    var title: String
    var blocks: [Block]

    init(title: String, blocks: [Block]) {
        self.title = title
        self.blocks = blocks
    }

    /// Parses a document whose first paragraph is its title.
    init(text: String) {
        var paragraphs = Self.paragraphs(in: text)
        title = paragraphs.isEmpty ? "" : Self.titleCased(paragraphs.removeFirst().joined(separator: " "))
        blocks = paragraphs.flatMap(Self.blocks(for:))
    }

    // MARK: Parsing

    /// Splits text into paragraphs (runs of non-blank lines), keeping each
    /// line's leading indentation so list items can be recognised.
    static func paragraphs(in text: String) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.replacing(/\s+$/, with: "")
            if line.isEmpty {
                if !current.isEmpty { result.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func blocks(for lines: [String]) -> [Block] {
        if lines.count == 1, let heading = lines[0].wholeMatch(of: /(\d+)\.\s+([A-Z][A-Z0-9 ,'&-]*)/) {
            return [.heading("\(heading.1). \(titleCased(String(heading.2)))")]
        }
        if lines[0].hasPrefix("Copyright") {
            return lines.map { .copyright($0) }
        }
        let listMarker = /\s+([a-z0-9])[.)]\s+(.*)/
        guard lines.contains(where: { $0.wholeMatch(of: listMarker) != nil }) else {
            return [.paragraph(joined(lines))]
        }
        // A list: each marker line starts an item, deeper-indented lines
        // continue it. Unmarked lines before the first item are a lead-in.
        var result: [Block] = []
        var lead: [String] = []
        var item: (marker: String, lines: [String])?
        func flushItem() {
            if let item { result.append(.listItem(marker: item.marker + ".", text: joined(item.lines))) }
            item = nil
        }
        for line in lines {
            if let match = line.wholeMatch(of: listMarker) {
                flushItem()
                item = (String(match.1), [String(match.2)])
            } else if item != nil {
                item?.lines.append(line)
            } else {
                lead.append(line)
            }
        }
        flushItem()
        if !lead.isEmpty { result.insert(.paragraph(joined(lead)), at: 0) }
        return result
    }

    /// Reflows hard-wrapped lines into one line of text.
    static func joined(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    /// `THIRD-PARTY COMPONENTS AND PACKAGES` → `Third-Party Components and
    /// Packages`. Text that isn't all capitals is left alone.
    static func titleCased(_ text: String) -> String {
        guard text == text.uppercased(), text.contains(where: \.isLetter) else { return text }
        let minor: Set<String> = ["a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to"]
        return text.lowercased().split(separator: " ").enumerated().map { index, word in
            index > 0 && minor.contains(String(word)) ? String(word) : String(word).capitalized
        }.joined(separator: " ")
    }
}

/// `ThirdPartyNotices.txt`: an introduction, then one section per bundled
/// component, separated by `────` rules.
struct ThirdPartyNotices: Equatable {
    struct Component: Equatable, Identifiable {
        var name: String
        /// The parenthetical after the name, e.g. "Included in @babel/standalone".
        var note: String?
        var url: URL?
        var copyright: [String]
        var licenseName: String?
        var licenseParagraphs: [String]

        var id: String { name }
    }

    var introduction: LegalDocument
    var components: [Component]

    init(text: String) {
        let sections = text.split(separator: /\n─{3,}[^\n]*\n/, omittingEmptySubsequences: true).map(String.init)
        introduction = LegalDocument(text: sections.first ?? "")
        components = sections.dropFirst().compactMap(Self.component(in:))
    }

    static func component(in text: String) -> Component? {
        var paragraphs = LegalDocument.paragraphs(in: text)
        guard !paragraphs.isEmpty else { return nil }
        var header = paragraphs.removeFirst()
        let (name, note) = splitNote(header.removeFirst())
        let url = header.first.flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil }

        var copyright: [String] = []
        while let first = paragraphs.first, first.first?.hasPrefix("Copyright") == true {
            copyright += paragraphs.removeFirst()
        }
        let license = paragraphs.map(LegalDocument.joined)
        return Component(
            name: name, note: note, url: url, copyright: copyright,
            licenseName: license.first?.hasPrefix("Permission is hereby granted, free of charge") == true ? "MIT License" : nil,
            licenseParagraphs: license
        )
    }

    /// `Popper 2 (included in bootstrap.bundle.min.js)` →
    /// (`Popper 2`, `Included in bootstrap.bundle.min.js`).
    static func splitNote(_ line: String) -> (String, String?) {
        guard let match = line.wholeMatch(of: /(.+?)\s+\(([^()]+)\)/) else { return (line, nil) }
        let note = String(match.2)
        return (String(match.1), note.prefix(1).uppercased() + note.dropFirst())
    }
}
