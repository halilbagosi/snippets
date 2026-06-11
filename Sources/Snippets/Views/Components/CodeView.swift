import SwiftUI

struct CodeView: View {
    @Environment(\.colorScheme) private var colorScheme

    let code: String
    var maxLines: Int? = nil
    var showLineNumbers: Bool = true
    var fontSize: CGFloat = 12.5

    private var displayedLines: [String] {
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
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(Array(displayedLines.enumerated()), id: \.offset) { index, _ in
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

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(displayedLines.enumerated()), id: \.offset) { _, line in
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
