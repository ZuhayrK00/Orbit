import AppKit
import Combine
import OrbitCore

@MainActor final class TextSelection: ObservableObject {
    @Published var input = "" { didSet { if input != oldValue { feedback = nil } } }
    @Published var transform = TextTransform.unchanged
    @Published private(set) var source = "Text workspace"
    @Published var feedback: String?
    private var element: AXUIElement?
    private var application: AXUIElement?
    private var capturedText = ""
    private var capturedRange: CFRange?
    var hasSelection: Bool { element != nil && !capturedText.isEmpty }
    var result: Result<String, Error> { Result { try transform.apply(to: input) } }
    var output: String { (try? result.get()) ?? "" }
    var canReplace: Bool { element != nil && capturedRange != nil }

    @discardableResult func capture() -> Bool {
        element = nil; application = nil; capturedRange = nil; capturedText = ""
        guard AXIsProcessTrusted(), let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let focused = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let target = unsafeBitCast(focused, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(target, 0.2)
        let role = attribute(target, kAXRoleAttribute) as? String ?? ""
        let subrole = attribute(target, kAXSubroleAttribute) as? String ?? ""
        guard !role.localizedCaseInsensitiveContains("secure"), !subrole.localizedCaseInsensitiveContains("secure"),
              let selected = attribute(target, kAXSelectedTextAttribute) as? String,
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selected.utf8.count <= TextActions.maximumBytes else { return false }
        element = target; application = app; capturedRange = range(target); capturedText = selected
        input = selected; source = front.localizedName ?? "Selected text"; transform = .unchanged; feedback = nil
        return true
    }
    func useText(_ text: String, source: String) {
        guard text.utf8.count <= TextActions.maximumBytes else { feedback = "Use text under 128 KB."; return }
        element = nil; application = nil; capturedRange = nil; capturedText = ""
        input = text; self.source = source; transform = .unchanged; feedback = nil
    }
    func replaceSelection() {
        guard let element, let application, let capturedRange, let output = try? result.get(),
              let currentFocus = attribute(application, kAXFocusedUIElementAttribute), CFEqual(currentFocus, element),
              attribute(element, kAXSelectedTextAttribute) as? String == capturedText,
              let currentRange = range(element), currentRange.location == capturedRange.location, currentRange.length == capturedRange.length else {
            feedback = "The original selection changed. Select the text again and reopen the wheel."; return
        }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success, settable.boolValue else {
            feedback = "This app doesn’t allow direct replacement. Copy the result and paste it yourself."; return
        }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, output as CFString) == .success else {
            feedback = "The app couldn’t replace this selection. Your result is ready to copy."; return
        }
        self.element = nil; self.application = nil; self.capturedRange = nil
        feedback = "Replaced in \(source)."
    }
    private func attribute(_ target: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(target, name as CFString, &value) == .success ? value : nil
    }
    private func range(_ target: AXUIElement) -> CFRange? {
        guard let value = attribute(target, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var range = CFRange(); return AXValueGetValue(ax, .cfRange, &range) ? range : nil
    }
}

enum WheelChoice: Identifiable {
    case tool(WheelSlot), transform(TextTransform), copy, search, workspace
    var id: String { switch self { case .tool(let slot): return slot.id.uuidString; case .transform(let action): return action.rawValue; case .copy: return "copy"; case .search: return "search"; case .workspace: return "workspace" } }
    var label: String { switch self { case .tool(let slot): return slot.label; case .transform(let action): return action.title; case .copy: return "Copy text"; case .search: return "Search web"; case .workspace: return "Text studio" } }
    var symbol: String { switch self { case .tool(let slot): return slot.action.symbol; case .transform(let action): return action.symbol; case .copy: return "doc.on.doc"; case .search: return "magnifyingglass"; case .workspace: return "text.cursor" } }
}
