import SwiftUI

struct SectionHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let prefix: String
    let label: String
    var trailing: AnyView? = nil

    init(prefix: String = "//", _ label: String, trailing: AnyView? = nil) {
        self.prefix = prefix
        self.label = label
        self.trailing = trailing
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
        HStack(spacing: 8) {
            Text(prefix)
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.comment)
            Text(label)
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textMuted)
                .textCase(.lowercase)
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
            if let trailing { trailing }
        }
    }
}

#Preview("SectionHeader") {
    VStack(spacing: 20) {
        SectionHeader("Files")
        SectionHeader(prefix: "///", "Documentation")
    }
    .padding()
}
