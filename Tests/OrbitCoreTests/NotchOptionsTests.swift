import XCTest
@testable import OrbitCore

final class NotchOptionsTests: XCTestCase {
    func testEditorCanAddNewToolsWithoutChangingExistingPositions() throws {
        var options = NotchOptions()
        let originalLeft = options.actions(at: .left)
        XCTAssertTrue(options.moveShortcut(.shelf, to: .bottom))
        XCTAssertTrue(options.moveShortcut(.calendar, to: .bottom, before: .shelf))
        options.normalize()
        XCTAssertEqual(options.actions(at: .left), originalLeft)
        XCTAssertEqual(options.actions(at: .bottom), [.calendar, .shelf])
        let restored = try JSONDecoder().decode(NotchOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(restored, options)
    }
    func testEditorReordersAndMovesByIdentityWithoutDuplicatingTools() {
        var options = NotchOptions()
        XCTAssertTrue(options.moveShortcut(.timer, to: .right, before: .files))
        XCTAssertEqual(options.actions(at: .right).first, .timer)
        XCTAssertTrue(options.reorderShortcut(.timer, by: 1))
        XCTAssertEqual(Array(options.actions(at: .right).prefix(2)), [.files, .timer])
        XCTAssertTrue(options.moveShortcut(.timer, to: .hidden))
        XCTAssertTrue(options.moveShortcut(.timer, to: .bottom))
        XCTAssertEqual(options.shortcuts.filter { $0.action == .timer }.count, 1)
        XCTAssertEqual(options.actions(at: .bottom), [.timer])
    }
    func testFullEditorZoneRejectsDropWithoutMovingAnythingElse() {
        var options = NotchOptions()
        XCTAssertTrue(options.moveShortcut(.shelf, to: .left))
        let full = options
        XCTAssertFalse(options.moveShortcut(.calendar, to: .left))
        XCTAssertEqual(options, full)
        XCTAssertTrue(options.moveShortcut(.agents, to: .left, before: .shelf))
        XCTAssertEqual(options.actions(at: .left).count, 6)
        options.shortcuts = NotchOptions.availableShortcuts.prefix(12).map { .init($0, .bottom) }
        let bottomFull = options
        XCTAssertFalse(options.moveShortcut(.settings, to: .bottom))
        XCTAssertEqual(options, bottomFull)
    }
    func testEditorReplacementAndCustomNameSurviveRestart() throws {
        var options = NotchOptions()
        let timer = try XCTUnwrap(options.shortcuts.firstIndex { $0.action == .timer })
        options.shortcuts[timer].label = "Focus timer"
        XCTAssertFalse(options.replaceShortcut(.timer, with: .agents))
        XCTAssertTrue(options.replaceShortcut(.timer, with: .calendar))
        options.normalize()
        XCTAssertEqual(options.shortcutTitle(.calendar), "Focus timer")
        XCTAssertEqual(options.actions(at: .left)[2], .calendar)
        XCTAssertTrue(options.actions(at: .hidden).contains(.timer))
        let restored = try JSONDecoder().decode(NotchOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(restored.shortcutTitle(.calendar), "Focus timer")
        XCTAssertEqual(restored.actions(at: .left), options.actions(at: .left))
    }
    func testImportedExtraToolsKeepBottomWithinTwoRows() {
        var options = NotchOptions()
        options.shortcuts = NotchOptions.availableShortcuts.map { .init($0, .bottom) }
        options.normalize()
        XCTAssertEqual(options.actions(at: .bottom).count, 12)
        XCTAssertEqual(options.actions(at: .hidden).count, 4)
        XCTAssertEqual(NotchShortcutLayout.bottomAllowance(count: options.actions(at: .bottom).count), 106)
    }
    func testOldConfigurationKeepsBlackNotchAndExistingPreferences() throws {
        var config = OrbitConfiguration()
        config.notchWidth = 509; config.notchEnabled = false; config.hoverDelay = 0.07
        var restored = try JSONDecoder().decode(OrbitConfiguration.self, from: JSONEncoder().encode(config))
        restored.normalize()
        XCTAssertNil(restored.notchSettings)
        XCTAssertEqual(restored.notch.color, .black)
        XCTAssertFalse(restored.notch.outlineEnabled)
        XCTAssertEqual(restored.notch.visibleActions(at: .left), [.agents, .music, .timer, .clipboard, .sound])
        XCTAssertEqual(restored.notchWidth, 509); XCTAssertFalse(restored.notchEnabled); XCTAssertEqual(restored.hoverDelay, 0.07)
    }
    func testCustomLayoutColorsAndActivitySwitchesRoundTrip() throws {
        var config = OrbitConfiguration(), notch = NotchOptions()
        notch.color = .init(0.2, 0.4, 0.9); notch.outlineEnabled = true; notch.outlineWidth = 2.5
        notch.shortcuts = [.init(.timer, .bottom), .init(.music, .bottom), .init(.agents, .right), .init(.settings, .hidden)]
        notch.showAgents = false; notch.showInbox = false; notch.showNotifications = false
        config.notchSettings = notch; config.normalize()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ConfigurationIO.save(config, to: url)
        let restored = try ConfigurationIO.load(from: url)
        XCTAssertEqual(config, restored)
        XCTAssertEqual(restored.notch.visibleActions(at: .bottom), [.timer, .music])
        XCTAssertFalse(restored.notch.showsActivity(for: .agents)); XCTAssertTrue(restored.notch.showsActivity(for: .timer))
        XCTAssertFalse(restored.notch.showInbox)
    }
    func testInvalidImportedLayoutDeduplicatesAndKeepsSideRailsBounded() {
        var value = NotchOptions()
        value.shortcuts = [.init(.timer, .left), .init(.timer, .right), .init(.openURL, .bottom)]
            + NotchOptions.defaultShortcuts.filter { $0.action != .timer }.map { .init($0.action, .left) }
        value.outlineWidth = .infinity; value.color = .init(-2, 3, .nan)
        value.normalize()
        XCTAssertEqual(value.actions(at: .left).count, 6)
        XCTAssertEqual(value.actions(at: .bottom).count, 5)
        XCTAssertEqual(Set(value.shortcuts.map(\.action)).count, 11)
        XCTAssertFalse(value.shortcuts.contains { $0.action == .openURL })
        XCTAssertEqual(value.outlineWidth, 1); XCTAssertEqual(value.color, .init(0, 1, 0))
        let normalized = value; value.normalize(); XCTAssertEqual(value, normalized)
    }
    func testMissingFieldsGetDefaultsButExplicitEmptyLayoutStaysHidden() throws {
        let defaults = try JSONDecoder().decode(NotchOptions.self, from: Data("{}".utf8))
        XCTAssertEqual(defaults, NotchOptions())
        let empty = try JSONDecoder().decode(NotchOptions.self, from: Data("{\"shortcuts\":[]}".utf8))
        XCTAssertEqual(empty.shortcuts.count, 11)
        for position in [NotchShortcutPosition.left, .right, .bottom] { XCTAssertTrue(empty.visibleActions(at: position).isEmpty) }
    }
    func testHiddenRailsReserveNoCanvasAndRestoreTheirOrder() {
        var options = NotchOptions(); options.shortcutsEnabled = false
        let size = CGSize(width: 480, height: 180)
        let hidden = NotchShortcutLayout(bodySize: size, railTop: 44, options: options)
        XCTAssertEqual(hidden.canvas, size); XCTAssertEqual(hidden.left, .zero); XCTAssertEqual(hidden.right, .zero); XCTAssertEqual(hidden.bottom, .zero)
        options.shortcutsEnabled = true
        let visible = NotchShortcutLayout(bodySize: size, railTop: 44, options: options)
        XCTAssertEqual(visible.canvas.width, 608); XCTAssertEqual(visible.canvas.height, 296)
        XCTAssertEqual(visible.left.height, 252)
        XCTAssertEqual(options.visibleActions(at: .left), [.agents, .music, .timer, .clipboard, .sound])
    }
    func testBottomShortcutsWrapAndFitWithinScreenBudget() {
        var options = NotchOptions()
        options.shortcuts = NotchOptions.defaultShortcuts.map { .init($0.action, .bottom) }
        let allowance = NotchShortcutLayout.bottomAllowance(count: 11)
        XCTAssertEqual(allowance, 106)
        let bodyHeight = NotchLayout.fittedHeight(measured: 2000, screenHeight: 768 - allowance)
        let layout = NotchShortcutLayout(bodySize: CGSize(width: 380, height: bodyHeight), railTop: 44, options: options)
        XCTAssertEqual(layout.bottom.height, 96); XCTAssertEqual(layout.bottom.width, 304)
        XCTAssertEqual(layout.canvas.width, 380); XCTAssertEqual(layout.canvas.height, 728)
        XCTAssertEqual(layout.bottom.minY, bodyHeight + 10)
        XCTAssertEqual(NotchShortcutLayout.bottomAllowance(count: 0), 0)
        XCTAssertEqual(NotchShortcutLayout.bottomAllowance(count: 6), 54)
    }
}
