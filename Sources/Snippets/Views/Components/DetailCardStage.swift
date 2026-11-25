import AppKit
import QuartzCore
import SwiftUI

/// How the detail card travels between closed and open.
enum DetailCardPath: Equatable {
    /// Zoom out of (and back into) a point, from `startScale` of full size.
    /// `anchor` is in the card's own coordinates, top-left origin.
    case zoom(anchor: CGPoint, startScale: Double)
    /// The card's box runs from a gallery card's box (`source`, in the
    /// stage's coordinates) to its own, and a copy of the gallery card rides
    /// the same box on top, handing over.
    case morph(source: CGRect)
}

/// The window-wide layer that presents the snippet detail card: a dim over
/// everything behind it, the card, and — for the morph — a copy of the
/// gallery card it grows out of and shrinks back into.
///
/// Every frame of the open and close is animated by Core Animation, in the
/// render server, not by SwiftUI. Profiling showed why that matters: while
/// any SwiftUI animation runs, every Liquid Glass element in the window
/// refreshes its interaction state on every frame, and with the gallery,
/// toolbar and card full of glass that alone held the window to ~30fps.
/// Here SwiftUI only lays the card out once; the motion is keyframes on
/// layer transforms and opacities, so the main thread is idle while it plays.
///
/// The card and the copy are separate `NSHostingView`s carrying the
/// presenter's environment, so they render exactly as they would inline.
struct DetailCardStage: NSViewRepresentable {
    /// Whether the card should be open. Flipping it (re)targets the
    /// animation from wherever the card is now.
    var isOpen: Bool
    /// Bumped by the presenter for every new open, so a re-open of the same
    /// card from closed restarts from the gallery.
    var openToken: Int
    var card: AnyView?
    var galleryCopy: AnyView?
    /// Shared with the presenter; see `DetailStageLayout`.
    var layout: DetailStageLayout
    /// The card's frame, collapsed and with the preview expanded, in the
    /// stage's coordinates.
    var collapsedFrame: CGRect
    var expandedFrame: CGRect
    var path: DetailCardPath
    var dimOpacity: Double
    var stretch: Double
    var tuning: DetailMotionTuning.Values
    var reduceMotion: Bool
    /// A click outside the card while it is open.
    var onDismissTap: () -> Void
    /// The open has settled.
    var onOpened: () -> Void
    /// The close has fully finished and the card is off screen.
    var onClosed: () -> Void

    func makeNSView(context: Context) -> DetailCardStageView {
        DetailCardStageView()
    }

    func updateNSView(_ view: DetailCardStageView, context: Context) {
        view.onDismissTap = onDismissTap
        view.onOpened = onOpened
        view.onClosed = onClosed
        view.update(
            card: card,
            environment: context.environment,
            transaction: context.transaction,
            galleryCopy: galleryCopy,
            layout: layout,
            collapsedFrame: collapsedFrame,
            expandedFrame: expandedFrame,
            path: path,
            isOpen: isOpen,
            openToken: openToken,
            dimOpacity: dimOpacity,
            stretch: stretch,
            tuning: tuning,
            reduceMotion: reduceMotion
        )
    }
}

/// Where the card sits inside the stage, and whether its preview is
/// expanded. Observed directly by the views inside the stage's hosting view,
/// so changing it inside `withAnimation` — the expand button, a click on the
/// backdrop — animates the card's frame and its contents together in SwiftUI.
/// (Swapping the hosting view's `rootView` carries no animation, which is why
/// the expanded state cannot simply be passed down as a value.)
@MainActor
@Observable
final class DetailStageLayout {
    var isExpanded = false
    var collapsedFrame: CGRect = .zero
    var expandedFrame: CGRect = .zero

    var cardFrame: CGRect { isExpanded ? expandedFrame : collapsedFrame }

    /// Called right after the card's frame changes because the preview is
    /// expanding or collapsing, with the old and new frames, so the stage
    /// hit-tests and closes from the right frame. After, not before: SwiftUI
    /// can run an update of the presenter in between, and it must already
    /// see the new state.
    @ObservationIgnored var didChangeFrame: ((CGRect, CGRect) -> Void)?

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        let old = cardFrame
        isExpanded = expanded
        didChangeFrame?(old, cardFrame)
    }
}

/// Reads `DetailStageLayout.isExpanded` inside the stage's own view graph,
/// so content built by the presenter can react to it with animation.
struct StageExpansionReader<Content: View>: View {
    let layout: DetailStageLayout
    @ViewBuilder let content: (Bool) -> Content

