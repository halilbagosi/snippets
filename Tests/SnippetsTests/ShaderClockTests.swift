import XCTest
@testable import Snippets

final class ShaderClockTests: XCTestCase {
    func test_firstFrameStartsAtZero() {
        var clock = ShaderClock()
        clock.advance(to: 1_000)
        XCTAssertEqual(clock.elapsed, 0)
    }

    func test_accumulatesNormalFrameDeltas() {
        var clock = ShaderClock()
        clock.advance(to: 100)
        clock.advance(to: 100 + 1.0 / 120)
        clock.advance(to: 100 + 2.0 / 120)
        XCTAssertEqual(clock.elapsed, 2.0 / 120, accuracy: 1e-9)
    }

    /// The reason this type exists: an MTKView stops drawing while it cannot be
    /// seen, so the gap across a pause must not reach the shader.
    func test_pauseContributesAtMostOneClampedFrame() {
        var clock = ShaderClock()
        clock.advance(to: 0)
        clock.advance(to: 300) // five minutes occluded
        XCTAssertEqual(clock.elapsed, ShaderClock.maxFrameDelta, accuracy: 1e-9)
    }

    func test_frameRatesAboveTheClampAreNotSlowed() {
        // 5fps is slower than any usable shader and still must not be clamped.
        var clock = ShaderClock()
        clock.advance(to: 0)
        clock.advance(to: 0.2)
        XCTAssertEqual(clock.elapsed, 0.2, accuracy: 1e-9)
    }

    func test_backwardsClockStepDoesNotRewind() {
        var clock = ShaderClock()
        clock.advance(to: 10)
        clock.advance(to: 10.1)
        clock.advance(to: 4) // clock jumped backwards
        XCTAssertEqual(clock.elapsed, 0.1, accuracy: 1e-9)

        // ...and the clock keeps running from the new reference point.
        clock.advance(to: 4.1)
        XCTAssertEqual(clock.elapsed, 0.2, accuracy: 1e-9)
    }

    func test_elapsedIsMonotonic() {
        var clock = ShaderClock()
        var previous = clock.elapsed
        for step in stride(from: 0.0, through: 5.0, by: 0.05) {
            clock.advance(to: step)
            XCTAssertGreaterThanOrEqual(clock.elapsed, previous)
            previous = clock.elapsed
        }
    }
}
