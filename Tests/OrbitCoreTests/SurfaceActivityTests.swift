import XCTest
@testable import OrbitCore

final class SurfaceActivityTests: XCTestCase {
    func testToolsStayInsideControlSurfaces() {
        for action in OrbitAction.surfaceTools { XCTAssertEqual(action.utilitySection, action) }
        for action in [OrbitAction.compressImage, .convertImage, .zipFiles] { XCTAssertEqual(action.utilitySection, .files) }
        for action in [OrbitAction.settings, .wheelProfile, .openURL, .openApp, .shortcut] { XCTAssertNil(action.utilitySection) }
    }
    func testCompactActivityIdlePriorityExpiryAndStableOrder() {
        let now = Date(timeIntervalSince1970: 3600)
        func choose(_ seconds: Double = 0, waiting: Bool = false, agent: Bool = false, timer: Bool = false, finished: Bool = false, music: Bool = false, copied: Date? = nil) -> NotchActivityKind? {
            NotchActivity.choose(waitingAgent: waiting, activeAgent: agent, timer: timer, timerFinished: finished, music: music, copiedAt: copied, now: now.addingTimeInterval(seconds))
        }
        XCTAssertNil(choose())
        XCTAssertEqual(choose(waiting: true, timer: true, finished: true, copied: now), .agent)
        XCTAssertEqual(choose(finished: true, copied: now), .timerFinished)
        XCTAssertEqual(choose(5, timer: true, copied: now), .copied)
        XCTAssertEqual(choose(6, timer: true, copied: now), .timer)
        XCTAssertEqual(choose(agent: true, timer: true, music: true), .timer)
        XCTAssertEqual(choose(6, agent: true, timer: true, music: true), .timer)
        XCTAssertEqual(choose(12, agent: true, timer: true, music: true), .timer)
        XCTAssertEqual(choose(18, agent: true, timer: true, music: true), .timer)
        XCTAssertNil(choose(copied: now.addingTimeInterval(1)))
    }
    func testAgentElapsedClockSurvivesEventsAndStopsAtCompletion() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let start = Date(timeIntervalSince1970: 1000)
        func event(_ phase: AgentPhase, at offset: Double, startedAt: Date? = nil) throws {
            try AgentBridge.write(AgentStatus(id: "test", provider: "Codex", title: "Test", detail: "", phase: phase,
                updatedAt: start.addingTimeInterval(offset), startedAt: startedAt), directory: folder)
        }
        try event(.running, at: 0)
        try event(.running, at: 12)
        try event(.waiting, at: 24)
        var status = try XCTUnwrap(AgentBridge.read(directory: folder).first)
        XCTAssertEqual(status.elapsed(at: start.addingTimeInterval(30)), 30)
        try event(.running, at: 40)
        try event(.completed, at: 80)
        status = try XCTUnwrap(AgentBridge.read(directory: folder).first)
        XCTAssertEqual(status.elapsed(at: start.addingTimeInterval(150)), 80)
        // A late old callback cannot restart the clock or overwrite completion.
        try event(.running, at: 45)
        XCTAssertEqual(AgentBridge.read(directory: folder).first?.phase, .completed)
        try event(.offline, at: 100)
        XCTAssertEqual(AgentBridge.read(directory: folder).first?.elapsed(at: start.addingTimeInterval(150)), 80)
        try event(.running, at: 200, startedAt: start.addingTimeInterval(200))
        status = try XCTUnwrap(AgentBridge.read(directory: folder).first)
        XCTAssertEqual(status.elapsed(at: start.addingTimeInterval(210)), 10)
        XCTAssertEqual(status.elapsed(at: start.addingTimeInterval(700)), 0) // stale activity is frozen
    }
    func testOldAgentPayloadHasNoFabricatedElapsedClock() throws {
        let agent = AgentStatus(id: "old", provider: "Claude", title: "Test", detail: "", phase: .running)
        let data = try JSONEncoder().encode(agent)
        XCTAssertNil(try JSONDecoder().decode(AgentStatus.self, from: data).elapsed(at: Date()))
        XCTAssertNotNil(AgentBridge.claudeEvent(["hook_event_name": "UserPromptSubmit", "session_id": "one"])?.startedAt)
        XCTAssertNil(AgentBridge.claudeEvent(["hook_event_name": "PostToolUse", "session_id": "one"])?.startedAt)
    }
}