    var body: some View { content(layout.isExpanded) }
}

/// The card's content and the presenter's environment, handed to the
/// stage's hosting view through observation rather than by replacing its
/// `rootView`: a new root view applies without animation, so every update
/// of the presenter during an expand — and the expand itself updates it —
/// snapped the card's contents to their new layout (the title and
/// description vanished instead of fading). An observed change carries the
/// transaction it was made in.
@MainActor
@Observable
final class StageCardContent {
    var view = AnyView(EmptyView())
    var environment = EnvironmentValues()
}

/// The card's root inside the stage's hosting view: the card, laid out at
/// `layout.cardFrame` in a host that covers the whole stage.
private struct StageCardRoot: View {
    let layout: DetailStageLayout
    let content: StageCardContent

    var body: some View {
        let frame = layout.cardFrame
        content.view
            .environment(\.self, content.environment)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // The host covers the whole window, title bar included; without
            // this SwiftUI lays the card out inside the toolbar's safe area
            // and everything lands a toolbar-height too low.
            .ignoresSafeArea()
    }
}

/// A view whose sublayers are transformed together: the hosted SwiftUI view
/// inside is laid out once at full size, and `sublayerTransform` moves and
/// scales it without any layout. Flipped, so transforms use the same
/// top-left coordinates as SwiftUI.
final class StageCardContainer: NSView {
    let host = NSHostingView(rootView: AnyView(EmptyView()))

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        host.sizingOptions = []
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() {
        super.layout()
        host.frame = bounds
    }
}

final class DetailCardStageView: NSView {
    var onDismissTap: () -> Void = {}
    var onOpened: () -> Void = {}
    var onClosed: () -> Void = {}

    private let dimLayer = CALayer()
    private let cardContainer = StageCardContainer()
    private let copyContainer = StageCardContainer()

    private var path: DetailCardPath = .zoom(anchor: .zero, startScale: 1)
    /// Where the card is laid out (or is expanding to): its frame at the end
    /// of whatever is animating. Hit testing and every transform use it.
    private var cardFrame: CGRect = .zero
    private var lastTuning = DetailMotionTuning.Values.defaults
    private var lastIsMorph = false
    private var isOpen = false
    private var openToken = 0
    private var dimTarget: Double = 0

    // Animated values, each a spring track the keyframes are sampled from.
    private var progress = Track(value: 0)
    private var cardOpacity = Track(value: 0)
    private var copyOpacity = Track(value: 0)
    private var dim = Track(value: 0)
    private var stretchAmount = Track(value: 0)

