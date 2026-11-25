import SwiftUI

/// Every number behind the snippet detail card's open and close: how long
/// the zoom and fade take, how small the card starts, how much it warps and
/// blurs on the way.
///
/// Release builds always use ``Values/defaults``. Debug builds can change
/// them live from Debug ▸ Detail Motion… (`DetailMotionTuningView`); those
/// edits persist in UserDefaults so a relaunch keeps them, and Reset puts the
/// defaults back. Once a set feels right, copy it from that panel into
/// ``Values/defaults``.
@MainActor
@Observable
final class DetailMotionTuning {
    static let shared = DetailMotionTuning()

    struct Values: Codable, Equatable {
        /// Scales every duration below: 2 is half speed. For inspecting
        /// motion frame by frame; ship at 1.
        var slowMotion: Double = 1

        /// Morph: the clicked gallery card itself grows into the detail card
        /// and shrinks back, as an app icon opens into its app. Off: the
        /// detail card zooms out of the click point instead.
        var morph: Bool = true
        /// How long the morph's copy of the gallery card takes to fade out as
        /// the card opens, handing over to the detail card's content. Short:
        /// the copy is stretched to the detail card's size as it grows, and
        /// left visible for long it read as a big faded gallery card.
        var morphCardFadeOutDuration: Double = 0.1
        /// …and to fade back in as it closes, so the gallery card is solid
        /// when it lands.
        var morphCardFadeInDuration: Double = 0.14
        /// The morph's own open and close, on bounce-free springs.
        var morphInDuration: Double = 0.3
        var morphOutDuration: Double = 0.26
        /// The detail card's content fading in during a morph, overlapping
        /// the gallery card's copy fading out.
        var morphFadeInDuration: Double = 0.1
        /// The detail card's content fading out during a morph's close,
        /// overlapping the gallery card's copy fading back in.
        var morphFadeOutDuration: Double = 0.14
        /// How far into a morph's close the detail card's content starts
        /// handing over to the gallery card's copy. Until then the card
        /// shrinks with its own content.
        var morphCloseHandoverDelay: Double = 0.1
        /// Blur radius the gallery card's copy reaches as it fades out (and
        /// starts from as it fades back in), so the handover dissolves.
        var morphCardBlur: Double = 10

        /// The card growing out of the clicked gallery card, on a
        /// bounce-free spring (overshoot reads as wobble). A spring keeps
        /// its velocity when interrupted, so a close mid-open turns round
        /// smoothly.
        var zoomInDuration: Double = 0.34
        /// Shrinking back into it, a little faster than opening.
        var zoomOutDuration: Double = 0.3
        /// The card turns opaque early in its growth, so a solid card
        /// travels rather than a ghost of one; the blur clearing over the
        /// same stretch hides the moment it appears.
        var fadeInDuration: Double = 0.16
        /// Leaving, it fades from the first frame and is gone before the
        /// zoom has it back at a gallery card's size — fading late left a
        /// washed-out white card over the gallery card.
        var fadeOutDuration: Double = 0.22

        /// The card's size when it leaves the click, as a fraction of its
        /// full size: roughly a gallery card's width over the detail card's.
        var startScale: Double = 0.32
        /// How much the card's bottom stretches down mid-way open, as a
        /// fraction of its height: 0.06 is 6% taller at the peak. Gone by
        /// the time it lands.
        var warp: Double = 0.09
        /// Blur radius the card starts an open with, clearing over
        /// ``blurInDuration``. Off by default: blurring the first frame
        /// makes SwiftUI snapshot the card's AppKit views before anything is
        /// drawn, which delays the start of the open noticeably.
        var openBlur: Double = 0
        /// How long an open takes to go from ``openBlur`` to sharp.
        var blurInDuration: Double = 0.08
        /// Blur radius the card reaches as a close fades it out. Cheaper
        /// than an open blur — the card is already on screen — so it stays
        /// on, lightly.
        var closeBlur: Double = 6

        /// The preview expanding to fill the window, and collapsing back.
        var expandDuration: Double = 0.36

        static let defaults = Values()

        var zoomIn: Animation { .smooth(duration: zoomInDuration * slowMotion) }
        var zoomOut: Animation { .smooth(duration: zoomOutDuration * slowMotion) }
        // Every curve is a bounce-free spring, fades and blur included: a
        // spring that is interrupted carries its current speed into the new
        // target, where a timing curve restarts from rest — the jolt that
        // made a close mid-open, or a re-open mid-close, feel rough.
        var fadeIn: Animation { .smooth(duration: fadeInDuration * slowMotion) }
        var blurIn: Animation { .smooth(duration: blurInDuration * slowMotion) }
        var morphIn: Animation { .smooth(duration: morphInDuration * slowMotion) }
        var morphOut: Animation { .smooth(duration: morphOutDuration * slowMotion) }
        var morphFadeIn: Animation { .smooth(duration: morphFadeInDuration * slowMotion) }
        var morphCardFadeOut: Animation { .smooth(duration: morphCardFadeOutDuration * slowMotion) }
        var morphFadeOut: Animation { .smooth(duration: morphFadeOutDuration * slowMotion) }
        var morphCardFadeIn: Animation { .smooth(duration: morphCardFadeInDuration * slowMotion) }
        var fadeOut: Animation { .smooth(duration: fadeOutDuration * slowMotion) }
    }

    #if DEBUG
    var values: Values {
        didSet { save() }
    }

    private static let defaultsKey = "debug.detailMotionTuning"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Values.self, from: data) {
            values = saved
        } else {
            values = .defaults
        }
    }

    func reset() {
        values = .defaults
    }

    private func save() {
        if values == .defaults {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
    #else
    let values = Values.defaults
    private init() {}
    #endif
}
