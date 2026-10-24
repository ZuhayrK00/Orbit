import XCTest
@testable import OrbitCore

final class NotchMotionTests: XCTestCase {
    private let closed = CGSize(width: 208, height: 38)
    private let opened = CGSize(width: 532, height: 390)

    func testOpeningHeightLeadsWidthAndSettlesWithLimitedBounce() {
        let motion = NotchMotion(from: closed, to: opened)
        let early = motion.sample(at: 0.10).size
        XCTAssertGreaterThan((early.height - closed.height) / (opened.height - closed.height),
                             (early.width - closed.width) / (opened.width - closed.width))
        var peak = CGSize.zero
        for step in 0...1000 {
            let size = motion.sample(at: Double(step) / 1000 * motion.duration).size
            peak.width = max(peak.width, size.width); peak.height = max(peak.height, size.height)
            XCTAssertLessThanOrEqual(size.width, motion.envelope.width)
            XCTAssertLessThanOrEqual(size.height, motion.envelope.height)
        }
        XCTAssertGreaterThan(peak.width, opened.width)
        XCTAssertGreaterThan(peak.height, opened.height)
        XCTAssertLessThanOrEqual(peak.width - opened.width, 12.01)
        XCTAssertLessThanOrEqual(peak.height - opened.height, 12.01)
        assertSettles(motion)
    }

    func testClosingPullsUpBeforeNarrowingWithoutCrossingCamera() {
        let motion = NotchMotion(from: opened, to: closed)
        let early = motion.sample(at: 0.10).size
        XCTAssertGreaterThan((opened.height - early.height) / (opened.height - closed.height),
                             (opened.width - early.width) / (opened.width - closed.width))
        var previous = opened
        for step in 1...240 {
            let size = motion.sample(at: Double(step) / 240 * motion.duration).size
            XCTAssertGreaterThanOrEqual(size.width, closed.width)
            XCTAssertGreaterThanOrEqual(size.height, closed.height)
            XCTAssertLessThanOrEqual(size.width, previous.width)
            XCTAssertLessThanOrEqual(size.height, previous.height)
            previous = size
        }
        assertSettles(motion)
    }

    func testReversalsAndContentMeasurementsPreservePositionAndVelocity() {
        var motion = NotchMotion(from: closed, to: opened)
        for target in [closed, opened, CGSize(width: 532, height: 610), closed, opened] {
            let interrupted = motion.sample(at: 0.08)
            motion = NotchMotion(from: interrupted.size, velocity: interrupted.velocity, to: target)
            let resumed = motion.sample(at: 0)
            XCTAssertEqual(resumed.size.width, interrupted.size.width, accuracy: 0.000001)
            XCTAssertEqual(resumed.size.height, interrupted.size.height, accuracy: 0.000001)
            XCTAssertEqual(resumed.velocity.width, interrupted.velocity.width, accuracy: 0.000001)
            XCTAssertEqual(resumed.velocity.height, interrupted.velocity.height, accuracy: 0.000001)
            for frame in 0...480 {
                let sample = motion.sample(at: Double(frame) / 240).size
                XCTAssertGreaterThanOrEqual(sample.width, closed.width)
                XCTAssertGreaterThanOrEqual(sample.height, closed.height)
                XCTAssertLessThanOrEqual(sample.width, motion.envelope.width)
                XCTAssertLessThanOrEqual(sample.height, motion.envelope.height)
            }
            assertSettles(motion)
        }
    }

    func testLiveReadoutWidthFitsQuietlyAtCameraHeight() {
        for target in [CGSize(width: 352, height: 38), CGSize(width: 208, height: 38)] {
            let motion = NotchMotion(from: CGSize(width: 306, height: 38), to: target, steadyWidth: true)
            for frame in 0...240 {
                let size = motion.sample(at: Double(frame) / 240 * motion.duration).size
                XCTAssertEqual(size.height, 38)
                XCTAssertTrue((min(306, target.width)...max(306, target.width)).contains(size.width))
            }
            assertSettles(motion)
        }
    }

    func testLargePagesAndZeroTravelHaveBoundedBackingAndNoSettleJump() {
        for target in [CGSize(width: 900, height: 1200), closed] {
            let motion = NotchMotion(from: closed, to: target)
            XCTAssertLessThanOrEqual(motion.envelope.width, target.width + 14)
            XCTAssertLessThanOrEqual(motion.envelope.height, target.height + 14)
            assertSettles(motion)
        }
    }

    private func assertSettles(_ motion: NotchMotion, file: StaticString = #filePath, line: UInt = #line) {
        let before = motion.sample(at: motion.duration - 0.0001)
        XCTAssertLessThan(abs(before.size.width - motion.target.width), 0.11, file: file, line: line)
        XCTAssertLessThan(abs(before.size.height - motion.target.height), 0.11, file: file, line: line)
        XCTAssertEqual(motion.sample(at: motion.duration).size, motion.target, file: file, line: line)
        XCTAssertEqual(motion.sample(at: motion.duration).velocity, .zero, file: file, line: line)
    }
}
