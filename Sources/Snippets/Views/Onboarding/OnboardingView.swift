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
        /// Where a page's controls sit: under a Mac shrunk to make room,
        /// above the page dots.
        static let controlsTop: CGFloat = 290
        static let controlsHeight: CGFloat = 136
    }

    var body: some View {
        ZStack(alignment: .top) {
            stage
            controls
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

    // MARK: Controls

    private var controls: some View {
        ZStack {
            if let kind = page.controls {
                OnboardingControls(kind: kind)
                    .id(kind)
                    // Out quickly, in just after: two sets of controls
                    // fading through each other read as one garbled panel,
                    // and coming in late lets the Mac shrink out of the way
                    // first.
                    .transition(.asymmetric(
                        insertion: (reduceMotion
                            ? AnyTransition.opacity
                            : AnyTransition.opacity.combined(with: .offset(y: 14))
                        ).animation(DSToken.Motion.pageTurn.delay(0.16)),
                        removal: AnyTransition.opacity.animation(.easeOut(duration: 0.14))
                    ))
            }
        }
        .frame(width: Layout.cardSize.width, height: Layout.controlsHeight)
        .padding(.top, Layout.controlsTop)
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
    @Environment(AppearanceSettings.self) private var appearanceSettings

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
    private static let accentDissolve: Animation = .easeInOut(duration: 0.45)
    /// The agent session drawn over the window on the agents page.
    private static let terminalFrame = CGRect(x: 660, y: 330, width: 760, height: 470)

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / Self.screen.width

            ZStack(alignment: .topLeading) {
                Wallpaper()

                // Its own stack, so ``Dissolve``'s z-order only sorts one
                // shot against the one it replaces.
                ZStack(alignment: .topLeading) {
                    screenshot(windowImage, clip: page.windowClip, in: Self.windowFrame, scale: scale)
                }
                // One layer, one shadow. Without the group SwiftUI shadows
                // each layer on its own, and a clip laid over the shot casts
                // a rectangular shadow across the window it sits in. The
                // group also keeps the shadow steady while one shot
                // dissolves into the next.
                .compositingGroup()
                .shadow(color: .black.opacity(0.45), radius: 30 * scale, y: 14 * scale)
                // Picking an accent swaps the whole shot. The swatch's own
                // spring is a quick press response, which makes the swap read
                // as a cut; the shots dissolve on a slower curve instead.
                .animation(Self.accentDissolve, value: appearanceSettings.themeColorHex)

                if page.controls == .agents {
                    AgentSession(scale: scale)
                        .frame(width: Self.terminalFrame.width * scale, height: Self.terminalFrame.height * scale)
                        .shadow(color: .black.opacity(0.4), radius: 26 * scale, y: 12 * scale)
                        .offset(x: Self.terminalFrame.minX * scale, y: Self.terminalFrame.minY * scale)
                        .transition(.opacity.combined(with: .offset(y: 24 * scale)))
                }

                MenuBar(scale: scale, statusItemCenter: Self.panelFrame.midX, isStatusItemOpen: page.panelImage != nil)
                    .frame(width: proxy.size.width, height: Self.menuBarHeight * scale)

                ZStack(alignment: .topLeading) {
                    if let panel = page.panelImage {
                        screenshot(panel, in: Self.panelFrame, scale: scale, isPanel: true)
                    }
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.35), radius: 22 * scale, y: 10 * scale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    /// The appearance page shows the gallery in the accent you pick: one shot
    /// per preset, and the nearest of them for a custom colour.
    private var windowImage: String {
        guard page.controls == .appearance else { return page.windowImage }
        return OnboardingPage.accentWindowImage(forHex: appearanceSettings.themeColorHex)
    }

    private func screenshot(
        _ name: String,
        clip: OnboardingClip? = nil,
        in frame: CGRect,
        scale: CGFloat,
        isPanel: Bool = false
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
            .offset(x: frame.minX * scale, y: frame.minY * scale)
            // Keyed by image, so pages that share a shot keep it still while
            // the zoom moves, and only a real change dissolves across.
            .id(name)
            .transition(Dissolve.transition(holdingUntilCovered: !isPanel))
    }
}

/// Brings a shot in over the one it replaces, which stays opaque underneath
/// until the new one has covered it.
///
/// A plain cross-fade (or `.blurReplace`) fades both shots at once, so
/// halfway through neither covers the window and the wallpaper flashes
/// through it on every page turn. So the incoming shot fades in on top, and
/// the outgoing one is held, fully opaque and below it, until the fade is
/// over: its removal animation waits out ``holdDuration`` and then cuts.
///
/// No blur: magnified by the zoom, a blurred shot smears the window's edge
/// into the wallpaper, and the whole window goes to a pale haze for the
/// first frames of the turn.
private enum Dissolve {
    /// Longer than any fade it covers: the page turn's spring and the accent
    /// swap both settle well inside it.
    static let holdDuration: TimeInterval = 0.9

    /// The window always has a shot, so one leaving is always being
    /// covered. A menu bar panel can leave for nothing — the page after the
    /// last panel has none — and held, it would sit there whole for the
    /// length of the hold and then vanish. So a panel only waits long enough
    /// for a replacement to cover most of it, then fades.
    @MainActor
    static func transition(holdingUntilCovered: Bool) -> some Transition {
        AsymmetricTransition(
            insertion: Reveal(),
            removal: Hold().animation(
                holdingUntilCovered
                    ? .linear(duration: 0.01).delay(holdDuration)
                    : .easeOut(duration: 0.25).delay(0.2)
            )
        )
    }

    private struct Reveal: Transition {
        func body(content: Content, phase: TransitionPhase) -> some View {
            content
                .zIndex(1)
                .opacity(phase.isIdentity ? 1 : 0)
        }
    }

    private struct Hold: Transition {
        func body(content: Content, phase: TransitionPhase) -> some View {
            content
                .zIndex(0)
                .opacity(phase.isIdentity ? 1 : 0)
        }
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

// MARK: - Agent session

/// A terminal with an agent using Snippets over MCP, drawn to scale on the
/// desktop. Drawn, not captured: it stands for any agent, and stays crisp at
/// whatever size the tour shows it.
private struct AgentSession: View {
    let scale: CGFloat

    private struct Line: Identifiable {
        let id: Int
        let text: String
        var color = Color(white: 0.86)
        var indent: CGFloat = 0
    }

    private static let green = Color(red: 0.42, green: 0.85, blue: 0.52)
    private static let violet = Color(red: 0.70, green: 0.62, blue: 1.0)
    private static let muted = Color(white: 0.55)

    private static let lines: [Line] = [
        Line(id: 0, text: "> use my debounce snippet in SearchField.swift", color: .white),
        Line(id: 1, text: "⏺ snippets · find_snippets(\"debounce\")", color: violet),
        Line(id: 2, text: "⎿  Debounce — swift · utilities", color: muted, indent: 22),
        Line(id: 3, text: "⏺ snippets · use_snippet(\"Debounce\")", color: violet),
        Line(id: 4, text: "⎿  14 lines", color: muted, indent: 22),
        Line(id: 5, text: "⏺ Updated SearchField.swift", color: green),
        Line(id: 6, text: "⎿  +14 lines, search now waits 300 ms", color: muted, indent: 22),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8 * scale) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
            }
            .frame(height: 13 * scale)
            .padding(.leading, 18 * scale)
            .frame(height: 40 * scale)

            VStack(alignment: .leading, spacing: 13 * scale) {
                ForEach(Self.lines) { line in
                    Text(line.text)
                        .foregroundStyle(line.color)
                        .padding(.leading, line.indent * scale)
                }
            }
            .font(.system(size: 21 * scale, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 26 * scale)
            .padding(.top, 14 * scale)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11), in: .rect(cornerRadius: 16 * scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: max(0.5, scale))
        }
    }
}

// MARK: - Controls

/// The settings a page lets you change during the tour. They are the real
/// settings, applied as they change — the tour is in the window it styles.
private struct OnboardingControls: View {
    let kind: OnboardingPage.Controls

    var body: some View {
        switch kind {
        case .agents:
            #if !APP_STORE
            AgentControls()
            #else
            EmptyView()
            #endif
        case .appearance:
            VStack(spacing: DSToken.Spacing.sm) {
                ColorSchemePicker(tileSize: CGSize(width: 78, height: 50), spacing: 16)
                AccentColorPicker(spacing: 4)
            }
        }
    }
}

#if !APP_STORE
/// Agent access, its status, and the setup to paste into an agent.
private struct AgentControls: View {
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }
    private var accent: Color { appearanceSettings.themeColor }

    var body: some View {
        @Bindable var access = AgentAccess.shared

        VStack(spacing: DSToken.Spacing.sm) {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.safeAccentText(accent))
                    .frame(width: 30, height: 30)
                    .liquidGlassSurface(
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                        tint: accent.opacity(0.12),
                        shadowRadius: 3,
                        shadowY: 1
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Agent Access")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text(status(access))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                        .contentTransition(.opacity)
                }

                Spacer(minLength: 12)

                Toggle("Allow Agent Access", isOn: $access.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(accent)
            }
            .padding(.horizontal, DSToken.Spacing.md)
            .padding(.vertical, DSToken.Spacing.sm)
            .frame(width: 400)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                shadowRadius: 10,
                shadowY: 4
            )

            AgentSetupPicker()
                .controlSize(.regular)
                .disabled(!access.isEnabled)
        }
    }

    /// On with nothing serving behind it must say so, not look healthy.
    private func status(_ access: AgentAccess) -> String {
        if !access.isEnabled { return "Off — nothing listens until you turn it on" }
        if !access.isServing { return access.startProblem ?? "Starting…" }
        return access.allowsEdits
            ? "On — agents can find, use and save snippets"
            : "On — agents can find and use snippets; edits are in Settings"
    }
}
#endif

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
