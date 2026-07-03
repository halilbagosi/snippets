import SwiftUI
import AVKit
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)
struct LoopingVideoPlayerView: NSViewRepresentable {
    let fileName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var zoomScale: CGFloat = 1
    var zoomOffset: CGSize = .zero

    func makeNSView(context: Context) -> LoopingVideoContainerView {
        let view = LoopingVideoContainerView()
        view.configure(with: MediaManager.resolvedURL(for: fileName), videoGravity: videoGravity)
        view.setZoom(scale: zoomScale, offset: zoomOffset)
        return view
    }

    func updateNSView(_ nsView: LoopingVideoContainerView, context: Context) {
        nsView.configure(with: MediaManager.resolvedURL(for: fileName), videoGravity: videoGravity)
        nsView.setZoom(scale: zoomScale, offset: zoomOffset)
    }

    static func dismantleNSView(_ nsView: LoopingVideoContainerView, coordinator: ()) {
        nsView.teardown()
    }
}

final class LoopingVideoContainerView: NSView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: NSObjectProtocol?
    private var currentURL: URL?
    private var currentGravity: AVLayerVideoGravity = .resizeAspectFill
    private var zoomScale: CGFloat = 1
    private var zoomOffset: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
    }

    func configure(with url: URL, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        if currentURL == url, currentGravity == videoGravity, player != nil { return }
        teardown()
        currentURL = url
        currentGravity = videoGravity

        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = true
        newPlayer.actionAtItemEnd = .none

        let newLayer = AVPlayerLayer(player: newPlayer)
        newLayer.videoGravity = videoGravity
        // Bounds + position instead of frame: frame is undefined once the
        // layer carries a zoom transform.
        newLayer.bounds = bounds
        newLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer?.addSublayer(newLayer)

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        newPlayer.play()

        player = newPlayer
        playerLayer = newLayer
        applyZoom()
    }

    func setZoom(scale: CGFloat, offset: CGSize) {
        guard scale != zoomScale || offset != zoomOffset else { return }
        zoomScale = scale
        zoomOffset = offset
        applyZoom()
    }

    private func applyZoom() {
        guard let playerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The backing layer is y-up (view is not flipped); SwiftUI offsets are y-down.
        playerLayer.setAffineTransform(
            CGAffineTransform(translationX: zoomOffset.width, y: -zoomOffset.height)
                .scaledBy(x: zoomScale, y: zoomScale)
        )
        CATransaction.commit()
    }

    func teardown() {
        player?.pause()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
        currentURL = nil
        currentGravity = .resizeAspectFill
    }

    override func layout() {
        super.layout()
        guard let playerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.bounds = bounds
        playerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }
}
#else
struct LoopingVideoPlayerView: View {
    let fileName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    var zoomScale: CGFloat = 1
    var zoomOffset: CGSize = .zero

    var body: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 32))
            .foregroundStyle(.secondary)
    }
}
#endif
