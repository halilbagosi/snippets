import SwiftUI

/// Offers to turn something the user copied elsewhere into a snippet.
///
/// Shows an excerpt rather than the whole capture: enough to recognise what
/// was caught, not so much that it takes over the panel.
struct CaptureBanner: View {
    /// Lines of the capture shown in the excerpt.
    private static let excerptLineLimit = 6

    let candidate: ClipboardCapture.Candidate
    let onSave: () -> Void
    let onDismiss: () -> Void

    private var excerpt: String {
        candidate.code
            .components(separatedBy: .newlines)
            .prefix(Self.excerptLineLimit)
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSToken.Spacing.xs) {
            HStack(spacing: DSToken.Spacing.xs) {
                Text("Copied code")
                    .font(.system(size: 11, weight: .semibold))
                LanguageBadge(language: candidate.language, compact: true)
                Spacer()
            }

            Text(excerpt)
                .font(Mono.font(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(Self.excerptLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: DSToken.Spacing.xs) {
                Button("Save as snippet", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .controlSize(.small)
                Spacer()
            }
            .font(.system(size: 11))
        }
        .padding(DSToken.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: DSToken.Radius.sm, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        }
        .padding(.horizontal, DSToken.Spacing.xs)
        .padding(.bottom, DSToken.Spacing.xs)
    }
}
