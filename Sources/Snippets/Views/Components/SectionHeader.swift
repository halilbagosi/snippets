import SwiftUI

struct SectionHeader<Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let prefix: String
    let label: String
    let trailing: Trailing

    init(prefix: String = "//", _ label: String, @ViewBuilder trailing: () -> Trailing) {
        self.prefix = prefix
        self.label = label
        self.trailing = trailing()
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
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(prefix: String = "//", _ label: String) {
        self.prefix = prefix
        self.label = label
        self.trailing = EmptyView()
    }
}

#Preview("SectionHeader") {
    VStack(spacing: 20) {
        SectionHeader("Files")
        SectionHeader(prefix: "///", "Documentation")
    }
    .padding()
}
