import XCTest
@testable import OrbitCore

final class NotchNavigationTests: XCTestCase {
    func testReopeningKeepsTheUsersLastTool() {
        var navigation = NotchNavigation()
        navigation.select(.music)
        for _ in 0..<3 { navigation.reopen(); XCTAssertEqual(navigation.current, .music) }
        navigation.select(.timer); navigation.reopen()
        XCTAssertEqual(navigation.current, .timer)
        XCTAssertEqual(NotchNavigation(savedTool: navigation.remembered.rawValue).current, .timer)
    }

    func testAutomaticNotificationDoesNotReplaceRememberedChoice() {
        var navigation = NotchNavigation()
        navigation.select(.music); navigation.showNotification()
        XCTAssertTrue(navigation.isShowingNotification)
        XCTAssertEqual(navigation.current, .notifications)
        XCTAssertEqual(navigation.remembered, .music)
        navigation.reopen()
        XCTAssertFalse(navigation.isShowingNotification)
        XCTAssertEqual(navigation.current, .music)
        navigation.showNotification(); navigation.select(.clipboard); navigation.reopen()
        XCTAssertFalse(navigation.isShowingNotification)
        XCTAssertEqual(navigation.current, .clipboard)
    }

    func testExplicitInboxSelectionIsRememberedAndInvalidSavedToolsAreSafe() {
        var navigation = NotchNavigation(savedTool: "unknown")
        XCTAssertEqual(navigation.current, .agents)
        XCTAssertEqual(NotchNavigation(savedTool: "settings").current, .agents)
        navigation.select(.notifications); navigation.reopen()
        XCTAssertFalse(navigation.isShowingNotification)
        XCTAssertEqual(navigation.current, .notifications)
        navigation.select(.openURL); navigation.reopen()
        XCTAssertEqual(navigation.current, .notifications)
    }

    func testOpeningInboxFromAnArrivalLeavesTheTransientPresentation() {
        var navigation = NotchNavigation(savedTool: "music")
        navigation.showNotification()
        navigation.select(.notifications)
        XCTAssertFalse(navigation.isShowingNotification)
        XCTAssertEqual(navigation.remembered, .notifications)
        navigation.showNotification(); navigation.reopen()
        XCTAssertFalse(navigation.isShowingNotification)
        XCTAssertEqual(navigation.current, .notifications)
    }
}
