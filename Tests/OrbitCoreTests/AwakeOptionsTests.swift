import XCTest
@testable import OrbitCore

final class AwakeOptionsTests: XCTestCase {
    func testExistingConfigurationUsesOptionalAwakeDefaultsAndRoundTripsChanges() throws {
        let old = try JSONEncoder().encode(OrbitConfiguration())
        let restored = try JSONDecoder().decode(OrbitConfiguration.self, from: old)
        XCTAssertNil(restored.awakeSettings)
        XCTAssertTrue(restored.awake.allowDisplaySleep)
        XCTAssertFalse(restored.awake.startOnLaunch)
        XCTAssertFalse(restored.awake.automationEnabled)
        var configured = restored
        var awake = AwakeOptions(); awake.startOnLaunch = true; awake.movePointer = true; awake.pointerInterval = 120
        configured.awakeSettings = awake
        let roundtrip = try JSONDecoder().decode(OrbitConfiguration.self, from: JSONEncoder().encode(configured))
        XCTAssertEqual(roundtrip.awake, awake)
    }
    func testAutomationAnyAllAndEmptySelections() {
        var options = AwakeOptions(); options.automationEnabled = true
        XCTAssertFalse(options.matches(power: true, externalDisplay: true, running: []))
        options.onPower = true; options.runningApps = true; options.apps = [.init(id: "example.editor", name: "Editor")]
        XCTAssertTrue(options.matches(power: true, externalDisplay: false, running: []))
        options.requireAll = true
        XCTAssertFalse(options.matches(power: true, externalDisplay: false, running: []))
        XCTAssertTrue(options.matches(power: true, externalDisplay: false, running: ["example.editor"]))
        options.apps = []
        XCTAssertFalse(options.matches(power: true, externalDisplay: true, running: []))
        options.automationEnabled = false
        XCTAssertFalse(options.matches(power: true, externalDisplay: true, running: ["example.editor"]))
    }
    func testManualStopIsNotUndoneByNextAutomationPoll() {
        var automation = AwakeAutomation()
        XCTAssertTrue(automation.shouldStart(matching: true, sessionActive: false, allowed: true))
        automation.userStopped(matching: true)
        XCTAssertFalse(automation.shouldStart(matching: true, sessionActive: false, allowed: true))
        XCTAssertFalse(automation.shouldStart(matching: false, sessionActive: false, allowed: true))
        XCTAssertTrue(automation.shouldStart(matching: true, sessionActive: false, allowed: true))
        XCTAssertFalse(automation.shouldStart(matching: true, sessionActive: true, allowed: true))
        XCTAssertFalse(automation.shouldStart(matching: true, sessionActive: false, allowed: false))
    }
    func testImportedOptionsNormalizeWithoutStartingAnything() {
        var options = AwakeOptions(); options.pointerInterval = 0; options.batteryCutoff = -20
        options.apps = [.init(id: "a", name: "A"), .init(id: "a", name: "Again"), .init(id: "", name: "Empty")]
        options.normalize()
        XCTAssertEqual(options.pointerInterval, 60)
        XCTAssertEqual(options.batteryCutoff, 5)
        XCTAssertEqual(options.apps.count, 1)
        XCTAssertFalse(options.automationEnabled)
    }
    func testEndTimeAndLidLeaseExpireRatherThanPersisting() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let picked = now.addingTimeInterval(-3600)
        let end = AwakeTiming.nextEndTime(picked, now: now, calendar: calendar)
        XCTAssertGreaterThan(end, now)
        XCTAssertLessThanOrEqual(end.timeIntervalSince(now), 86400)
        XCTAssertTrue(AwakeTiming.leaseIsFresh(updated: now, deadline: now.addingTimeInterval(60), now: now.addingTimeInterval(5)))
        XCTAssertFalse(AwakeTiming.leaseIsFresh(updated: now, deadline: now.addingTimeInterval(60), now: now.addingTimeInterval(10)))
        XCTAssertFalse(AwakeTiming.leaseIsFresh(updated: now, deadline: now, now: now))
        XCTAssertFalse(AwakeTiming.leaseIsFresh(updated: now.addingTimeInterval(20), deadline: now.addingTimeInterval(60), now: now))
    }
}
