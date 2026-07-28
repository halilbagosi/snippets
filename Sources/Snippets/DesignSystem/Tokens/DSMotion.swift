import SwiftUI

public extension DSToken {
    /// The app's motion scale.
    ///
    /// Entries are named by **intent**, not by number: pick the one that
    /// matches what the user is doing, so the same gesture times the same way
    /// everywhere and there is a single place to retune it.
    ///
    /// Two rules shaped these values:
    ///
    /// - **Frequency sets the budget.** Something hit hundreds of times a day
    ///   (row selection, hover) gets a short curve with no overshoot, because
    ///   at that rate any settle time reads as lag rather than personality.
    ///   Motion the user sees occasionally (overlays, toasts) can take longer.
    /// - **UI motion stays under 300ms**, overlays excepted — press feedback
    ///   100–160ms, small popovers 125–200ms, dropdowns 150–250ms, modals and
    ///   drawers 200–500ms.
    ///
    /// Prefer adding a *use case* here over hand-typing a spring at the call
    /// site. Springs that differ by 0.01–0.02 are indistinguishable in motion
    /// but look deliberate in a diff, which is how a codebase ends up with
    /// thirty of them.
    struct Motion {

        // MARK: - High frequency
        //
        // Fires constantly, often from the keyboard. Short, and springless:
        // an overshoot the user triggers fifty times an hour is noise.

        /// Row, tab and chip selection — including arrow-key navigation.
        public static let selection: Animation = .easeOut(duration: 0.12)

        /// Hover tint, glow and border changes.
        public static let hover: Animation = .easeOut(duration: 0.14)

        /// Press-down feedback on buttons and cards.
        public static let press: Animation = .easeOut(duration: 0.11)

        /// Release after a press. Deliberately slower than ``press``: pressing
        /// is the user's action and wants to feel immediate, while letting go
        /// is the system settling back.
        public static let release: Animation = .easeOut(duration: 0.14)

        // MARK: - State changes

        /// Small state flips: switches, colour swatches, icon pickers,
        /// favourite toggles, copy confirmations.
        public static let toggle: Animation = .spring(response: 0.28, dampingFraction: 0.86)

        /// Inline disclosure, and content that grows or reflows in place.
        public static let reveal: Animation = .spring(response: 0.34, dampingFraction: 0.9)

        // MARK: - Overlays

        /// Modals, editors, sheets and the snippet detail card.
        public static let overlay: Animation = .spring(response: 0.4, dampingFraction: 0.88)

        /// Toasts arrive on a spring…
        public static let toastIn: Animation = .spring(response: 0.34, dampingFraction: 0.88)

        /// …and leave immediately. Dismissal is the UI getting out of the way,
        /// so it should not take as long as the arrival did.
        public static let toastOut: Animation = .easeOut(duration: 0.18)

        // MARK: - Interruptible
        //
        // `interactiveSpring` carries velocity when it is retargeted mid-flight,
        // so these cover motion the user can reverse or restart before it
        // finishes. A fixed-duration curve would restart from zero instead.

        /// Gallery section collapse and expand.
        public static let collapse: Animation = .interactiveSpring(
            response: 0.28,
            dampingFraction: 0.96,
            blendDuration: 0.06
        )

        /// Grid reflow when cards are added, deleted or reordered.
        public static let gridReflow: Animation = .interactiveSpring(
            response: 0.42,
            dampingFraction: 0.9,
            blendDuration: 0.12
        )

        /// Pointer-tracked parallax on cards; retargets on every mouse move.
        public static let tilt: Animation = .interactiveSpring(
            response: 0.24,
            dampingFraction: 0.74
        )

        // MARK: - Entrances

        /// Grid card entrance, before any stagger delay.
        public static let entrance: Animation = .spring(response: 0.34, dampingFraction: 0.92)

        /// Delay added per item in a staggered group.
        public static let staggerStep: Double = 0.02

        /// Ceiling on the accumulated stagger, so a large grid never leaves the
        /// last card arriving noticeably late. Stagger is decorative — it must
        /// never gate interaction.
        public static let staggerCap: Double = 0.12

        /// ``entrance`` delayed by an item's position in its group.
        public static func staggeredEntrance(index: Int) -> Animation {
            entrance.delay(min(Double(index) * staggerStep, staggerCap))
        }

        /// Items leaving a section that is folding shut.
        ///
        /// Shorter than the entrance, and shorter than ``collapse`` itself: a
        /// section closing is the UI getting out of the way, and every frame
        /// the cards spend fading is a frame the layout below sits still.
        public static let sectionItemExit: Animation = .easeOut(duration: 0.16)

        /// Exit stagger, tighter than ``staggerStep`` / ``staggerCap``. The
        /// spread only has to be legible as an order, not admired.
        public static let exitStaggerStep: Double = 0.012

        /// Ceiling on the accumulated exit stagger.
        public static let exitStaggerCap: Double = 0.06

        /// ``sectionItemExit`` delayed by an item's position in its group.
        ///
        /// Pass a reversed index when a group is folding into a header above
        /// it, so the furthest card leaves first and the grid empties toward
        /// the thing it is collapsing into.
        public static func staggeredCollapse(index: Int) -> Animation {
            sectionItemExit.delay(min(Double(index) * exitStaggerStep, exitStaggerCap))
        }

        /// How long a container waits before unmounting staggered content that
        /// is on its way out.
        ///
        /// Deliberately shorter than the exit fully settles, so the layout
        /// starts closing while the last items are still going — waiting for a
        /// clean finish reads as a hang, and by this point the cards are faint
        /// enough that the overlap is not visible.
        public static let staggeredExitWindow: Double = 0.18
    }
}
