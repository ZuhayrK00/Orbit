import AppKit
import SwiftUI
import OrbitCore

@MainActor final class SelectionActionsController {
    private weak var store: OrbitStore?
    private var monitor: Any?
    private var local: Any?
    private var activation: NSObjectProtocol?
    private var pending: DispatchWorkItem?
    private var expiry: DispatchWorkItem?
    private var panel: NSPanel?
    private var selectionStart: NSPoint?
    init(store: OrbitStore) {
        self.store = store
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            guard let self else { return }
            self.close()
            if event.type == .leftMouseDown { self.selectionStart = NSEvent.mouseLocation; return }
            guard event.type == .leftMouseUp, store.configuration.productivity.selectionActionsEnabled == true else { return }
            let start = self.selectionStart; self.selectionStart = nil
            let end = NSEvent.mouseLocation
            let dragged = start.map { hypot(end.x - $0.x, end.y - $0.y) > 4 } ?? false
            // A plain click beside an old selection should not summon the wheel again.
            guard dragged || event.clickCount >= 2 || event.modifierFlags.contains(.shift) else { return }
            let work = DispatchWorkItem { [weak self] in self?.show() }; self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
        local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown, .scrollWheel]) { [weak self] event in if event.window !== self?.panel || event.type == .keyDown { self?.close() }; return event }
        activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.close() } }
    }
    private func show() {
        guard let store, store.configuration.productivity.selectionActionsEnabled == true, !store.wheelVisible,
              !(store.configuration.productivity.selectionExcludedApps ?? []).contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""), store.selection.capture() else { return }
        let value = store.selection.input
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        let size = 178.0, visible = screen.visibleFrame
        let frame = CGRect(x: min(max(visible.minX + 8, point.x - size / 2), visible.maxX - size - 8), y: min(max(visible.minY + 8, point.y - size - 12), visible.maxY - size - 8), width: size, height: size)
        let panel = SelectionPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .popUpMenu; panel.hidesOnDeactivate = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = SelectionHost(rootView: SelectionMiniWheel(store: store) { [weak self] index in
            self?.close()
            switch index {
            case 0: store.copy(value)
            case 1: store.copy(value.uppercased())
            case 2: store.copy(value.lowercased())
            case 3: store.copy((try? TextTransform.cleanLink.apply(to: value)) ?? value.trimmingCharacters(in: .whitespacesAndNewlines))
            case 4: if let url = TextActions.searchURL(value) { NSWorkspace.shared.open(url) }
            default: store.scratchpad.append(value); store.message("Added to the current note")
            }
        })
        self.panel = panel; panel.orderFrontRegardless()
        let expire = DispatchWorkItem { [weak self] in self?.close() }; expiry = expire
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: expire)
    }
    func close() { pending?.cancel(); pending = nil; expiry?.cancel(); expiry = nil; panel?.orderOut(nil); panel = nil }
    func shutdown() { close(); if let monitor { NSEvent.removeMonitor(monitor) }; if let local { NSEvent.removeMonitor(local) }; if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) } }
}
private final class SelectionPanel: NSPanel { override var canBecomeKey: Bool { false }; override var canBecomeMain: Bool { false } }
private final class SelectionHost<Content: View>: NSHostingView<Content> { override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true } }
private struct SelectionMiniWheel: View {
    @ObservedObject var store: OrbitStore
    var perform: (Int) -> Void
    private let actions = [("Copy", "doc.on.doc"), ("Uppercase", "textformat.abc"), ("Lowercase", "textformat"), ("Clean link / trim", "link"), ("Search web", "magnifyingglass"), ("Save to note", "square.and.pencil")]
    var body: some View {
        ZStack {
            Circle().fill(.clear).orbitGlass(in: Circle())
            OrbitMark(size: 23, color: .white.opacity(0.7))
            ForEach(actions.indices, id: \.self) { i in
                let angle = Double(i) * .pi / 3 - .pi / 2
                Button { perform(i) } label: { Image(systemName: actions[i].1).font(.system(size: 15)).frame(width: 38, height: 38).contentShape(Circle()) }.buttonStyle(OrbitIconButtonStyle()).help(actions[i].0).accessibilityLabel(actions[i].0)
                    .position(x: 89 + cos(angle) * 57, y: 89 + sin(angle) * 57)
            }
        }.frame(width: 178, height: 178).preferredColorScheme(.dark).orbitControls(store)
    }
}
