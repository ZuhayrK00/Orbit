import XCTest
@testable import OrbitCore

final class NotchLiveActivityTests: XCTestCase {
    func testExplicitSelectionSurvivesNoticesAndDoesNotRotate() {
        let available: [NotchActivityKind] = [.timer, .agent, .music]
        var selection = NotchActivitySelection()
        selection.select(.music, available: available, timerRunning: true)
        let start = Date(timeIntervalSince1970: 10_000)
        func shown(_ seconds: Double, copied: Date? = nil, waiting: Bool = false) -> NotchActivityKind? {
            NotchActivity.choose(waitingAgent: waiting, activeAgent: true, timer: true, timerFinished: false,
                music: true, copiedAt: copied, now: start.addingTimeInterval(seconds), selection: selection)
        }
        XCTAssertEqual(shown(0), .music)
        XCTAssertEqual(shown(600), .music)
        XCTAssertEqual(shown(1, copied: start), .copied)
        XCTAssertEqual(shown(6, copied: start), .music)
        XCTAssertEqual(shown(7, waiting: true), .agent)
        XCTAssertEqual(shown(8), .music)
    }

    func testUnavailableChoiceFallsBackAndAnEmptySessionResetsIt() {
        var selection = NotchActivitySelection()
        selection.select(.music, available: [.timer, .music], timerRunning: true)
        XCTAssertEqual(selection.current(in: [.timer]), .timer)
        XCTAssertEqual(selection.current(in: [.timer, .music]), .music)
        selection.select(.agent, available: [.timer, .music], timerRunning: true)
        XCTAssertEqual(selection.preferred, .music)
        selection.reconcile(available: [])
        XCTAssertNil(selection.preferred)
        XCTAssertEqual(selection.current(in: [.timer, .music]), .timer)
    }

    func testTimerPairIsExplicitAndYieldsToPauseOrMissingCompanion() {
        let available: [NotchActivityKind] = [.timer, .agent, .music]
        var selection = NotchActivitySelection()
        XCTAssertNil(selection.visibleCompanion(available: available, timerRunning: true))
        selection.select(.timer, companion: .agent, available: available, timerRunning: true)
        XCTAssertEqual(selection.visibleCompanion(available: available, timerRunning: true), .agent)
        XCTAssertNil(selection.visibleCompanion(available: available, timerRunning: false))
        XCTAssertNil(selection.visibleCompanion(available: [.timer, .music], timerRunning: true))
        XCTAssertEqual(selection.visibleCompanion(available: available, timerRunning: true), .agent)
        selection.select(.music, companion: .agent, available: available, timerRunning: true)
        XCTAssertEqual(selection.preferred, .timer)
        selection.select(.timer, available: available, timerRunning: true)
        XCTAssertNil(selection.companion)
    }

    func testTimerNoticeExpiresWithoutSuppressingOngoingActivities() {
        let end = Date(timeIntervalSince1970: 20_000)
        for offset in [-1.0, 0, 7.9, 8, 60] {
            let now = end.addingTimeInterval(offset)
            let recent = NotchActivity.isRecent(end, now: now, duration: 8)
            XCTAssertEqual(recent, offset >= 0 && offset < 8)
            let shown = NotchActivity.choose(waitingAgent: false, activeAgent: true, timer: false,
                timerFinished: recent, music: true, copiedAt: nil, now: now)
            XCTAssertEqual(shown, recent ? .timerFinished : .agent)
        }
    }

    func testAgentFocusKeepsTheSameClockAndWaitingTasksTakePriority() throws {
        let now = Date()
        let first = AgentStatus(id: "one", provider: "Codex", title: "One", detail: "", phase: .running, updatedAt: now, startedAt: now.addingTimeInterval(-90))
        var second = AgentStatus(id: "two", provider: "Claude", title: "Two", detail: "", phase: .running, updatedAt: now, startedAt: now.addingTimeInterval(-30))
        XCTAssertEqual(AgentActivity.focused([second, first], selectedID: nil, now: now)?.id, "one")
        XCTAssertEqual(AgentActivity.focused([first, second], selectedID: "two", now: now)?.id, "two")
        XCTAssertEqual(AgentActivity.focused([first, second], selectedID: "two", now: now.addingTimeInterval(20))?.id, "two")
        second.phase = .waiting
        XCTAssertEqual(AgentActivity.focused([first, second], selectedID: "one", now: now)?.id, "two")
        XCTAssertEqual(try XCTUnwrap(AgentActivity.focused([first], selectedID: "two", now: now)).elapsed(at: now), 90)
    }

    func testKeepAwakeStaysBehindMoreImmediateActivities() {
        XCTAssertEqual(NotchActivity.available(timer: true, agent: true, music: true, keepAwake: true), [.timer, .agent, .music, .keepAwake])
        XCTAssertEqual(NotchActivity.available(timer: false, agent: false, music: false, keepAwake: true), [.keepAwake])
        XCTAssertTrue(NotchOptions().showKeepAwake)
    }

    func testExistingNotchSettingsEnableLiveIndicatorsWithoutAddingPermission() throws {
        let old = try JSONDecoder().decode(NotchOptions.self, from: Data("{\"showAgents\":true}".utf8))
        XCTAssertTrue(old.allowActivityOverMenus)
        XCTAssertTrue(old.showKeepAwake)
        let explicit = try JSONDecoder().decode(NotchOptions.self, from: Data("{\"allowActivityOverMenus\":false}".utf8))
        XCTAssertFalse(explicit.allowActivityOverMenus)
    }
}
