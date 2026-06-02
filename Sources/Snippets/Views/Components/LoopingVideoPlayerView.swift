import SwiftUI
import AVKit
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)
struct LoopingVideoPlayerView: NSViewRepresentable {
    let fileName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeNSView(context: Context) -> LoopingVideoContainerView {
        let view = LoopingVideoContainerView()
        view.configure(with: MediaManager.resolvedURL(for: fileName), videoGravity: videoGravity)
        return view
    }

    func updateNSView(_ nsView: LoopingVideoContainerView, context: Context) {
        nsView.configure(with: MediaManager.resolvedURL(for: fileName), videoGravity: videoGravity)
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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
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
        newLayer.frame = bounds
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
        playerLayer?.frame = bounds
    }
}
#else
struct LoopingVideoPlayerView: View {
    let fileName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    var body: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 32))
            .foregroundStyle(.secondary)
    }
}
#endif
