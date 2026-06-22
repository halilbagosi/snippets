import SwiftUI

struct CodeView: View {
    @Environment(\.colorScheme) private var colorScheme

    let code: String
    var maxLines: Int? = nil
    var showLineNumbers: Bool = true
    var fontSize: CGFloat = 12.5

    @State private var displayedLines: [String]

    init(
        code: String,
        maxLines: Int? = nil,
        showLineNumbers: Bool = true,
        fontSize: CGFloat = 12.5
    ) {
        self.code = code
        self.maxLines = maxLines
        self.showLineNumbers = showLineNumbers
        self.fontSize = fontSize
        self._displayedLines = State(initialValue: Self.makeDisplayedLines(from: code, maxLines: maxLines))
    }

    private static func makeDisplayedLines(from code: String, maxLines: Int?) -> [String] {
        let raw = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let maxLines, raw.count > maxLines {
            return Array(raw.prefix(maxLines)) + ["…"]
        }
        return raw
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 0) {
                if showLineNumbers {
                    LazyVStack(alignment: .trailing, spacing: 2) {
                        ForEach(displayedLines.indices, id: \.self) { index in
                            Text("\(index + 1)")
                                .font(Mono.font(size: fontSize - 1))
                                .foregroundStyle(theme.textFaint)
                                .frame(minWidth: 28, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.trailing, 12)
                    .padding(.leading, 12)
                    .background(theme.canvasDeep)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(theme.border).frame(width: 1)
                    }
                }

                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(displayedLines.indices, id: \.self) { index in
                        let line = displayedLines[index]
                        Text(line.isEmpty ? " " : line)
                            .font(Mono.font(size: fontSize))
                            .foregroundStyle(theme.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.canvasDeep)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: code) { _, newValue in
            displayedLines = Self.makeDisplayedLines(from: newValue, maxLines: maxLines)
        }
        .onChange(of: maxLines) { _, newValue in
            displayedLines = Self.makeDisplayedLines(from: code, maxLines: newValue)
        }
    }
}

#Preview("CodeView") {
    CodeView(
        code: "func hello() {\n    print(\"Hello, World!\")\n}",
        maxLines: nil,
        showLineNumbers: true,
        fontSize: 12.5
    )
    .padding()
}
