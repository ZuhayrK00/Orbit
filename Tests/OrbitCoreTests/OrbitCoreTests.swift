import XCTest
import CoreGraphics
@testable import OrbitCore

final class OrbitCoreTests: XCTestCase {
    func testNotchActivationMatchesVisibleWidthAtExactTopEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let panel = CGRect(x: 646, y: 942, width: 220, height: 40)
        for x in [646.0, 756, 866] {
            XCTAssertTrue(NotchActivation.contains(point: CGPoint(x: x, y: 982), screen: screen, panel: panel))
            XCTAssertTrue(NotchActivation.contains(point: CGPoint(x: x, y: 960), screen: screen, panel: panel))
        }
        for x in [8.0, 600, 645.9, 866.1, 900, 1512] {
            XCTAssertFalse(NotchActivation.contains(point: CGPoint(x: x, y: 982), screen: screen, panel: panel))
        }
        XCTAssertFalse(NotchActivation.contains(point: CGPoint(x: 756, y: 941), screen: screen, panel: panel))
        XCTAssertFalse(NotchActivation.contains(point: CGPoint(x: 756, y: 990), screen: screen, panel: panel))
        let external = CGRect(x: -1920, y: 180, width: 1920, height: 1080)
        let externalPanel = CGRect(x: -1070, y: 1226, width: 220, height: 34)
        XCTAssertTrue(NotchActivation.contains(point: CGPoint(x: -960, y: 1260), screen: external, panel: externalPanel))
        XCTAssertFalse(NotchActivation.contains(point: CGPoint(x: -1071, y: 1260), screen: external, panel: externalPanel))
        let expanded = CGRect(x: 516, y: 550, width: 480, height: 432)
        XCTAssertTrue(NotchActivation.contains(point: CGPoint(x: 990, y: 600), screen: screen, panel: expanded))
        XCTAssertFalse(NotchActivation.contains(point: CGPoint(x: 997, y: 982), screen: screen, panel: expanded))
    }
    func testOldFullEdgeSettingIsIgnoredWithoutLosingCustomisation() throws {
        var settings = OrbitConfiguration(); settings.hoverDelay = 0.77; settings.keyboardEnabled = false
        settings.slots[0].label = "My files"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        json["notchFullTopEdge"] = true
        var restored = try JSONDecoder().decode(OrbitConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        restored.normalize()
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        XCTAssertNil(encoded["notchFullTopEdge"])
        XCTAssertEqual(restored.hoverDelay, 0.77)
        XCTAssertFalse(restored.keyboardEnabled)
        XCTAssertEqual(restored.slots[0].label, "My files")
    }
    func testWheelCardinalDirectionsAndDeadZones() {
        XCTAssertEqual(WheelGeometry.index(x: 230, y: 60, diameter: 460, count: 8), 0)
        XCTAssertEqual(WheelGeometry.index(x: 400, y: 230, diameter: 460, count: 8), 2)
        XCTAssertEqual(WheelGeometry.index(x: 230, y: 400, diameter: 460, count: 8), 4)
        XCTAssertEqual(WheelGeometry.index(x: 60, y: 230, diameter: 460, count: 8), 6)
        XCTAssertNil(WheelGeometry.index(x: 230, y: 230, diameter: 460, count: 8))
        XCTAssertNil(WheelGeometry.index(x: 0, y: 0, diameter: 460, count: 8))
        XCTAssertNil(WheelGeometry.index(x: 230, y: 60, diameter: 460, count: 0))
    }
    func testEverySlotCenterResolvesAcrossSupportedCounts() {
        for count in 4...12 { for index in 0..<count { let point = WheelGeometry.center(index: index, count: count, diameter: 680); XCTAssertEqual(WheelGeometry.index(x: point.x, y: point.y, diameter: 680, count: count), index) } }
    }
    func testConfigurationBoundsAndPersistence() throws {
        var config = OrbitConfiguration(); config.wheelDiameter = 10_000; config.mouseButton = -9; config.hoverDelay = -2; config.notchHeight = 2
        config.keyModifiers = 0; config.slots = []; config.normalize()
        XCTAssertEqual(config.wheelDiameter, 680); XCTAssertEqual(config.mouseButton, 0); XCTAssertEqual(config.hoverDelay, 0.05); XCTAssertEqual(config.notchHeight, 300)
        XCTAssertEqual(config.slots.count, 8); XCTAssertEqual(config.keyModifiers, 6144)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ConfigurationIO.save(config, to: url); XCTAssertEqual(try ConfigurationIO.load(from: url), config)
    }
    func testTimerPauseResumeAndElapsedRestart() {
        let start = Date(timeIntervalSince1970: 1000)
        var timer = OrbitTimer(); timer.start(seconds: 60, now: start)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(15)), 45)
        timer.pause(now: start.addingTimeInterval(15)); XCTAssertEqual(timer.pausedRemaining, 45)
        timer.resume(now: start.addingTimeInterval(100)); XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(110)), 35)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(200)), 0)
        timer.cancel(); XCTAssertFalse(timer.isActive)
        XCTAssertEqual(OrbitTimer.label(3601), "1:00:01"); XCTAssertEqual(OrbitTimer.label(-5), "00:00")
    }
    func testNewTimerCannotGainASecondFromThePreviousDisplayTick() throws {
        let startedAt = Date(timeIntervalSince1970: 1000.875)
        for duration in [60.0, 1500.0, 3600.0] {
            var timer = OrbitTimer(); timer.start(seconds: duration, now: startedAt)
            // Reproduce starting just before the display's next half-second tick.
            let staleDisplayTime = startedAt.addingTimeInterval(-0.499)
            XCTAssertEqual(timer.remaining(at: staleDisplayTime), duration)
            XCTAssertEqual(OrbitTimer.label(timer.remaining(at: staleDisplayTime)), OrbitTimer.label(duration))
            XCTAssertEqual(OrbitTimer.label(timer.remaining(at: startedAt)), OrbitTimer.label(duration))
            XCTAssertEqual(OrbitTimer.label(timer.remaining(at: startedAt.addingTimeInterval(0.999))), OrbitTimer.label(duration))
            XCTAssertEqual(OrbitTimer.label(timer.remaining(at: startedAt.addingTimeInterval(1.001))), OrbitTimer.label(duration - 1))
            let restored = try JSONDecoder().decode(OrbitTimer.self, from: JSONEncoder().encode(timer))
            XCTAssertEqual(restored.remaining(at: staleDisplayTime), duration)
        }
    }
    func testPauseAndResumePreserveTheFractionalCountdownWithoutAddingTime() {
        let startedAt = Date(timeIntervalSince1970: 1000.875)
        var timer = OrbitTimer(); timer.start(seconds: 60, now: startedAt)
        let pausedAt = startedAt.addingTimeInterval(10.375)
        let beforePause = timer.remaining(at: pausedAt)
        timer.pause(now: pausedAt)
        XCTAssertEqual(beforePause, 49.625)
        XCTAssertEqual(timer.remaining(at: pausedAt.addingTimeInterval(30)), beforePause)
        let resumedAt = pausedAt.addingTimeInterval(30.625)
        timer.resume(now: resumedAt)
        XCTAssertEqual(timer.remaining(at: resumedAt), beforePause)
        XCTAssertEqual(OrbitTimer.label(timer.remaining(at: resumedAt)), "00:50")
        XCTAssertEqual(OrbitTimer.label(timer.remaining(at: resumedAt.addingTimeInterval(0.624))), "00:50")
        XCTAssertEqual(OrbitTimer.label(timer.remaining(at: resumedAt.addingTimeInterval(0.626))), "00:49")
        XCTAssertEqual(timer.remaining(at: resumedAt.addingTimeInterval(60)), 0)
    }
    func testAgentStalenessDoesNotFabricateCompletion() {
        let updated = Date(timeIntervalSince1970: 1000)
        let agent = AgentStatus(id: "abc", provider: "Codex", title: "Build", detail: "Working", phase: .running, updatedAt: updated)
        XCTAssertEqual(agent.displayedPhase(now: updated.addingTimeInterval(299)), .running)
        XCTAssertEqual(agent.displayedPhase(now: updated.addingTimeInterval(301)), .offline)
        let done = AgentStatus(id: "abc", provider: "Codex", title: "Build", detail: "Done", phase: .completed, updatedAt: updated)
        XCTAssertEqual(done.displayedPhase(now: updated.addingTimeInterval(5000)), .completed)
    }
    func testClaudeAndCodexEventsPreserveStatusAndOmitPromptContent() {
        let claude = AgentBridge.claudeEvent(["hook_event_name": "PermissionRequest", "session_id": "123", "cwd": "/dev/Orbit", "prompt": "private text"])
        XCTAssertEqual(claude?.phase, .waiting); XCTAssertEqual(claude?.title, "Orbit"); XCTAssertFalse(claude?.detail.contains("private") ?? true)
        XCTAssertEqual(AgentBridge.claudeEvent(["hook_event_name": "PostToolUseFailure", "session_id": "123"])?.phase, .running)
        XCTAssertEqual(AgentBridge.codexEvent(["type": "turn.completed"], session: "abc", title: "Orbit")?.phase, .completed)
        XCTAssertEqual(AgentBridge.codexEvent(["type": "turn.failed"], session: "abc", title: "Orbit")?.phase, .failed)
        XCTAssertNil(AgentBridge.codexEvent(["type": "unknown"], session: "abc", title: "Orbit"))
    }
    func testAgentFilesAreAtomicBoundedAndPathSafe() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let agent = AgentStatus(id: "../../not-a-path", provider: "Claude", title: "Orbit", detail: "Working", phase: .running)
        try AgentBridge.write(agent, directory: folder)
        XCTAssertEqual(AgentBridge.read(directory: folder).first?.id, agent.id)
        XCTAssertFalse(AgentBridge.fileName(for: agent.id).contains("/"))
        try Data("malformed".utf8).write(to: folder.appendingPathComponent("bad.json"))
        XCTAssertEqual(AgentBridge.read(directory: folder).count, 1)
        let linked = folder.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: folder.appendingPathComponent(AgentBridge.fileName(for: agent.id)))
        XCTAssertEqual(AgentBridge.read(directory: folder).count, 1)
    }
    func testClaudeHookMergePreservesOtherSettingsAndIsIdempotent() throws {
        let command = "'/a path/bin/orbit-agent' --claude-hook"
        let existing: [String: Any] = ["permissions": ["allow": ["Bash(swift test)"]], "hooks": ["Stop": [["matcher": "", "hooks": [["type": "command", "command": "notify-me"], ["type": "command", "command": command]]]], "CustomEvent": ["unchanged"]]]
        let first = try AgentHooks.addingClaude(to: existing, command: command)
        let second = try AgentHooks.addingClaude(to: first, command: command)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: first, options: .sortedKeys), try JSONSerialization.data(withJSONObject: second, options: .sortedKeys))
        XCTAssertEqual((second["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(swift test)"])
        let hooks = try XCTUnwrap(second["hooks"] as? [String: Any])
        XCTAssertEqual(hooks["CustomEvent"] as? [String], ["unchanged"])
        let stops = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stops.count, 2)
        XCTAssertEqual((stops[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String, "notify-me")
        XCTAssertThrowsError(try AgentHooks.addingClaude(to: ["hooks": "invalid"], command: command))
        XCTAssertThrowsError(try AgentHooks.addingClaude(to: ["hooks": ["Stop": [["hooks": "invalid"]]]], command: command))
    }
}
