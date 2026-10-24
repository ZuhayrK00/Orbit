import XCTest
@testable import OrbitCore

final class WheelPresentationTests: XCTestCase {
    func testOldSettingsGainWheelDefaultsWithoutChangingTriggersOrSlots() throws {
        var original = OrbitConfiguration()
        original.keyboardLabel = "⌃Q"; original.keyCode = 12; original.wheelDiameter = 520
        let restored = try JSONDecoder().decode(OrbitConfiguration.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.wheel, WheelOptions())
        XCTAssertEqual(restored.keyboardLabel, "⌃Q")
        XCTAssertEqual(restored.slots, original.slots)
        XCTAssertEqual(restored.wheelDiameter, 520)
        let partial = try JSONDecoder().decode(WheelOptions.self, from: Data("{\"showLabels\":false,\"toolWidth\":9999}".utf8))
        XCTAssertFalse(partial.showLabels); XCTAssertTrue(partial.animate); XCTAssertEqual(partial.toolWidth, 600)
    }
    func testFinderSelectionAndDropsDoNotDismissFileTools() {
        for pinned in [true, false] {
            XCTAssertFalse(WheelDismissal.outsideClickCloses(section: .files, pinned: pinned, processing: false, enabled: true, modal: false))
        }
        XCTAssertFalse(WheelDismissal.outsideClickCloses(section: .timer, pinned: true, processing: false, enabled: true, modal: false))
        XCTAssertFalse(WheelDismissal.outsideClickCloses(section: .timer, pinned: false, processing: true, enabled: true, modal: false))
        XCTAssertFalse(WheelDismissal.outsideClickCloses(section: nil, pinned: false, processing: false, enabled: true, modal: true))
        XCTAssertFalse(WheelDismissal.outsideClickCloses(section: .timer, pinned: false, processing: false, enabled: false, modal: false))
        XCTAssertTrue(WheelDismissal.outsideClickCloses(section: .timer, pinned: false, processing: false, enabled: true, modal: false))
        XCTAssertTrue(WheelDismissal.outsideClickCloses(section: nil, pinned: false, processing: false, enabled: true, modal: false))
    }
    func testWheelAndTallToolsStayWithinDisplaysIncludingNegativeOrigins() {
        for screen in [CGRect(x: 0, y: 30, width: 1440, height: 870), CGRect(x: -1920, y: -200, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 640, height: 480)] {
            for point in [screen.origin, CGPoint(x: screen.maxX, y: screen.maxY), CGPoint(x: screen.midX, y: screen.midY)] {
                let layout = WheelLayout(screen: screen, pointer: point, diameter: 680, toolWidth: 600, placement: .pointer)
                XCTAssertTrue(screen.contains(layout.frame))
                XCTAssertLessThanOrEqual(layout.diameter, layout.frame.width)
                XCTAssertLessThanOrEqual(layout.toolHeightLimit, layout.frame.height)
            }
        }
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let centered = WheelLayout(screen: screen, pointer: .zero, diameter: 460, toolWidth: 460, placement: .screenCenter)
        XCTAssertEqual(centered.frame.midX, screen.midX); XCTAssertEqual(centered.frame.midY, screen.midY)
    }
    func testCircleMorphSettlesAndRetainsVelocityWhenReversed() {
        let wheel = WheelMotion.Pose(size: CGSize(width: 460, height: 460), radius: 230)
        let panel = WheelMotion.Pose(size: CGSize(width: 520, height: 650), radius: 26)
        let opening = WheelMotion(from: wheel, to: panel)
        XCTAssertEqual(opening.sample(at: 0).pose, wheel)
        XCTAssertEqual(opening.sample(at: opening.duration).pose, panel)
        let interrupted = opening.sample(at: 0.12)
        let back = WheelMotion(from: interrupted.pose, velocity: interrupted.velocity, radiusVelocity: interrupted.radiusVelocity, to: wheel)
        let first = back.sample(at: 0)
        XCTAssertEqual(first.pose.size.width, interrupted.pose.size.width, accuracy: 0.0001)
        XCTAssertEqual(first.velocity.height, interrupted.velocity.height, accuracy: 0.0001)
        XCTAssertEqual(first.radiusVelocity, interrupted.radiusVelocity, accuracy: 0.0001)
        XCTAssertEqual(back.sample(at: back.duration).pose, wheel)
        for i in 0...240 {
            let pose = back.sample(at: Double(i) / 120).pose
            XCTAssertGreaterThan(pose.size.width, 0); XCTAssertGreaterThan(pose.size.height, 0)
            XCTAssertTrue(pose.radius.isFinite)
        }
    }
}
