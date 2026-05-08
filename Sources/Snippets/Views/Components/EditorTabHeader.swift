import SwiftUI

struct EditorTabHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let filename: String
    var language: SupportedLanguage = .unknown
    var showTrafficLights: Bool = true
    var trailing: AnyView? = nil

    var body: some View {
        let theme = Theme.current(colorScheme)
        HStack(spacing: 12) {
            if showTrafficLights {
                HStack(spacing: 7) {
                    Circle().fill(theme.trafficRed).frame(width: 11, height: 11)
                    Circle().fill(theme.trafficYellow).frame(width: 11, height: 11)
                    Circle().fill(theme.trafficGreen).frame(width: 11, height: 11)
                }
                .padding(.trailing, 4)
            }

            HStack(spacing: 6) {
                Image(systemName: language.symbolName)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: language.accentHex) ?? theme.accent)
                Text(filename)
                    .font(Mono.font(size: 12, weight: .medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    }
            }

            Spacer(minLength: 8)

            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(theme.surfaceElevated)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.border).frame(height: 1)
                }
        }
    }
}