    private var settleWork: DispatchWorkItem?
    private let cardContent = StageCardContent()
    private var rootLayout: DetailStageLayout?
    private var layoutModel = DetailStageLayout()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(dimLayer)
        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.opacity = 0
        addSubview(cardContainer)
        addSubview(copyContainer)
        cardContainer.isHidden = true
        copyContainer.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimLayer.frame = bounds
        CATransaction.commit()
        // The card's host covers the whole stage and SwiftUI places the card
        // inside it; moving or resizing the card is then a transform on this
        // container, never a resize of the host.
        cardContainer.frame = bounds
    }

    // MARK: Events

    /// Transparent to clicks unless the card is open: then clicks on the
    /// card go to it, and clicks anywhere else close it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isOpen, !cardContainer.isHidden else { return nil }
        let local = convert(point, from: superview)
        if cardFrame.contains(local) {
            return cardContainer.hitTest(local) ?? self
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard !cardFrame.contains(local) else { return }
        onDismissTap()
    }

    override func scrollWheel(with event: NSEvent) {
        // Swallowed while the card is open, as the dimmed gallery was.
    }

    // MARK: Updates

    func update(
        card: AnyView?,
        environment: EnvironmentValues,
        transaction: Transaction,
        galleryCopy: AnyView?,
        layout: DetailStageLayout,
        collapsedFrame: CGRect,
        expandedFrame: CGRect,
        path newPath: DetailCardPath,
        isOpen newIsOpen: Bool,
        openToken newToken: Int,
        dimOpacity: Double,
        stretch: Double,
        tuning: DetailMotionTuning.Values,
        reduceMotion: Bool
    ) {
        layoutModel = layout
        lastTuning = tuning
        layout.didChangeFrame = { [weak self] old, new in self?.expandCard(from: old, to: new) }
        if layout.collapsedFrame != collapsedFrame || layout.expandedFrame != expandedFrame {
            // Window or column size changes: place the card outright.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                layout.collapsedFrame = collapsedFrame
                layout.expandedFrame = expandedFrame
            }
        }
        if rootLayout !== layout {
            rootLayout = layout
            cardContainer.host.rootView = AnyView(StageCardRoot(layout: layout, content: cardContent))
        }
        if let card {
            withTransaction(transaction) {
                cardContent.view = card
                cardContent.environment = environment
            }
        }
        if let galleryCopy {
            copyContainer.host.rootView = AnyView(galleryCopy.environment(\.self, environment))
        }
        path = newPath
        if case .morph(let source) = newPath {
            copyContainer.frame = source
        }
        cardFrame = layout.cardFrame

        let newDim = newIsOpen ? dimOpacity : 0
        let targetChanged = newIsOpen != isOpen || newToken != openToken || newDim != dimTarget
        guard targetChanged else { return }
        let restart = newIsOpen && (newToken != openToken) && !isOpen
        isOpen = newIsOpen
        openToken = newToken
        dimTarget = newDim
        animate(restartFromClosed: restart, stretch: stretch, tuning: tuning, reduceMotion: reduceMotion)
    }

    private func animate(restartFromClosed: Bool, stretch: Double, tuning: DetailMotionTuning.Values, reduceMotion: Bool) {
        let now = CACurrentMediaTime()
        let isMorph: Bool = { if case .morph = path { return true } else { return false } }()

        if restartFromClosed && cardContainer.isHidden {
            progress = Track(value: reduceMotion ? 1 : 0)
            cardOpacity = Track(value: 0)
            copyOpacity = Track(value: isMorph ? 1 : 0)
            stretchAmount = Track(value: stretch)
        }
        cardContainer.isHidden = false
        copyContainer.isHidden = !isMorph
        if restartFromClosed {
            // A new card's content reaches the host through observation, which
            // SwiftUI applies on its next update — after this transaction has
            // committed and the open has started, so the card flew open empty
            // for its first frames. Lay it out now, with the first keyframe.
            if let layout = rootLayout {
                cardContainer.host.rootView = AnyView(StageCardRoot(layout: layout, content: cardContent))
            }
            cardContainer.host.layoutSubtreeIfNeeded()
            if isMorph { copyContainer.host.layoutSubtreeIfNeeded() }
        }

        let slow = tuning.slowMotion
        if isOpen {
            progress.retarget(to: 1, duration: (isMorph ? tuning.morphInDuration : tuning.zoomInDuration) * slow, at: now)
            stretchAmount.retarget(to: stretch, duration: (isMorph ? tuning.morphInDuration : tuning.zoomInDuration) * slow, at: now)
            cardOpacity.retarget(to: 1, duration: (isMorph ? tuning.morphFadeInDuration : tuning.fadeInDuration) * slow, at: now)
            copyOpacity.retarget(to: 0, duration: tuning.morphCardFadeOutDuration * slow, at: now)
        } else {
            progress.retarget(to: reduceMotion ? 1 : 0, duration: (isMorph ? tuning.morphOutDuration : tuning.zoomOutDuration) * slow, at: now)
            stretchAmount.retarget(to: 0, duration: (isMorph ? tuning.morphOutDuration : tuning.zoomOutDuration) * slow, at: now)
            // A morph hands over late: the card keeps its own content while
            // it shrinks, and cross-fades into the gallery card only near the
            // end, as an app closes back into its icon. Handing over at once
            // showed the gallery card's copy stretched to the full detail
            // card, big and faded. Only from rest — a close that interrupts an
            // open turns its fades round at once, carrying their speed.
            let atRest = cardOpacity.value(at: now) >= 1 && copyOpacity.value(at: now) <= 0
            let handover = isMorph && atRest ? now + tuning.morphCloseHandoverDelay * slow : now
            cardOpacity.retarget(to: 0, duration: (isMorph ? tuning.morphFadeOutDuration : tuning.fadeOutDuration) * slow, at: handover)
            copyOpacity.retarget(to: isMorph ? 1 : 0, duration: tuning.morphCardFadeInDuration * slow, at: handover)
        }
        dim.retarget(to: dimTarget, duration: 0.3 * slow, at: now)

        lastIsMorph = isMorph
        applyKeyframes(from: now, isMorph: isMorph)
        scheduleSettle(now: now)
    }

    private var allTracks: [Track] { [progress, cardOpacity, copyOpacity, dim, stretchAmount] }

    private func scheduleSettle(now: CFTimeInterval) {
        settleWork?.cancel()
        let settle = allTracks.map(\.endTime).max().map { max($0 - now, 0) } ?? 0
        let work = DispatchWorkItem { [weak self] in self?.settled() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: work)
    }

    /// The preview expanding or collapsing. SwiftUI animates the card's
    /// frame and contents inside the host — the preview grows out of its
    /// place in the card while the rest steps aside — so the stage only
    /// tracks the new frame, and, if a close is under way, carries it on
    /// from there.
    private func expandCard(from old: CGRect, to new: CGRect) {
        cardFrame = new
        if !isOpen, !cardContainer.isHidden {
            applyKeyframes(from: CACurrentMediaTime(), isMorph: lastIsMorph)
        }
    }

    /// Keyframes are added with `beginTime` 0, so Core Animation starts them
    /// when the transaction actually commits — after the main thread has
    /// finished laying out whatever changed — instead of at the moment they
    /// were requested, which skipped the start of the motion whenever the
    /// first frame took a while. Once committed, shift the tracks to the real
    /// start so later retargets continue from the right place.
    private func realign(expected: CFTimeInterval) {
        guard let actual = cardContainer.layer?.animation(forKey: "stage.transform")?.beginTime,
              actual > 0 else { return }
        let delta = actual - expected
        guard delta > 0.001 else { return }
        progress.shift(by: delta)
        cardOpacity.shift(by: delta)
        copyOpacity.shift(by: delta)
        dim.shift(by: delta)
        stretchAmount.shift(by: delta)
        scheduleSettle(now: CACurrentMediaTime())
    }

    private func settled() {
        if isOpen {
            onOpened()
        } else {
            cardContainer.isHidden = true
            copyContainer.isHidden = true
            onClosed()
        }
    }

    /// Samples every track from `start` until they all settle and hands the
    /// result to Core Animation as keyframes, then sets the layers' model
    /// values to where they end.
    private func applyKeyframes(from start: CFTimeInterval, isMorph: Bool) {
        let end = allTracks.map(\.endTime).max() ?? start
        let duration = max(end - start, 1.0 / 120)
        let steps = max(Int(duration * 120), 2)

        var cardTransforms: [NSValue] = []
        var copyTransforms: [NSValue] = []
        var cardOpacities: [NSNumber] = []
        var copyOpacities: [NSNumber] = []
        var dims: [NSNumber] = []
        for i in 0...steps {
            let t = start + duration * Double(i) / Double(steps)
            let p = progress.value(at: t)
            let s = stretchAmount.value(at: t)
            let (openT, copyT) = transforms(progress: p, stretch: s)
            cardTransforms.append(NSValue(caTransform3D: openT))
            copyTransforms.append(NSValue(caTransform3D: copyT))
            cardOpacities.append(NSNumber(value: min(max(cardOpacity.value(at: t), 0), 1)))
            copyOpacities.append(NSNumber(value: min(max(copyOpacity.value(at: t), 0), 1)))
            dims.append(NSNumber(value: min(max(dim.value(at: t), 0), 1)))
        }

        func keyframes(_ keyPath: String, _ values: [Any]) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.duration = duration
            // 0: start at commit; see `realign(expected:)`.
            animation.beginTime = 0
            animation.calculationMode = .linear
            animation.fillMode = .both
            animation.isRemovedOnCompletion = true
            return animation
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cardLayer = cardContainer.layer
        let cardHostLayer = cardContainer.host.layer
        let copyLayer = copyContainer.layer
        let copyHostLayer = copyContainer.host.layer

        cardLayer?.sublayerTransform = cardTransforms.last!.caTransform3DValue
        cardLayer?.add(keyframes("sublayerTransform", cardTransforms), forKey: "stage.transform")
        cardHostLayer?.opacity = cardOpacities.last!.floatValue
        cardHostLayer?.add(keyframes("opacity", cardOpacities), forKey: "stage.opacity")

        if isMorph {
            copyLayer?.sublayerTransform = copyTransforms.last!.caTransform3DValue
            copyLayer?.add(keyframes("sublayerTransform", copyTransforms), forKey: "stage.transform")
            copyHostLayer?.opacity = copyOpacities.last!.floatValue
            copyHostLayer?.add(keyframes("opacity", copyOpacities), forKey: "stage.opacity")
        }

        dimLayer.opacity = dims.last!.floatValue
        dimLayer.add(keyframes("opacity", dims), forKey: "stage.opacity")
        CATransaction.commit()
        DispatchQueue.main.async { [weak self] in self?.realign(expected: start) }
    }

    /// The card's and the copy's transforms at one point of the trip.
    private func transforms(progress p: Double, stretch: Double) -> (CATransform3D, CATransform3D) {
        let clamped = min(max(p, 0), 1)
        let bump = 1 + stretch * sin(.pi * clamped)
        let to = cardFrame
        guard to.width > 0, to.height > 0 else { return (CATransform3DIdentity, CATransform3DIdentity) }

        // The card's host covers the whole stage, so these transforms are in
        // stage coordinates: everything is about `to`, the card's frame.
        func stretchFromTop(_ edge: CGFloat) -> CATransform3D {
            var t = CATransform3DMakeTranslation(0, -edge, 0)
            t = CATransform3DConcat(t, CATransform3DMakeScale(1, bump, 1))
            return CATransform3DConcat(t, CATransform3DMakeTranslation(0, edge, 0))
        }

        switch path {
        case .zoom(let anchor, let startScale):
            let scale = startScale + (1 - startScale) * p
            let a = CGPoint(x: to.minX + anchor.x, y: to.minY + anchor.y)
            // Stretch from the card's top edge, then zoom about the anchor.
            var t = stretchFromTop(to.minY)
            t = CATransform3DConcat(t, CATransform3DMakeTranslation(-a.x, -a.y, 0))
            t = CATransform3DConcat(t, CATransform3DMakeScale(scale, scale, 1))
            t = CATransform3DConcat(t, CATransform3DMakeTranslation(a.x, a.y, 0))
            return (t, CATransform3DIdentity)

        case .morph(let from):
            guard from.width > 0, from.height > 0 else { return (CATransform3DIdentity, CATransform3DIdentity) }
            func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(p) }
            let box = CGRect(
                x: lerp(from.minX, to.minX),
                y: lerp(from.minY, to.minY),
                width: lerp(from.width, to.width),
                height: lerp(from.height, to.height) * CGFloat(bump)
            )
            // The card (host covers the stage, card at `to`): map `to` onto
            // `box`. The copy (host exactly at `from`, local coordinates):
            // map its bounds onto `box`.
            let sx = box.width / to.width, sy = box.height / to.height
            let card = CATransform3DConcat(
                CATransform3DMakeScale(sx, sy, 1),
                CATransform3DMakeTranslation(box.minX - to.minX * sx, box.minY - to.minY * sy, 0)
            )
            let copy = CATransform3DConcat(
                CATransform3DMakeScale(box.width / from.width, box.height / from.height, 1),
                CATransform3DMakeTranslation(box.minX - from.minX, box.minY - from.minY, 0)
            )
            return (card, copy)
        }
    }
}

