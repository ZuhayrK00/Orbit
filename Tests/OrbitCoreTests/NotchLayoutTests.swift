import XCTest
@testable import OrbitCore

final class NotchLayoutTests: XCTestCase {
    func testIdleMatchesPhysicalCutoutIncludingFractionalDisplayScaling() {
        for camera in [CGSize(width: 208, height: 37.5), CGSize(width: 172.5, height: 32), CGSize(width: 240, height: 38)] {
            XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera), camera)
            XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: 50), camera)
        }
    }

    func testActivityFitsMeasuredSpaceAndNeverGrowsBelowCamera() {
        let camera = CGSize(width: 208, height: 37.5)
        let active = NotchLayout.compactSize(cameraSize: camera, requiredWing: 50, availableWing: 60)
        XCTAssertEqual(active, CGSize(width: 308, height: 37.5))
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: 50, availableWing: 49), CGSize(width: 306, height: 37.5))
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: 50, availableWing: .nan), camera)
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: 50.2, availableWing: 50.5), CGSize(width: 308, height: 37.5))
        let idle = NotchLayout.compactSize(cameraSize: camera)
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1243)
        for size in [idle, active] {
            let panel = CGRect(x: screen.midX - camera.width / 2, y: screen.maxY - size.height, width: camera.width, height: size.height)
            XCTAssertTrue(NotchActivation.contains(point: CGPoint(x: panel.minX, y: screen.maxY), screen: screen, panel: panel))
            XCTAssertFalse(NotchActivation.contains(point: CGPoint(x: panel.minX - 1, y: screen.maxY), screen: screen, panel: panel))
            XCTAssertFalse(NotchActivation.contains(point: CGPoint(x: panel.maxX + 1, y: screen.maxY), screen: screen, panel: panel))
        }
    }

    // Behavioral fixtures checked against Vorssaint 7ad9b5df's hanging-notch geometry.
    func testSimulatedNotchScalesWithActualMenuBarInsteadOfAConstantWidth() {
        for (height, width) in [(22.0, 123.75), (24, 135), (30, 168.75), (32, 180)] {
            let idle = NotchLayout.cameraSize(reported: .zero, menuBarHeight: height, screenWidth: 5120)
            XCTAssertEqual(idle, CGSize(width: width, height: height))
            XCTAssertEqual(NotchLayout.compactSize(cameraSize: idle, requiredWing: 44, availableWing: 100, activity: .timer),
                           CGSize(width: width + 88, height: height))
        }
    }

    func testPhysicalCameraIncludesMenuBarAndOnlyOptionalOutlineClearance() {
        let reported = CGSize(width: 208, height: 37.5)
        XCTAssertEqual(NotchLayout.cameraSize(reported: reported, menuBarHeight: 38, screenWidth: 1920), CGSize(width: 208, height: 38))
        XCTAssertEqual(NotchLayout.cameraSize(reported: reported, menuBarHeight: 38, screenWidth: 1920, outlined: true), CGSize(width: 212, height: 40))
    }

    func testActivitySpecificWingLimitsAndCrowdedMenus() {
        let camera = CGSize(width: 208, height: 38)
        // Timers keep a readable menu-bar lane, even for a short reading.
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: 48, availableWing: 63, activity: .timer), camera)
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: 48, availableWing: 64, activity: .timer).width, 304)
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: 110, availableWing: 120, activity: .timer).width, 336)
        // Agents can shrink their reading; they never keep the old 104-point wings.
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: 99, availableWing: 120, activity: .agent).width, 368)
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: 70, availableWing: 44, activity: .agent).width, 296)
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: 70, availableWing: 43, activity: .agent), camera)
    }

    func testMusicFitsArtworkAndMeterInsteadOfAPlayingLabel() {
        let wing = NotchLayout.musicWing(height: 38, physicalCamera: true)
        XCTAssertEqual(wing, 40)
        let camera = CGSize(width: 208, height: 38)
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: wing, availableWing: 60, activity: .music).width, 288)
        XCTAssertEqual(NotchLayout.compactSize(cameraSize: camera, requiredWing: wing, availableWing: 39, activity: .music), camera)
        XCTAssertEqual(NotchLayout.musicWing(height: 30, physicalCamera: false), 56)
    }

    func testPickerKeepsTheWidestStripAndCombinationWithoutMovingChoices() {
        XCTAssertEqual(NotchLayout.pickerWidth(stripWidths: [288, 304, 368], count: 3, labelWidth: 60, screenWidth: 1920), 416)
        XCTAssertEqual(NotchLayout.pickerWidth(stripWidths: [368, 288, 304], count: 3, labelWidth: 60, screenWidth: 1920), 416)
        XCTAssertEqual(NotchLayout.pickerWidth(stripWidths: [288, 304, 368], count: 3, labelWidth: 60, screenWidth: 400), 376)
    }

    func testMenuBarHeightSurvivesHidingButNotAResolutionChange() {
        var readings = NotchBarMeasurements()
        let size = CGSize(width: 5120, height: 1440)
        XCTAssertEqual(readings.height(displayID: 1, size: size, scale: 1, visibleGap: 30, fallback: 22), 30)
        XCTAssertEqual(readings.height(displayID: 1, size: size, scale: 1, visibleGap: 0, fallback: 22), 30)
        XCTAssertEqual(readings.height(displayID: 2, size: size, scale: 2, visibleGap: 0, fallback: .nan), 24)
        XCTAssertEqual(readings.height(displayID: 1, size: CGSize(width: 2560, height: 720), scale: 1, visibleGap: 0, fallback: 22), 22)
    }

    func testCompactReadoutsHaveReadableSizesAndCurveClearance() {
        for height in [24.0, 32, 34, 37.5] {
            let icon = NotchLayout.compactIconSize(height: height)
            let text = NotchLayout.compactTextSize(height: height)
            XCTAssertLessThanOrEqual(icon, height - 8)
            XCTAssertGreaterThanOrEqual(text, 14)
            XCTAssertGreaterThanOrEqual(NotchLayout.compactInset(height: height, contentHeight: icon), 5)
        }
    }

    func testCompactDurationFitsMinuteAndHourBoundariesWithoutSecondsJitter() {
        XCTAssertEqual(NotchLayout.compactDuration(1800), "30m")
        XCTAssertEqual(NotchLayout.compactDuration(1799.1), "30m")
        XCTAssertEqual(NotchLayout.compactDuration(1740), "29m")
        XCTAssertEqual(NotchLayout.compactDuration(3600), "1h")
        XCTAssertEqual(NotchLayout.compactDuration(5400), "1h30")
        XCTAssertEqual(NotchLayout.compactDuration(0.1), "1m")
        XCTAssertEqual(NotchLayout.compactDuration(.infinity), "∞")
    }

    func testMenuSpaceUsesNearestItemsAndRejectsUnknownOrOverlappingMenus() {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1243)
        let menus = [CGRect(x: -1920, y: 1205, width: 400, height: 38)]
        let status = [CGRect(x: -800, y: 1205, width: 200, height: 38)]
        XCTAssertEqual(NotchLayout.menuSideRoom(screen: screen, cameraWidth: 208, menuItems: menus, statusItems: status), 48)
        XCTAssertNil(NotchLayout.menuSideRoom(screen: screen, cameraWidth: 208, menuItems: [], statusItems: status))
        let overlap = [CGRect(x: -1000, y: 1205, width: 200, height: 38)]
        XCTAssertEqual(NotchLayout.menuSideRoom(screen: screen, cameraWidth: 208, menuItems: menus, statusItems: overlap), 0)
        let otherDisplay = [CGRect(x: 0, y: 1205, width: 400, height: 38)]
        XCTAssertNil(NotchLayout.menuSideRoom(screen: screen, cameraWidth: 208, menuItems: otherDisplay, statusItems: status))
    }

    func testExpandedWidthKeepsCameraClearanceAndFitsDisplay() {
        XCTAssertEqual(NotchLayout.expandedWidth(preferred: 480, cameraWidth: 208, screenWidth: 1920, shortcutAllowance: 144), 480)
        XCTAssertEqual(NotchLayout.expandedWidth(preferred: 600, cameraWidth: 208, screenWidth: 720, shortcutAllowance: 144), 552)
        XCTAssertEqual(NotchLayout.expandedWidth(preferred: 360, cameraWidth: 340, screenWidth: 1920, shortcutAllowance: 144), 376)
    }

    func testMeasuredToolsGrowAndShrinkWithoutPresetHeight() {
        XCTAssertEqual(NotchLayout.fittedHeight(measured: 237.2, screenHeight: 900), 238)
        XCTAssertEqual(NotchLayout.fittedHeight(measured: 518, screenHeight: 900), 518)
        XCTAssertEqual(NotchLayout.fittedHeight(measured: 186, screenHeight: 900), 186)
        XCTAssertEqual(NotchLayout.fittedHeight(measured: 1800, screenHeight: 768), 728)
    }

    func testCameraUsesHeadingSpaceInsteadOfAddingAnEmptyCompactBand() {
        let external = NotchLayout.contentBudget(screenHeight: 900, cameraHeight: 0)
        let builtIn = NotchLayout.contentBudget(screenHeight: 900, cameraHeight: 38)
        XCTAssertEqual(external - builtIn, 10)
        XCTAssertEqual(10 + NotchLayout.headingHeight(cameraHeight: 38), 38)
        XCTAssertEqual(builtIn + NotchLayout.headingHeight(cameraHeight: 38) + 38, 860)
    }

    func testAllItemsReachableWithoutScrollingOrDroppingRows() {
        var visited: [Int] = []
        for index in 0..<5 {
            let page = SurfacePage(itemCount: 13, requestedIndex: index, capacity: 3)
            XCTAssertEqual(page.count, 5)
            visited.append(contentsOf: page.range)
        }
        XCTAssertEqual(visited, Array(0..<13))
    }

    func testLastPageClampsWhenSessionsFinishOrDevicesDisappear() {
        let page = SurfacePage(itemCount: 4, requestedIndex: 8, capacity: 3)
        XCTAssertEqual(page.index, 1)
        XCTAssertEqual(page.range, 3..<4)
        let empty = SurfacePage(itemCount: 0, requestedIndex: 8, capacity: 0)
        XCTAssertEqual(empty.index, 0)
        XCTAssertTrue(empty.range.isEmpty)
    }
}
