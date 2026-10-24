import XCTest
@testable import OrbitCore

final class NotchNotificationTests: XCTestCase {
    func testModernFieldNamesIdentityAndActions() {
        let root = BannerNode(key: "banner", subrole: "AXNotificationCenterBanner", pressable: true, children: [
            text("header", "Notification"), BannerNode(role: "AXImage", label: "WhatsApp"),
            text("notification-title", "Sam"), text("notification-body", "Hello"),
            BannerNode(key: "reply", role: "AXButton", label: "Reply", pressable: true),
            BannerNode(key: "delete", role: "AXButton", label: "Delete", pressable: true)
        ])
        let notice = BannerParser.notices(in: [root], now: now).first
        XCTAssertEqual(notice?.app, "WhatsApp")
        XCTAssertEqual(notice?.title, "Sam")
        XCTAssertEqual(notice?.actions.map(\.kind), [.open, .reply])
        XCTAssertEqual(notice?.sourceKey, "banner")
        XCTAssertEqual(notice?.redacted.actions, notice?.actions)
    }

    func testAnonymousBannerDoesNotInventAnAppName() {
        let root = BannerNode(subrole: "AXNotificationCenterBanner", children: [text("title", "Download complete"), text("body", "example.zip")])
        XCTAssertEqual(BannerParser.notices(in: [root], now: now).first?.app, "")
    }

    func testCallNeedsBothVisibleNativeControls() {
        let accept = BannerNode(key: "answer", role: "AXButton", label: "Accept", pressable: true)
        var decline = BannerNode(key: "decline", role: "AXButton", label: "Decline", pressable: true)
        func parse(_ buttons: [BannerNode]) -> NotchNotice? {
            BannerParser.incomingCall(in: BannerNode(key: "call", children: [text("", "Alex"), text("", "Incoming call")] + buttons), app: "Phone", bundleID: "com.apple.mobilephone", now: now)
        }
        XCTAssertNil(parse([accept]))
        decline.visible = false; XCTAssertNil(parse([accept, decline]))
        decline.visible = true
        let notice = parse([accept, decline])
        XCTAssertEqual(notice?.title, "Alex")
        XCTAssertEqual(notice?.actions.map(\.kind), [.answer, .decline])
        XCTAssertEqual(notice?.isCall, true)
        XCTAssertEqual(notice?.redacted.title, "Incoming call")
        XCTAssertEqual(notice?.redacted.bundleID, "com.apple.mobilephone")
    }

    func testNativeCustomActionsAndUnknownActions() {
        let reveal = NoticeAction(id: "native-action", title: "Show in Finder", kind: .reveal)
        let root = BannerNode(subrole: "AXNotificationCenterBanner", exposedActions: [reveal], children: [text("title", "Finished"), text("body", "example.zip")])
        XCTAssertEqual(BannerParser.notices(in: [root], now: now).first?.actions, [reveal])
        XCTAssertNil(NoticeAction.kind(for: "Send"))
        XCTAssertNil(NoticeAction.kind(for: "Delete"))
        XCTAssertNil(NoticeAction.kind(for: "Accept all invitations"))
    }

