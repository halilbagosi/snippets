import SwiftUI

/// Shows the licence notices for the bundled preview runtimes
/// (`ThirdPartyNotices.txt`) as an acknowledgements browser: the components
/// in a sidebar, the selected one's copyright and licence beside it. Their
/// MIT licences require the notice to ship with every copy of the app.
struct ThirdPartyNoticesView: View {
    static let windowID = "third-party-notices"

    private enum Selection: Hashable {
        case overview
        case component(String)
    }

    private let notices = bundledText("ThirdPartyNotices").map(ThirdPartyNotices.init(text:))
    @State private var selection: Selection? = .overview

    var body: some View {
        Group {
            if let notices {
                NavigationSplitView {
                    List(selection: $selection) {
                        Label("Overview", systemImage: "info.circle")
                            .tag(Selection.overview)
                        Section("Bundled Components") {
                            ForEach(notices.components) { component in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(component.name)
                                        .lineLimit(2)
                                    if let note = component.note {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .tag(Selection.component(component.id))
                            }
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
                } detail: {
                    detail(for: notices)
                }
            } else {
                ContentUnavailableView(
                    "No Notices",
                    systemImage: "doc.questionmark",
                    description: Text("Third-party notices are missing from this copy of Snippets.")
                )
            }
        }
        .frame(minWidth: 640, idealWidth: 780, minHeight: 400, idealHeight: 580)
    }

    @ViewBuilder
    private func detail(for notices: ThirdPartyNotices) -> some View {
        switch selection {
        case .component(let id):
            if let component = notices.components.first(where: { $0.id == id }) {
                ComponentNoticeView(component: component)
                    .id(id)
            }
        case .overview, nil:
            LegalDocumentView(document: notices.introduction)
        }
    }
}

/// One component's notice: what it is, where it comes from, who holds the
/// copyright, and the licence text it ships under.
private struct ComponentNoticeView: View {
    let component: ThirdPartyNotices.Component

    var body: some View {
        LegalPage {
            VStack(alignment: .leading, spacing: 4) {
                Text(component.name)
                    .font(.title2.weight(.semibold))
                if let note = component.note {
                    Text(note)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                if let license = component.licenseName {
                    Text(license)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                if let url = component.url {
                    Link(destination: url) {
                        Label(url.host().map { $0 + url.path() } ?? url.absoluteString,
                              systemImage: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
            }

            if !component.copyright.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(component.copyright, id: \.self) { Text($0) }
                }
                .font(.callout.weight(.medium))
            }

            Divider()

            ForEach(Array(component.licenseParagraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(linked(paragraph))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
    }
}

/// Typesets a `LegalDocument` like a page: a title, numbered section
/// headings, reflowed paragraphs with live links, and hanging-indent lists.
struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        LegalPage {
            Text(document.title)
                .font(.title2.weight(.semibold))
                .padding(.bottom, 2)

            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(text)
                        .font(.headline)
                        .padding(.top, 10)
                case .copyright(let text):
                    Text(text)
                        .foregroundStyle(.secondary)
                case .paragraph(let text):
                    Text(linked(text))
                        .lineSpacing(2)
                case .listItem(let marker, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker)
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Text(linked(text))
                            .lineSpacing(2)
                    }
                    .padding(.leading, 8)
                }
            }
        }
    }
}

/// A scrolling, selectable column of readable width.
private struct LegalPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .textSelection(.enabled)
        }
    }
}

private func bundledText(_ resource: String) -> String? {
    Bundle.main.url(forResource: resource, withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
}

/// The text with every URL in it made a clickable link.
private func linked(_ text: String) -> AttributedString {
    var result = AttributedString(text)
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return result
    }
    for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let url = match.url,
              let range = Range(match.range, in: text),
              let lower = AttributedString.Index(range.lowerBound, within: result),
              let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
        result[lower..<upper].link = url
    }
    return result
}

/// Shows Snippets' end user licence agreement (`EULA.txt`). The app is
/// closed source, so this is the licence users get it under.
struct LicenseAgreementView: View {
    static let windowID = "license-agreement"

    var body: some View {
        BundledTextView(
            resource: "EULA", withExtension: "txt",
            missingMessage: "The licence agreement is missing from this copy of Snippets."
        )
    }
}

/// A scrollable, selectable monospaced view of a plain-text bundle resource.
private struct BundledTextView: View {
    private let text: String

    init(resource: String, withExtension ext: String?, missingMessage: String) {
        if let url = Bundle.main.url(forResource: resource, withExtension: ext),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            text = contents
        } else {
            text = missingMessage
        }
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .frame(minWidth: 520, idealWidth: 640, minHeight: 360, idealHeight: 560)
    }
}
