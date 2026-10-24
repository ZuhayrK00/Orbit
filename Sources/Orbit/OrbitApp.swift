import AppKit
import SwiftUI
import UserNotifications
import OrbitCore
import Combine

@main enum OrbitEntry {
    @MainActor static func main() {
        if CommandLine.arguments.count > 1, OrbitCLI.run(Array(CommandLine.arguments.dropFirst())) { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = OrbitAppDelegate(); app.delegate = delegate
        app.run()
    }
}

@MainActor final class OrbitAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private var store: OrbitStore!
    private var wheel: WheelController!
    private var notch: NotchController!
    private var triggers: TriggerController!
    private var selectionActions: SelectionActionsController!
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var mouseRetryTimer: Timer?
    private var surfaceSubscription: AnyCancellable?
    private var permissionGuide: PermissionGuideController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        store = OrbitStore(); wheel = WheelController(store: store); notch = NotchController(store: store); triggers = TriggerController(store: store); selectionActions = SelectionActionsController(store: store)
        permissionGuide = PermissionGuideController(store: store)
        do { try AgentInstaller.refreshInstalledBridge(); store.codexAccount.refreshActivity(); store.claudeAccount.refreshActivity() }
        catch { store.error = "Could not update the installed activity bridge: \(error.localizedDescription)" }
        store.openWheel = { [weak self] in self?.popover?.close(); self?.wheel.show() }
        store.hideWheel = { [weak self] in self?.wheel.dismiss() }
        store.openSettings = { [weak self] in self?.showDashboard(section: .settings) }
        store.previewNotch = { [weak self] in self?.notch.preview() }
        store.focusNotch = { [weak self] in self?.notch.focus() }
        store.configurationChanged = { [weak self] in self?.triggers.rebuild(); self?.selectionActions.close(); self?.notch.rebuild(); self?.wheel.updateAppearance(); self?.updateStatusItem() }
        // PermissionCenter owns access status. Retry a failed mouse tap
        // independently, since Input Monitoring can change after Accessibility.
        mouseRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.store.configuration.mouseEnabled, self.store.inputPermission, !self.store.mouseMonitoring else { return }
                self.triggers.rebuild()
            }
        }
        if PermissionCenter.canUseNotifications { UNUserNotificationCenter.current().delegate = self }
        surfaceSubscription = Publishers.CombineLatest(store.$menuSection, store.$configuration.map { $0.effectiveTimerPresets.count })
            .map { ToolLayout.menuHeight($0.0, timerPresetCount: $0.1) }.removeDuplicates()
            .sink { [weak self] height in
                DispatchQueue.main.async { self?.popover?.contentSize = NSSize(width: 400, height: height) }
            }
        updateStatusItem(); installMenu()
        if store.onboardingPresented { showDashboard(section: .settings) }
        if ProcessInfo.processInfo.arguments.contains("--show-wheel") { wheel.show() }
    }
    func applicationDidBecomeActive(_ notification: Notification) { store?.refreshPermissions(); triggers?.rebuild() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDashboard(section: .settings); return true }
    func application(_ application: NSApplication, open urls: [URL]) { showDashboard(section: .settings) }
    func applicationWillTerminate(_ notification: Notification) { permissionGuide?.close(); store.permissions.shutdown(); store.notifications.shutdown(); store.clipboardHistory.shutdown(); store.scratchpad.flush(); store.awake.shutdown(); triggers.shutdown(); selectionActions.shutdown(); store.agentAwake.stop(); store.screenText.cancel(); wheel.dismiss(); notch.shutdown(); store.audio.stopAll(); store.codexAccount.shutdown(); store.claudeAccount.shutdown(); mouseRetryTimer?.invalidate() }
    func windowWillClose(_ notification: Notification) { store.permissions.settingsVisible = false }
    func windowDidMiniaturize(_ notification: Notification) { store.permissions.settingsVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { store.permissions.settingsVisible = true; store.refreshPermissions() }
    private func showDashboard(section: OrbitAction) {
        store.refreshPermissions()
        popover?.close(); wheel.dismiss(); store.notchExpanded = false; store.selectedSection = .settings
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Orbit Settings"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.backgroundColor = .clear; window.isOpaque = false; window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 840, height: 680); window.delegate = self
            window.contentView = NSHostingView(rootView: OrbitRootView(store: store)); window.center(); self.window = window
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); store.permissions.settingsVisible = true
    }
    private func updateStatusItem() {
        if !store.configuration.menuBarEnabled { if let statusItem { NSStatusBar.system.removeStatusItem(statusItem); self.statusItem = nil }; return }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "Orbit")
        item.button?.target = self; item.button?.action = #selector(showPopover); item.button?.toolTip = "Orbit · your Mac, within reach"
        statusItem = item
    }
    @objc private func showPopover() {
        guard let button = statusItem?.button else { wheel.show(); return }
        if popover?.isShown == true { popover?.close(); return }
        wheel.dismiss(); store.notchExpanded = false
        NSApp.activate(ignoringOtherApps: true)
        if store.menuSection == nil { store.menuSection = .sound }
        let popover = NSPopover(); popover.behavior = .transient; popover.contentSize = NSSize(width: 400, height: ToolLayout.menuHeight(store.menuSection, timerPresetCount: store.configuration.effectiveTimerPresets.count))
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: MenuBarView(store: store)); self.popover = popover
        DispatchQueue.main.async {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }
    private func installMenu() {
        let main = NSMenu(), appMenu = NSMenu(), appItem = NSMenuItem()
        appItem.submenu = appMenu; main.addItem(appItem)
        appMenu.addItem(withTitle: "Open Orbit controls", action: #selector(showPopover), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "Orbit Settings…", action: #selector(settingsMenu), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Quick Setup…", action: #selector(setupMenu), keyEquivalent: "").target = self
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit Orbit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit"), editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key) }
        NSApp.mainMenu = main
    }
    @objc private func setupMenu() { store.startOnboarding() }
    @objc private func settingsMenu() { showDashboard(section: .settings) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}
