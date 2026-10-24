import XCTest
import EventKit
import UserNotifications
import OrbitCore
@testable import Orbit

final class PermissionServiceTests: XCTestCase {
    @MainActor func testCalendarDoesNotTreatWriteOnlyAsReadable() {
        XCTAssertEqual(PermissionCenter.calendarStatus(.fullAccess), .granted)
        XCTAssertEqual(PermissionCenter.calendarStatus(.writeOnly), .limited)
        XCTAssertEqual(PermissionCenter.calendarStatus(.notDetermined), .notRequested)
        XCTAssertEqual(PermissionCenter.calendarStatus(.restricted), .restricted)
        XCTAssertEqual(PermissionCenter.calendarStatus(.denied), .denied)
    }
    @MainActor func testNotificationStatusDistinguishesQuietDeliveryAndDeniedAccess() {
        XCTAssertEqual(PermissionCenter.alertStatus(.authorized), .granted)
        XCTAssertEqual(PermissionCenter.alertStatus(.provisional), .limited)
        XCTAssertEqual(PermissionCenter.alertStatus(.denied), .denied)
        XCTAssertEqual(PermissionCenter.alertStatus(.notDetermined), .notRequested)
    }
    @MainActor func testUnprobedAccessCannotDisplayAsAllowed() {
        let permissions = PermissionCenter(refreshImmediately: false)
        for kind in OrbitPermission.allCases {
            XCTAssertEqual(permissions.status(kind), .checking)
            XCTAssertFalse(permissions.isAllowed(kind))
        }
        XCTAssertTrue(permissions.requesting.isEmpty)
        XCTAssertNil(permissions.guide)
    }
}
