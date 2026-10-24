import AppKit
import SwiftUI
import Combine

@MainActor final class PermissionGuideController {
    private weak var store: OrbitStore?
    private var panel: NSPanel?
    private var watcher: AnyCancellable?
    private var dismissTask: Task<Void, Never>?
    init(store: OrbitStore) {
        self.store = store
        store.permissions.guideRequested = { [weak self] _ in self?.show() }
        watcher = store.permissions.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.synchronize() }
        }
    }
    private func show() {
        close()
        guard let store, let kind = store.permissions.guide, !store.onboardingPresented else { return }
        let root = PermissionGuideContent(permissions: store.permissions, kind: kind).orbitControls(store).preferredColorScheme(.dark)
        let host = NSHostingView(rootView: root)
        // Reserve space for the recovery explanation so the guide does not
        // jump or clip while the user is working in System Settings.
        let size = NSSize(width: 370, height: 400)
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let panel = NSPanel(contentRect: NSRect(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 24, width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel; panel.orderFrontRegardless()
    }
    private func synchronize() {
        guard let permissions = store?.permissions else { return }
        guard let kind = permissions.guide else { close(); return }
        if permissions.isAllowed(kind), kind != .screenCapture, dismissTask == nil {
            dismissTask = Task { [weak self, weak permissions] in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                defer { self?.dismissTask = nil }
                guard !Task.isCancelled, permissions?.guide == kind, permissions?.isAllowed(kind) == true else { return }
                permissions?.guide = nil; self?.close()
            }
        }
    }
    func close() { dismissTask?.cancel(); dismissTask = nil; panel?.orderOut(nil); panel = nil }
}
