import AVFoundation
import SwiftUI
import VideoToolbox

/// The welcome tour: a Mac on a card that zooms toward each feature in turn,
/// with the copy and screenshot blurring across on every page.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pager = OnboardingPager(pageCount: OnboardingPage.all.count)

    private var page: OnboardingPage { OnboardingPage.all[pager.index] }

    private enum Layout {
        static let cardSize = CGSize(width: 540, height: 620)
        static let deviceWidth: CGFloat = 476
        static let deviceTop: CGFloat = 54
        /// The stage runs under the copy, so a zoomed screen can fade out
        /// behind the title rather than stop at a hard edge.
        static let stageHeight: CGFloat = 470
    }

    var body: some View {
        ZStack(alignment: .top) {
            stage
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                copy
            }
            topBar
        }
        .frame(width: Layout.cardSize.width, height: Layout.cardSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Stage

    private var stage: some View {
        ZStack(alignment: .top) {
            device
                .id(reduceMotion ? page.id : "device")
                .transition(.opacity)
        }
        .frame(width: Layout.cardSize.width, height: Layout.stageHeight, alignment: .top)
        .clipped()
        .overlay(alignment: .bottom) {
            // Fades a magnified screen into the card behind the copy. At 1×
            // the whole Mac is in view and needs no fade.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.92), location: 0.55),
                    .init(color: Color(nsColor: .windowBackgroundColor), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 230)
            .opacity(page.zoom > 1 ? 1 : 0)
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }

    private var device: some View {
        MacBookFrame(width: Layout.deviceWidth) {
            OnboardingDesktop(page: page)
        }
        .scaleEffect(page.zoom, anchor: page.focus)
        .padding(.top, Layout.deviceTop)
    }

    // MARK: Copy

    private var copy: some View {
        VStack(spacing: DSToken.Spacing.sm) {
            PageDots(count: pager.pageCount, current: pager.index, select: go(to:))
                .padding(.bottom, DSToken.Spacing.xxs)

            VStack(spacing: DSToken.Spacing.xs) {
                Text(page.title)
                    .font(.system(size: 22, weight: .bold))
                Text(page.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .id(page.id)
            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            .frame(height: 74, alignment: .top)

            Button(action: advance) {
                Text(pager.isLast ? "Get Started" : "Continue")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 220)
                    .contentTransition(.opacity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .padding(.top, DSToken.Spacing.xs)
        }
        .padding(.bottom, DSToken.Spacing.xl)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                if pager.isFirst { finish() } else { goBack() }
            } label: {
                Image(systemName: pager.isFirst ? "xmark" : "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentTransition(.symbolEffect(.replace))
            }
            .keyboardShortcut(backShortcut)
            .help(leadingLabel)
            .accessibilityLabel(leadingLabel)

            Spacer()

            Button(action: finish) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .keyboardShortcut(.cancelAction)
            .help("Skip the tour")
            .accessibilityLabel("Skip the tour")
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .padding(DSToken.Spacing.md)
    }

    private var leadingLabel: Text {
        pager.isFirst ? Text("Close") : Text("Back")
    }

    /// Left arrow steps back; on the first page there is nothing behind,
    /// and the button there closes instead.
    private var backShortcut: KeyboardShortcut? {
        pager.isFirst ? nil : KeyboardShortcut(.leftArrow, modifiers: [])
    }

    // MARK: Actions

    private var pageTurn: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : DSToken.Motion.pageTurn
    }

    private func advance() {
        guard !pager.isLast else { return finish() }
        _ = withAnimation(pageTurn) { pager.advance() }
    }

    private func goBack() {
        _ = withAnimation(pageTurn) { pager.goBack() }
    }

    private func go(to page: Int) {
        _ = withAnimation(pageTurn) { pager.go(to: page) }
    }

    private func finish() {
        dismiss()
    }
}

// MARK: - Page dots

/// The current page stretches into a capsule; the rest stay dots. Each dot
/// jumps to its page.
private struct PageDots: View {
    let count: Int
    let current: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    select(index)
                } label: {
                    Capsule()
                        .fill(index == current ? Color.primary : Color.primary.opacity(0.25))
                        .frame(width: index == current ? 18 : 6, height: 6)
                        // A dot is too small to aim at; the hit area spans
                        // the gap to its neighbours.
                        .padding(.horizontal, 2.5)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(Text("Page \(index + 1)"))
            }
        }
        .padding(.vertical, -6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
        .accessibilityValue(Text("\(current + 1)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(current + 1)
            case .decrement: select(current - 1)
            @unknown default: break
            }
        }
    }
}

// MARK: - Device

/// A MacBook drawn at any width: bezel, notch, screen and the base below it.
private struct MacBookFrame<Screen: View>: View {
    let width: CGFloat
    @ViewBuilder let screen: Screen

    /// The 14" panel, in points.
    static var screenAspect: CGFloat { 1512 / 982 }

    var body: some View {
        let bezel = width * 0.014
        let screenWidth = width - bezel * 2
        let screenHeight = screenWidth / Self.screenAspect

        VStack(spacing: 0) {
            screen
                .frame(width: screenWidth, height: screenHeight)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: width * 0.02,
                    bottomLeadingRadius: width * 0.006,
                    bottomTrailingRadius: width * 0.006,
                    topTrailingRadius: width * 0.02,
                    style: .continuous
                ))
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: width * 0.008,
                        bottomTrailingRadius: width * 0.008,
                        style: .continuous
                    )
                    .fill(.black)
                    .frame(width: width * 0.12, height: screenHeight * 0.034)
                }
                .padding(bezel)
                .background {
                    UnevenRoundedRectangle(
                        topLeadingRadius: width * 0.032,
                        bottomLeadingRadius: width * 0.01,
                        bottomTrailingRadius: width * 0.01,
                        topTrailingRadius: width * 0.032,
                        style: .continuous
                    )
                    .fill(Color(white: 0.05))
                    .stroke(Color(white: 0.42), lineWidth: 1)
                }

            base
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }

    private var base: some View {
        UnevenRoundedRectangle(
            bottomLeadingRadius: width * 0.03,
            bottomTrailingRadius: width * 0.03,
            style: .continuous
        )
        .fill(LinearGradient(
            colors: [Color(white: 0.82), Color(white: 0.6), Color(white: 0.42)],
            startPoint: .top,
            endPoint: .bottom
        ))
        .frame(width: width * 1.12, height: width * 0.022)
        .overlay(alignment: .top) {
            // The thumb scoop in the lip of the base.
            UnevenRoundedRectangle(
                bottomLeadingRadius: width * 0.008,
                bottomTrailingRadius: width * 0.008,
                style: .continuous
            )
            .fill(Color(white: 0.48))
            .frame(width: width * 0.15, height: width * 0.007)
        }
    }
}

