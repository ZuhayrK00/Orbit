import XCTest
@testable import OrbitCore

final class PermissionPolicyTests: XCTestCase {
    func testDeniedOrRestrictedAccessNeverOffersAnotherNativeRequest() {
        for kind in OrbitPermission.allCases {
            XCTAssertFalse(kind.canRequest(.denied), kind.rawValue)
            XCTAssertFalse(kind.canRequest(.restricted), kind.rawValue)
            XCTAssertFalse(kind.canRequest(.granted), kind.rawValue)
        }
    }
    func testCalendarWriteOnlyNeedsUpgradeButQuietNotificationAccessDoesNot() {
        XCTAssertTrue(OrbitPermission.calendar.canRequest(.limited))
        XCTAssertFalse(OrbitPermission.notifications.canRequest(.limited))
        XCTAssertTrue(OrbitPermission.notifications.canRequest(.notRequested))
        XCTAssertFalse(OrbitPermission.notifications.canRequest(.unknown))
    }
    func testUnobservablePermissionsCannotClaimARequestFlow() {
        for kind in [OrbitPermission.systemAudio, .files] {
            for status in [PermissionStatus.notRequested, .unknown, .notGranted] {
                XCTAssertFalse(kind.canRequest(status))
            }
        }
        XCTAssertNotEqual(OrbitPermission.systemAudio.settingsURL, OrbitPermission.screenCapture.settingsURL)
    }
    func testRecoveryResetsOnlyTheTwoExplicitlySupportedServices() {
        XCTAssertEqual(OrbitPermission.accessibility.resetService, "Accessibility")
        XCTAssertEqual(OrbitPermission.screenCapture.resetService, "ScreenCapture")
        for kind in OrbitPermission.allCases where kind != .accessibility && kind != .screenCapture {
            XCTAssertNil(kind.resetService)
        }
    }
}
