import XCTest
@testable import OrbitCore

final class ProductivityTests: XCTestCase {
    func testOldSettingsGainOptionalFeaturesWithoutChangingTriggersOrLevels() throws {
        var old = OrbitConfiguration(); old.mouseButton = 7; old.clipboardEnabled = true
        var mixer = MixerOptions(); var level = MixerLevel(); level.setVolume(0.25); level.toggleMute(); mixer.levels["test"] = level; old.mixerSettings = mixer
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any]); json.removeValue(forKey: "productivitySettings"); json.removeValue(forKey: "wheelProfiles")
        let migrated = try JSONDecoder().decode(OrbitConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.mouseButton, 7); XCTAssertTrue(migrated.clipboardEnabled)
        XCTAssertFalse(migrated.productivity.calendarEnabled == true); XCTAssertFalse(migrated.productivity.downloadsEnabled == true)
        XCTAssertEqual(migrated.mixer, mixer); XCTAssertNil(migrated.wheelProfiles)
    }
    func testNewToolsStayInTheSurfaceAndHomeDoesNotLoseRememberedTool() {
        for action in [OrbitAction.shelf, .calendar, .downloads, .screenText, .home] { XCTAssertEqual(action.utilitySection, action) }
        var nav = NotchNavigation(savedTool: "music"); nav.showHome(); XCTAssertEqual(nav.current, .home); XCTAssertEqual(nav.remembered, .music); nav.reopen(); XCTAssertEqual(nav.current, .music)
        XCTAssertFalse(WheelDismissal.outsideClickCloses(section: .shelf, pinned: false, processing: false, enabled: true, modal: false))
    }
    func testMixerCurvePreservesSavedPhysicalGainAndMuteRestore() {
        for gain in [0.0, 0.01, 0.1, 0.25, 0.8, 1, 1.5, 2] { XCTAssertEqual(MixerCurve.gain(position: MixerCurve.position(gain: gain)), gain, accuracy: 0.000001) }
        XCTAssertEqual(MixerCurve.gain(position: 0.5), 0.25); XCTAssertEqual(MixerCurve.position(gain: .nan), 1)
        var level = MixerLevel(); level.setVolume(0.25); level.toggleMute(); level.toggleMute(); XCTAssertEqual(level.volume, 0.25)
    }
    func testMeetingLinksRejectLookalikesAndUnsafeSchemes() {
        XCTAssertEqual(MeetingLink.find(in: "Join https://team.zoom.us/j/123?pwd=xyz")?.host, "team.zoom.us")
        XCTAssertNotNil(MeetingLink.find(in: "Meeting: https://teams.microsoft.com/l/meetup-join/abc"))
        for value in ["https://zoom.us.evil.test/j/123", "https://evilzoom.us/j/123", "javascript:alert(1)", "file:///etc/passwd"] { XCTAssertFalse(MeetingLink.allowed(URL(string: value)!)) }
    }
    func testDownloadsRequireFinalFileAndStableSize() {
        var tracker = DownloadTracker(); let now = Date()
        let part = DownloadSample(path: "/d/a.zip.download", target: "/d/a.zip", bytes: 10, temporary: true)
        tracker.ingest([part], now: now); XCTAssertEqual(tracker.activities.first?.state, .downloading)
        tracker.ingest([], now: now.addingTimeInterval(1)); XCTAssertEqual(tracker.activities.first?.state, .downloading)
        tracker.ingest([.init(path: "/d/a.zip", target: "/d/a.zip", bytes: 12, temporary: false)], now: now.addingTimeInterval(2)); XCTAssertEqual(tracker.activities.first?.state, .downloading)
        tracker.ingest([.init(path: "/d/a.zip", target: "/d/a.zip", bytes: 14, temporary: false)], now: now.addingTimeInterval(3)); XCTAssertEqual(tracker.activities.first?.state, .downloading)
        tracker.ingest([.init(path: "/d/a.zip", target: "/d/a.zip", bytes: 14, temporary: false)], now: now.addingTimeInterval(4)); XCTAssertEqual(tracker.activities.first?.state, .complete)
    }
    func testExistingFileAndMissingTemporaryFileNeverFabricateCompletion() {
        var tracker = DownloadTracker(); let now = Date()
        tracker.ingest([.init(path: "/d/a.zip", target: "/d/a.zip", bytes: 100, temporary: false)], now: now)
        let part = DownloadSample(path: "/d/a.zip.part", target: "/d/a.zip", bytes: 10, temporary: true)
        tracker.ingest([part], now: now.addingTimeInterval(1))
        for i in 2...20 { tracker.ingest([.init(path: "/d/a.zip", target: "/d/a.zip", bytes: 100, temporary: false)], now: now.addingTimeInterval(Double(i))) }
        XCTAssertEqual(tracker.activities.first?.state, .missing)
    }
    func testUnknownDownloadTotalsStayIndeterminate() { let item = DownloadActivity(id: "a", target: "a", bytes: 800, total: nil, state: .downloading, updated: Date()); XCTAssertNil(item.fraction) }
    func testQuietOrMissingAgentDoesNotEndAwakeLease() {
        var lease = AgentAwakeLease(); lease.start(ids: ["a", "b"])
        lease.observe(completed: [], running: []); XCTAssertFalse(lease.finished)
        lease.observe(completed: ["a"], running: ["c"]); XCTAssertEqual(lease.pending, ["b", "c"])
        lease.observe(completed: ["b", "c"], running: []); XCTAssertTrue(lease.finished)
    }
    func testFocusCyclesAndStopwatchPauseContinuity() {
        var cycle = FocusCycle(); cycle.advance(rounds: 2); XCTAssertEqual(cycle.phase, .shortBreak); cycle.advance(rounds: 2); XCTAssertEqual(cycle.round, 2); cycle.advance(rounds: 2); XCTAssertEqual(cycle.phase, .longBreak); cycle.advance(rounds: 2); XCTAssertEqual(cycle.round, 1)
        let start = Date(); var watch = StopwatchState(); watch.toggle(at: start); watch.lap(at: start.addingTimeInterval(5)); watch.toggle(at: start.addingTimeInterval(8)); XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(20)), 8); watch.toggle(at: start.addingTimeInterval(20)); XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(22)), 10); XCTAssertEqual(watch.laps, [5])
    }
    func testMarkdownChecklistsToggleOnlyTheChosenLine() {
        var note = NoteDocument(text: "Title\n  - [ ] First\n- [x] Second\nparagraph")
        note.toggleChecklist(line: 1); XCTAssertEqual(note.text, "Title\n  - [x] First\n- [x] Second\nparagraph")
        note.toggleChecklist(line: 2); XCTAssertTrue(note.text.contains("- [ ] Second")); let prior = note.text; note.toggleChecklist(line: 30); XCTAssertEqual(note.text, prior)
    }
    func testClaudeUsageRejectsOldVersionsInvalidWindowsAndPreservesReset() {
        XCTAssertFalse(ClaudeUsageProtocol.supported(version: "2.1.285 (Claude Code)")); XCTAssertTrue(ClaudeUsageProtocol.supported(version: "2.1.286 (Claude Code)")); XCTAssertTrue(ClaudeUsageProtocol.supported(version: "3.0.0"))
        let now = Date(timeIntervalSince1970: 1000), reset = "2026-10-15T19:00:00.123Z"
        let value: [String: Any] = ["rate_limits_available": true, "rate_limits": ["five_hour": ["utilization": 42.5, "resets_at": reset], "seven_day": ["utilization": true, "resets_at": reset]]]
        let windows = ClaudeUsageProtocol.windows(value, now: now); XCTAssertEqual(windows.count, 1); XCTAssertEqual(windows.first?.usedPercent, 42.5); XCTAssertNotNil(windows.first?.resetsAt)
        XCTAssertTrue(ClaudeUsageProtocol.windows(value, now: Date.distantFuture).isEmpty)
    }
    func testProfilesRoundTripSubmenusAndShortcutBindings() throws {
        var profiles = WheelProfile.starters
        profiles[0].slots[0] = WheelSlot(action: .wheelProfile, argument: profiles[1].id.uuidString); profiles[0].keyCode = 48; profiles[0].modifiers = 6144
        let saved = try JSONDecoder().decode([WheelProfile].self, from: JSONEncoder().encode(profiles)); XCTAssertEqual(saved, profiles)
    }
}

extension ProductivityTests {
    func testDownloadsUseFileIdentityToRejectUnrelatedReplacement() {
        let now = Date(); var tracker = DownloadTracker()
        tracker.ingest([.init(path: "/d/a.part", target: "/d/a", bytes: 20, temporary: true, identifier: "download-file")], now: now)
        for i in 1...20 { tracker.ingest([.init(path: "/d/a", target: "/d/a", bytes: 20, temporary: false, identifier: "other-file")], now: now.addingTimeInterval(Double(i))) }
        XCTAssertEqual(tracker.activities.first?.state, .missing)
    }
    func testJoinDoesNotTreatProviderHomeAndChatPagesAsMeetings() {
        for value in ["https://zoom.us/", "https://teams.microsoft.com/l/chat/0/0?users=a", "https://meet.google.com/", "https://webex.com/support"] { XCTAssertFalse(MeetingLink.allowed(URL(string: value)!)) }
        XCTAssertTrue(MeetingLink.allowed(URL(string: "https://meet.google.com/abc-defg-hij")!))
    }
}