// MARK: - Desktop

/// What is on the Mac's screen: wallpaper, menu bar, the app window and an
/// optional menu bar panel, laid out in the points they were captured at.
private struct OnboardingDesktop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let page: OnboardingPage

    /// The screen the screenshots were captured on.
    private static let screen = CGSize(width: 1512, height: 982)
    private static let menuBarHeight: CGFloat = 33
    /// A floating window centred on the screen, with wallpaper around it —
    /// a full-screen window leaves nothing to say "this is a Mac" at the
    /// tour's scale.
    private static let windowFrame = CGRect(x: 148, y: 105, width: 1216, height: 772)
    /// The quick-copy panel as it sat on screen, under the status item.
    ///
    /// Captured from the screen over a full-screen copy of this desktop —
    /// ``Wallpaper`` with the gallery shot at ``windowFrame`` — because the
    /// panel's material only renders its frosted blur against what is really
    /// behind it; captured on its own it comes out flat grey. The capture is
    /// then cut to the panel's rounded shape, so nothing of the real desktop
    /// shows at its corners, and the shadow is drawn here. Change the
    /// wallpaper, the window frame or the gallery shot and these need retaking.
    private static let panelFrame = CGRect(x: 1047, y: 37, width: 340, height: 420)

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.screen.width

            ZStack(alignment: .topLeading) {
                Wallpaper()

                screenshot(page.windowImage, clip: page.windowClip, in: Self.windowFrame, scale: scale)
                    // One layer, one shadow. Without the group SwiftUI shadows
                    // each layer on its own, and a clip laid over the shot casts
                    // a rectangular shadow across the window it sits in.
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.45), radius: 30 * scale, y: 14 * scale)

                MenuBar(scale: scale, statusItemCenter: Self.panelFrame.midX, isStatusItemOpen: page.panelImage != nil)
                    .frame(width: proxy.size.width, height: Self.menuBarHeight * scale)

                if let panel = page.panelImage {
                    screenshot(panel, in: Self.panelFrame, scale: scale)
                        .shadow(color: .black.opacity(0.35), radius: 22 * scale, y: 10 * scale)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func screenshot(
        _ name: String,
        clip: OnboardingClip? = nil,
        in frame: CGRect,
        scale: CGFloat
    ) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .frame(width: frame.width * scale, height: frame.height * scale)
            .overlay(alignment: .topLeading) {
                if let clip, !reduceMotion, let url = clip.url(for: colorScheme) {
                    LoopingClip(url: url)
                        // A new appearance is a different recording.
                        .id(url)
                        .frame(width: clip.frame.width * scale, height: clip.frame.height * scale)
                        .offset(x: clip.frame.minX * scale, y: clip.frame.minY * scale)
                }
            }
            // Keyed by image, so pages that share a shot keep it still while
            // the zoom moves, and only a real change blurs across.
            .id(name)
            .transition(.blurReplace)
            .offset(x: frame.minX * scale, y: frame.minY * scale)
    }
}

