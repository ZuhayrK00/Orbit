import AppKit
import ApplicationServices
import OrbitCore

enum BannerReadResult: Sendable {
    case notices([NotchNotice])
    case historyOpen
    case unavailable
}

struct CallBannerSource: Sendable { let pid: pid_t; let name: String; let bundleID: String }

/// Visible surfaces only. Native action handles expire with the current snapshot;
/// they are invoked only after an explicit click in Orbit.
actor NotificationBannerReader {
    private var bindings: [String: [String: NativeNoticeAction]] = [:]
    private var readAt = Date.distantPast
    private var screens: [CGRect] = []
    func clear() { bindings.removeAll(); readAt = .distantPast }
    func perform(noticeID: String, actionID: String) -> Bool {
        guard AXIsProcessTrusted(), Date().timeIntervalSince(readAt) < 2,
              let binding = bindings[noticeID]?[actionID] else { return false }
        let element = binding.element
        let snapshot = BannerSnapshot(displays: screens)
        guard let frame = snapshot.frame(element), screens.contains(where: { $0.intersects(frame) }),
              snapshot.value(element, kAXEnabledAttribute) as? Bool != false,
              snapshot.value(element, "AXHidden") as? Bool != true else { return false }
        return AXUIElementPerformAction(element, binding.name as CFString) == .success
    }
    func read(pid: pid_t, displays: [CGRect], now: Date, calls: [CallBannerSource] = []) -> BannerReadResult {
        clear(); screens = displays
        guard AXIsProcessTrusted(), !Task.isCancelled else { return .unavailable }
        let snapshot = BannerSnapshot(displays: displays)
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.04)
        var focused: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused)
        if focusResult == .success, focused != nil { return .historyOpen }
        guard focusResult == .noValue || focusResult == .success else { return .unavailable }
        guard let windows = snapshot.value(application, kAXWindowsAttribute) as? [AXUIElement], windows.count <= 24 else { return .unavailable }
        var roots: [BannerNode] = []
        for window in windows {
            guard let frame = snapshot.frame(window), displays.contains(where: { $0.intersects(frame) }) else { continue }
            if let root = snapshot.node(window, depth: 0) { roots.append(root) }
        }
        guard !snapshot.incomplete, !Task.isCancelled else { return .unavailable }
        var notices = BannerParser.notices(in: roots, now: now)
        bind(notices, snapshot: snapshot)
        for source in calls {
            let callSnapshot = BannerSnapshot(displays: displays)
            let app = AXUIElementCreateApplication(source.pid)
            guard let windows = callSnapshot.value(app, kAXWindowsAttribute) as? [AXUIElement], windows.count <= 12 else { continue }
            for window in windows {
                guard let frame = callSnapshot.frame(window), displays.contains(where: { $0.intersects(frame) }),
                      let root = callSnapshot.node(window, depth: 0), !callSnapshot.incomplete,
                      let call = BannerParser.incomingCall(in: root, app: source.name, bundleID: source.bundleID, now: now) else { continue }
                notices.append(call); bind([call], snapshot: callSnapshot)
            }
        }
        readAt = Date()
        return .notices(notices)
    }
    private func bind(_ notices: [NotchNotice], snapshot: BannerSnapshot) {
        for notice in notices {
            var actions: [String: NativeNoticeAction] = [:]
            for action in notice.actions { if let element = snapshot.elements[action.id] { actions[action.id] = element } }
            bindings[notice.id] = actions
        }
    }
}

private struct NativeNoticeAction { let element: AXUIElement; let name: String }

private final class BannerSnapshot {
    let displays: [CGRect]
    private let deadline = ProcessInfo.processInfo.systemUptime + 0.25
    private var visited = 0
    var incomplete = false
    var elements: [String: NativeNoticeAction] = [:]
    init(displays: [CGRect]) { self.displays = displays }
    private var canRead: Bool {
        guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { incomplete = true; return false }
        return true
    }
    func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        guard canRead else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.04)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        if error == .cannotComplete || error == .invalidUIElement { incomplete = true }
        return error == .success ? result : nil
    }
    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        guard let result = value(element, attribute) as? String else { return "" }
        guard result.utf8.count <= 16_384 else { incomplete = true; return "" }
        return result
    }
    func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = value(element, kAXPositionAttribute), CFGetTypeID(origin) == AXValueGetTypeID(),
              let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(origin, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent), extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }
    func node(_ element: AXUIElement, depth: Int) -> BannerNode? {
        guard canRead, visited < 300, depth < 12 else { incomplete = true; return nil }
        visited += 1
        if (value(element, "AXHidden") as? Bool) == true { return nil }
        if let rect = frame(element), !displays.contains(where: { $0.intersects(rect) }) { return nil }
        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        let identifier = string(element, kAXIdentifierAttribute)
        let children = value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        guard children.count <= 150 else { incomplete = true; return nil }
        let key = "element-\(CFHash(element))"
        var nativeActions: CFArray?
        AXUIElementCopyActionNames(element, &nativeActions)
        let pressable = (nativeActions as? [String])?.contains(kAXPressAction) == true && value(element, kAXEnabledAttribute) as? Bool != false
        if pressable { elements[key] = NativeNoticeAction(element: element, name: kAXPressAction) }
        var exposed: [NoticeAction] = []
        for name in (nativeActions as? [String] ?? []).prefix(12) where name != kAXPressAction {
            guard canRead else { break }
            var description: CFString?
            AXUIElementCopyActionDescription(element, name as CFString, &description)
            let label = description as String? ?? name
            if let kind = NoticeAction.kind(for: label) {
                let actionKey = key + "-" + name
                exposed.append(NoticeAction(id: actionKey, title: label, kind: kind))
                elements[actionKey] = NativeNoticeAction(element: element, name: name)
            }
        }
        let label = [string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute)].first { !$0.isEmpty } ?? ""
        return BannerNode(key: key, role: role, subrole: subrole,
                          field: identifier, text: role == kAXStaticTextRole ? string(element, kAXValueAttribute) : "",
                          label: label, pressable: pressable, exposedActions: exposed,
                          children: children.compactMap { node($0, depth: depth + 1) })
    }
}