    func testGlassAndCallOptionsMigrateWithoutResettingPreferences() throws {
        let oldOptions = Data(#"{"enabled":true,"expandAutomatically":false,"showPreview":false,"duration":8}"#.utf8)
        let options = try JSONDecoder().decode(NotchNotificationOptions.self, from: oldOptions)
        XCTAssertTrue(options.callsEnabled)
        XCTAssertFalse(options.expandAutomatically)
        var config = OrbitConfiguration(); config.notchWidth = 555
        XCTAssertEqual(config.effectiveGlassTransparency, 0.68)
        config.glassTransparency = .nan; config.normalize()
        XCTAssertEqual(config.effectiveGlassTransparency, 0.68)
        config.glassTransparency = 2; config.normalize()
        XCTAssertEqual(config.effectiveGlassTransparency, 0.9)
        let restored = try JSONDecoder().decode(OrbitConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(restored.notchWidth, 555)
        XCTAssertEqual(restored.effectiveGlassTransparency, 0.9)
    }
    func testSharedGlassColourPreservesLegacyTintAndPersistsOverride() throws {
        var legacy = OrbitConfiguration()
        var notch = NotchOptions(); notch.color = .init(0.2, 0.75, 0.5); notch.outlineEnabled = true
        legacy.notchSettings = notch; legacy.glassTransparency = 0.45
        // A pre-colour configuration has no glassColor key.
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        saved.removeValue(forKey: "glassColor")
        var restored = try JSONDecoder().decode(OrbitConfiguration.self, from: JSONSerialization.data(withJSONObject: saved))
        XCTAssertEqual(restored.effectiveGlassColor, notch.color)
        restored.glassColor = .init(0.7, 0.35, 0.9)
        let roundTrip = try JSONDecoder().decode(OrbitConfiguration.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(roundTrip.effectiveGlassColor, restored.glassColor)
        XCTAssertEqual(roundTrip.notchSettings, legacy.notchSettings)
        XCTAssertEqual(roundTrip.effectiveGlassTransparency, 0.45)
        restored.glassColor = .init(-1, .infinity, 2); restored.normalize()
        XCTAssertEqual(restored.effectiveGlassColor, .init(0, 0, 1))
    }

    private let now = Date(timeIntervalSince1970: 1000)
    func testCompactNotificationKeepsPreviewRedactionAndFitsDisplayBounds() {
        let notice = NotchNotice(id: "example", app: "Messages", title: "Alex", body: "See you soon")
        XCTAssertEqual(notice.compactDetail, "Alex: See you soon")
        XCTAssertEqual(notice.redacted.compactDetail, "New notification")
        let camera = CGSize(width: 208, height: 34)
        let short = NotchLayout.compactSize(cameraSize: camera, requiredWing: 70, availableWing: 300, activity: .notification, screenWidth: 1440)
        let long = NotchLayout.compactSize(cameraSize: camera, requiredWing: 900, availableWing: 300, activity: .notification, screenWidth: 1440)
        XCTAssertLessThan(short.width, long.width)
        XCTAssertEqual(long.width, 208 + 190 * 2)
        let cramped = NotchLayout.compactSize(cameraSize: camera, requiredWing: 900, availableWing: 300, activity: .notification, screenWidth: 360)
        XCTAssertLessThanOrEqual(cramped.width, 360 - 24)
    }
    private func text(_ field: String, _ value: String) -> BannerNode { BannerNode(role: "AXStaticText", field: field, text: value) }
    private func card(_ id: String, title: String = "A new message", body: String = "Example content") -> BannerNode {
        BannerNode(key: id, subrole: "AXNotificationCenterBanner", children: [text("header", "Example"), text("title", title), text("body", body)])
    }
    private func notice(_ id: String) -> NotchNotice { NotchNotice(id: id, app: "Example", title: "Private title", body: "Private body", received: now) }

    func testOnlyVisibleRecognizedBannerSurfacesAreRead() {
        let ordinaryWindow = BannerNode(children: [text("header", "Not a banner"), text("title", "History"), text("body", "Old content")])
        var invisible = card("hidden"); invisible.visible = false
        let parsed = BannerParser.notices(in: [ordinaryWindow, invisible, card("new")], now: now)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.app, "Example")
        XCTAssertEqual(parsed.first?.title, "A new message")
        XCTAssertEqual(parsed.first?.body, "Example content")
    }

    func testStacksKeepDifferentSendersAndBodiesSeparate() {
        let first = card("one", title: "First", body: "First body")
        var second = card("two", title: "Second", body: "Second body")
        second.subrole = "" // Modern stacks can hold ordinary group children.
        let stack = BannerNode(key: "stack", subrole: "AXNotificationCenterBannerStack", children: [first, second])
        let result = BannerParser.notices(in: [stack], now: now)
        XCTAssertEqual(result.map(\.title), ["First", "Second"])
        XCTAssertEqual(result.map(\.body), ["First body", "Second body"])
        XCTAssertNotEqual(result[0].id, result[1].id)
        let fragments = BannerNode(subrole: "AXNotificationCenterBannerStack", children: [text("title", "One"), text("title", "Two"), text("body", "Ambiguous")])
        XCTAssertTrue(BannerParser.notices(in: [fragments], now: now).isEmpty)
    }

    func testUnlabelledLegacyCardsAndOversizeInput() {
        let legacy = BannerNode(key: "legacy", subrole: "AXNotificationCenterAlert", children: [BannerNode(role: "AXImage", label: "Calendar"), text("", "Meeting"), text("", "Starts soon")])
        let parsed = BannerParser.notices(in: [legacy], now: now)
        XCTAssertEqual(parsed.first?.app, "Calendar")
        XCTAssertEqual(parsed.first?.body, "Starts soon")
        XCTAssertTrue(BannerParser.notices(in: [card("large", body: String(repeating: "x", count: 20_000))], now: now).isEmpty)
        let bounded = BannerParser.notices(in: [card("bounded", body: String(repeating: "x", count: 5000))], now: now)
        XCTAssertEqual(bounded.first?.body.count, 1600)
    }

    func testBaselineDeduplicationDismissalAndHistoryReopening() {
        var inbox = NotificationInbox()
        XCTAssertTrue(inbox.ingest([notice("already-visible")], showPreview: true).isEmpty)
        XCTAssertEqual(inbox.ingest([notice("already-visible"), notice("new"), notice("new")], showPreview: true).count, 1)
        inbox.discard("new")
        XCTAssertTrue(inbox.ingest([notice("new")], showPreview: true).isEmpty)
        inbox.resumeWithBaseline()
        XCTAssertTrue(inbox.ingest([notice("history")], showPreview: true).isEmpty)
        XCTAssertEqual(inbox.ingest([notice("after-history")], showPreview: true).map(\.id), ["after-history"])
        inbox.clearDisplay()
        XCTAssertTrue(inbox.ingest([notice("after-history")], showPreview: true).isEmpty)
    }

    func testPrivacyRedactionBoundedHistoryAndReset() {
        var inbox = NotificationInbox()
        _ = inbox.ingest([], showPreview: true)
        _ = inbox.ingest((0..<45).map { notice(String($0)) }, showPreview: true)
        XCTAssertEqual(inbox.items.count, 30)
        inbox.redact()
        XCTAssertTrue(inbox.items.allSatisfy { $0.title == "New notification" && $0.body.isEmpty && $0.app == "Example" })
        XCTAssertEqual(inbox.ingest([notice("redacted")], showPreview: false).first?.body, "")
        inbox.reset()
        XCTAssertTrue(inbox.items.isEmpty)
        XCTAssertTrue(inbox.ingest([notice("on-unlock")], showPreview: true).isEmpty)
    }

    func testOldSettingsPreservedAndNotificationOptionsRoundTrip() throws {
        var config = OrbitConfiguration(); config.notchWidth = 512; config.hoverDelay = 0.8
        let oldData = try JSONEncoder().encode(config)
        var restored = try JSONDecoder().decode(OrbitConfiguration.self, from: oldData)
        XCTAssertFalse(restored.notifications.enabled)
        XCTAssertEqual(restored.notchWidth, 512)
        XCTAssertEqual(restored.hoverDelay, 0.8)
        var options = NotchNotificationOptions(); options.enabled = true; options.showPreview = false; options.duration = 999
        restored.notificationSettings = options; restored.normalize()
        let reloaded = try JSONDecoder().decode(OrbitConfiguration.self, from: JSONEncoder().encode(restored))
        XCTAssertTrue(reloaded.notifications.enabled)
        XCTAssertFalse(reloaded.notifications.showPreview)
        XCTAssertEqual(reloaded.notifications.duration, 15)
    }

    func testNotificationTakesTemporaryPriorityAndReturnsToRunningAgent() {
        let active = NotchActivity.choose(waitingAgent: false, activeAgent: true, timer: false, timerFinished: false, music: false, copiedAt: nil, now: now, notification: true)
        XCTAssertEqual(active?.section, .notifications)
        XCTAssertEqual(NotchActivity.choose(waitingAgent: false, activeAgent: true, timer: false, timerFinished: false, music: false, copiedAt: nil, now: now), .agent)
    }
}
