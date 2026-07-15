import SwiftUI
import SwiftData

struct SnippetCollectionCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let collection: SnippetCollection
    var isSelected: Bool = false
    var inTrashView: Bool = false
    var isSelectionMode: Bool = false
    let onOpen: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil
    var onPermanentDelete: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var cardSize: CGSize = .zero
    @State private var didAppear = false

    private var activeSnippetCount: Int {
        var seenIDs = Set<PersistentIdentifier>()

        func collect(from collection: SnippetCollection) {
            for snippet in collection.snippets where snippet.deletedAt == nil {
                guard !seenIDs.contains(snippet.persistentModelID) else { continue }
                seenIDs.insert(snippet.persistentModelID)
            }

            for child in collection.children {
                collect(from: child)
            }
        }

        collect(from: collection)
        return seenIDs.count
    }

    private var hoverCenter: CGPoint {
        CGPoint(x: max(cardSize.width, 1) * 0.5, y: max(cardSize.height, 1) * 0.5)
    }

    private var hoverVector: CGVector {
        guard cardSize.width > 0, cardSize.height > 0 else { return .zero }
        return CGVector(
            dx: min(max((hoverLocation.x / cardSize.width - 0.5) * 2, -1), 1),
            dy: min(max((hoverLocation.y / cardSize.height - 0.5) * 2, -1), 1)
        )
    }

    private var formattedDate: String {
        Self.dateFormatter.string(from: collection.createdAt)
    }

    @MainActor
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        let theme = Theme.current(colorScheme)
        let accent = collection.displayColor
        let effectiveIsHovered = isSelectionMode ? false : isHovered
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let iconShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let count = activeSnippetCount
        let snippetSummary = "\(count) Snippet\(count == 1 ? "" : "s")"

        HStack(spacing: 14) {
            ZStack {
                CollectionIconView(
                    iconName: collection.displayIconName,
                    color: accent,
                    size: 22,
                    isSelected: false
                )
            }
            .frame(width: 50, height: 50)
            .background {
                iconShape
                    .fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.10))
                    .overlay {
                        iconShape
                            .strokeBorder(accent.opacity(colorScheme == .dark ? 0.30 : 0.24), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(Sans.font(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .layoutPriority(1)
                    
                if inTrashView {
                    let days = collection.daysUntilPermanentDeletion
                    let deletionBadgeColor = days <= 3
                        ? (colorScheme == .dark ? Color.red : Color(red: 0.68, green: 0.05, blue: 0.06))
                        : (colorScheme == .dark ? Color.orange.opacity(0.82) : Color(red: 0.72, green: 0.29, blue: 0.0))
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(Mono.font(size: 10, weight: .semibold))
                        Text("\(days) day\(days == 1 ? "" : "s") remaining")
                            .font(Mono.font(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(deletionBadgeColor)
                } else {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                collection.isFavorite.toggle()
                            }
                        } label: {
                            Image(systemName: collection.isFavorite ? "star.fill" : "star")
                                .font(Mono.font(size: 14, weight: .semibold))
                                .foregroundStyle(
                                    collection.isFavorite
                                        ? Color(red: 1.0, green: 0.80, blue: 0.20)
                                        : theme.textFaint
                                )
                                .padding(.vertical, DSToken.Spacing.xxs)
                                .padding(.trailing, DSToken.Spacing.xxs)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(collection.isFavorite ? "Remove from favorites" : "Add to favorites")

                        Text("\(formattedDate)")
                            .font(Mono.font(size: 10, weight: .medium))
                            .foregroundStyle(theme.textFaint)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 9) {
                
                HStack(spacing: 7) {
                    Image(systemName: "square.stack.3d.up")
                        .font(Sans.font(size: 14, weight: .semibold))
                    Text(snippetSummary)
                        .font(Sans.font(size: 13, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .monospacedDigit()
                }
                .foregroundStyle(colorScheme == .dark ? accent : theme.safeAccentText(accent))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(accent.opacity(colorScheme == .dark ? 0.30 : 0.24), lineWidth: 1)
                        }
                }
            }
            .frame(minWidth: 130, alignment: .trailing)
            .layoutPriority(2)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .contentShape(shape)
        .background {
            shape
                .fill(theme.surface.opacity(colorScheme == .dark ? 0.40 : 0.30))
                .overlay {
                    shape
                        .fill(
                            // Dark mode only adds a soft top-left highlight that
                            // fades out — never re-darkens the center — so the
                            // card reads as a uniform surface like the light one.
                            // (The old middle stop was dark `surface`, which
                            // stacked into a diagonal shadow band in dark mode.)
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [
                                        .white.opacity(0.10),
                                        .white.opacity(0.03),
                                        accent.opacity(0.03)
                                      ]
                                    : [
                                        .white.opacity(0.24),
                                        theme.surface.opacity(0.42),
                                        accent.opacity(0.02)
                                      ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    shape
                        .fill(accent.opacity(colorScheme == .dark ? 0.10 : 0.07))
                        .opacity(effectiveIsHovered ? 1 : 0)
                        .animation(.easeOut(duration: 0.14), value: effectiveIsHovered)
                }
        }
        .overlay {
            shape
                .strokeBorder(
                    isSelected ? accent.opacity(0.85) : (colorScheme == .dark ? .white.opacity(0.14) : theme.border),
                    lineWidth: isSelected ? 1.35 : 1
                )
                .allowsHitTesting(false)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        cardSize = proxy.size
                        hoverLocation = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        cardSize = newSize
                        if !isHovered {
                            hoverLocation = CGPoint(x: newSize.width * 0.5, y: newSize.height * 0.5)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(effectiveIsHovered ? 1.002 : 1.0)
        .rotation3DEffect(
            .degrees(isHovered ? -Double(hoverVector.dy) * 0.6 : 0),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.72
        )
        .rotation3DEffect(
            .degrees(isHovered ? Double(hoverVector.dx) * 0.8 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.72
        )
        .offset(
            x: isHovered ? hoverVector.dx * 0.6 : 0,
            y: isHovered ? hoverVector.dy * 0.5 : 0
        )
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 6)
        .contentShape(shape)
        .onTapGesture {
            onOpen()
        }
        .onAppear {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.94)) {
                didAppear = true
            }
        }
        .onContinuousHover { phase in
            guard !isSelectionMode else { return }
            switch phase {
            case .active(let location):
                hoverLocation = CGPoint(
                    x: min(max(location.x, 0), max(cardSize.width, 1)),
                    y: min(max(location.y, 0), max(cardSize.height, 1))
                )
                if !isHovered {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isHovered = true
                    }
                }
            case .ended:
                withAnimation(.spring(response: 0.28, dampingFraction: 0.94)) {
                    isHovered = false
                    hoverLocation = hoverCenter
                }
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.94), value: isHovered)
        .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.86), value: hoverLocation)
        .accessibilityLabel("\(collection.name), \(snippetSummary)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onOpen()
        }
        .contextMenu {
            if inTrashView {
                if let onRestore {
                    Button { onRestore() } label: { Label("Put back", systemImage: "arrow.uturn.left") }
                }
                if let onPermanentDelete {
                    Button(role: .destructive) { onPermanentDelete() } label: { Label("Delete permanently", systemImage: "trash") }
                }
            } else {
                if let onEdit {
                    Button { onEdit() } label: { Label("Edit collection", systemImage: "pencil") }
                }
                if let onDelete {
                    Button(role: .destructive) { onDelete() } label: { Label("Delete collection", systemImage: "trash") }
                }
            }
        }
    }
}