/// Plays a bundled clip on a loop, drawn as SwiftUI images rather than through
/// an `AVPlayerLayer`.
///
/// The tour blurs, zooms, clips and fades this shot. An AppKit-hosted player
/// would sit outside all of that: it flashes white when a transition
/// rasterises it, and paints over the fade at the bottom of the stage.
private struct LoopingClip: View {
    let url: URL

    @State private var player = LoopingClipPlayer()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            if let frame = player.frame(at: context.date) {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .onAppear { player.play(url) }
        .onDisappear { player.stop() }
    }
}

/// An `AVPlayer` looping one item, read back a frame at a time.
@MainActor
private final class LoopingClipPlayer {
    private let player = AVPlayer()
    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    private var loopObserver: NSObjectProtocol?
    /// The last frame decoded, held while the player has nothing newer.
    private var current: CGImage?

    func play(_ url: URL) {
        guard player.currentItem == nil else { return }
        let item = AVPlayerItem(url: url)
        item.add(output)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none
        player.replaceCurrentItem(with: item)
        // Each clip's end already dissolves into its start, so a plain seek
        // back loops it without a seam.
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [player] _ in
            player.seek(to: .zero)
        }
        player.play()
    }

    func stop() {
        player.pause()
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player.currentItem?.remove(output)
        player.replaceCurrentItem(with: nil)
        current = nil
    }

    func frame(at date: Date) -> CGImage? {
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        else { return current }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
        if let image { current = image }
        return current
    }
}

/// A deep blue-violet field in the spirit of the macOS 26 wallpaper.
private struct Wallpaper: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.55], [0.6, 0.45], [1, 0.6],
                [0, 1], [0.45, 1], [1, 1],
            ],
            colors: [
                Color(red: 0.12, green: 0.08, blue: 0.55), Color(red: 0.30, green: 0.14, blue: 0.80), Color(red: 0.16, green: 0.22, blue: 0.85),
                Color(red: 0.32, green: 0.24, blue: 0.92), Color(red: 0.52, green: 0.62, blue: 0.98), Color(red: 0.22, green: 0.30, blue: 0.86),
                Color(red: 0.10, green: 0.10, blue: 0.48), Color(red: 0.36, green: 0.40, blue: 0.92), Color(red: 0.14, green: 0.12, blue: 0.58),
            ]
        )
    }
}

/// The macOS menu bar, drawn to scale: app menus on the left, the Snippets
/// status item and the system extras on the right.
private struct MenuBar: View {
    let scale: CGFloat
    /// Where the status item sits, in screen points — the panel hangs from it.
    let statusItemCenter: CGFloat
    let isStatusItemOpen: Bool

    var body: some View {
        let font = Font.system(size: 13 * scale)

        ZStack(alignment: .leading) {
            HStack(spacing: 20 * scale) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 14 * scale))
                Text("Snippets").font(.system(size: 13 * scale, weight: .bold))
                ForEach(["File", "Edit", "View", "Window", "Help"], id: \.self) { Text($0) }
            }
            .padding(.leading, 22 * scale)

            Image(systemName: "scissors")
                .font(.system(size: 13 * scale, weight: .medium))
                .frame(width: 30 * scale, height: 22 * scale)
                .background {
                    Capsule()
                        .fill(.white.opacity(isStatusItemOpen ? 0.25 : 0))
                }
                .offset(x: (statusItemCenter - 15) * scale)

            HStack(spacing: 18 * scale) {
                Image(systemName: "battery.100percent")
                Image(systemName: "wifi")
                Image(systemName: "switch.2")
                Text("Wed 14 Oct  9:41")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 18 * scale)
        }
        .font(font)
        .foregroundStyle(.white)
        .lineLimit(1)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Presentation

private struct OnboardingTour: ViewModifier {
    @Environment(Onboarding.self) private var onboarding
    @Environment(LicenseAgreement.self) private var agreement

    func body(content: Content) -> some View {
        @Bindable var onboarding = onboarding
        content
            // Until the license is agreed to, its gate starts the tour once
            // its own sheet has gone.
            .task { if agreement.isAccepted { onboarding.presentIfNeeded() } }
            .sheet(isPresented: $onboarding.isPresented, onDismiss: onboarding.complete) {
                OnboardingView()
            }
    }
}

extension View {
    /// Presents the welcome tour on first launch, and whenever Help ▸ Welcome
    /// to Snippets asks for it. Attach once, at the app's root.
    func onboardingTour() -> some View {
        modifier(OnboardingTour())
    }
}

#Preview {
    OnboardingView()
}