/// One animated value on a bounce-free spring that can be retargeted at any
/// moment, carrying its current velocity into the new target — so a close
/// mid-open turns round smoothly.
private struct Track {
    private var from: Double
    private var to: Double
    private var startTime: CFTimeInterval = 0
    private var initialVelocity: Double = 0
    private var spring = Spring(duration: 0.3, bounce: 0)

    init(value: Double) {
        from = value
        to = value
    }

    var endTime: CFTimeInterval {
        from == to && initialVelocity == 0 ? startTime : startTime + spring.settlingDuration
    }

    func value(at time: CFTimeInterval) -> Double {
        guard from != to || initialVelocity != 0 else { return to }
        let elapsed = max(time - startTime, 0)
        if elapsed >= spring.settlingDuration { return to }
        return from + spring.value(target: to - from, initialVelocity: initialVelocity, time: elapsed)
    }

    func velocity(at time: CFTimeInterval) -> Double {
        guard from != to || initialVelocity != 0 else { return 0 }
        let elapsed = max(time - startTime, 0)
        if elapsed >= spring.settlingDuration { return 0 }
        return spring.velocity(target: to - from, initialVelocity: initialVelocity, time: elapsed)
    }

    mutating func shift(by delta: CFTimeInterval) {
        startTime += delta
    }

    mutating func retarget(to target: Double, duration: Double, at time: CFTimeInterval) {
        let current = value(at: time)
        let velocity = velocity(at: time)
        from = current
        to = target
        startTime = time
        initialVelocity = velocity
        spring = Spring(duration: max(duration, 0.01), bounce: 0)
    }
}
