import AppKit
import ApplicationServices
import OrbitCore

/// Only reads rectangles, off the UI thread. Never reads menu labels or asks for access.
actor NotchMenuSpaceReader {
    func availableWing(pid: pid_t, screen: CGRect, cameraWidth: Double, primaryTop: Double, excludingPID: pid_t) -> Double? {
        guard AXIsProcessTrusted(), !Task.isCancelled else { return nil }
        let app = AXUIElementCreateApplication(pid)
        guard let raw = attribute(app, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let menu = unsafeBitCast(raw, to: AXUIElement.self)
        guard let children = attribute(menu, kAXChildrenAttribute) as? [AXUIElement], !children.isEmpty, children.count <= 64 else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        var menus: [CGRect] = []
        for child in children {
            guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline,
                  let rect = rectangle(child, primaryTop: primaryTop) else { return nil }
            menus.append(rect)
        }
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let menuLayer = Int(CGWindowLevelForKey(.statusWindow))
        let status: [CGRect] = windows.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? Int32 != excludingPID,
                  let layer = info[kCGWindowLayer as String] as? Int, (menuLayer...menuLayer + 1).contains(layer),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width > 0, rect.width < screen.width - 2,
                  rect.height > 0, rect.height <= 64 else { return nil }
            return CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
        }
        return NotchLayout.menuSideRoom(screen: screen, cameraWidth: cameraWidth, menuItems: menus, statusItems: status)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.04)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private func rectangle(_ element: AXUIElement, primaryTop: Double) -> CGRect? {
        guard let origin = attribute(element, kAXPositionAttribute), CFGetTypeID(origin) == AXValueGetTypeID(),
              let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(origin, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent),
              point.x.isFinite, point.y.isFinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(x: point.x, y: primaryTop - point.y - extent.height, width: extent.width, height: extent.height)
    }
}
