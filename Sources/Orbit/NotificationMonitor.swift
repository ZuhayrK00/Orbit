import AppKit
import Combine
import OrbitCore

@MainActor final class NotificationMonitor: ObservableObject {
    @Published private(set) var items: [NotchNotice] = []
    @Published private(set) var announcement: NotchNotice?
    @Published private(set) var status = "Off"
    @Published private(set) var liveActions: [String: [NoticeAction]] = [:]
    @Published private(set) var actionMessage: String?
    private(set) var expiresAt: Date?
    var holdAnnouncement = false
    var received: ((NotchNotice, Date) -> Void)?
    var cleared: (() -> Void)?
    var extended: ((Date) -> Void)?
    private var inbox = NotificationInbox()
    private let reader = NotificationBannerReader()
    private var options = NotchNotificationOptions()
    private var task: Task<Void, Never>?
    private var generation = 0
    private var currentPID: pid_t?
    private var locked = false
    private var wasPermitted = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var distributedObservers: [NSObjectProtocol] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.suspend() } }
            observers.append((workspace, token))
        }
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.locked = false } }
            observers.append((workspace, token))
        }
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in if locked { self?.suspend() } else { self?.locked = false } }
            })
        }
    }
    func configure(_ newOptions: NotchNotificationOptions, permitted: Bool) {
        var normalized = newOptions; normalized.normalize()
        if normalized != options {
            let wasEnabled = options.enabled
            options = normalized
            generation += 1; task?.cancel(); task = nil
            liveActions = [:]; Task { await reader.clear() }
            if !options.callsEnabled {
                for item in inbox.items where item.isCall { inbox.discard(item.id) }
                items = inbox.items
                if let announcement, announcement.isCall { dismiss(announcement.id) }
            }
            if !options.showPreview { inbox.redact(); items = inbox.items; announcement = announcement?.redacted }
            if wasEnabled != options.enabled { reset() }
        }
        if !options.enabled { status = "Off" }
        else if !permitted { if wasPermitted { reset() }; status = "Needs Accessibility access" }
        else if locked { status = "Paused while your Mac is locked" }
        else if status == "Off" || status == "Needs Accessibility access" { status = "Waiting for new banners" }
        wasPermitted = permitted
    }
    func tick(now: Date, permitted: Bool) {
        if let expiresAt, now >= expiresAt, !holdAnnouncement {
            announcement = nil; self.expiresAt = nil; cleared?()
        }
        guard options.enabled, permitted, !locked, task == nil else { return }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first?.processIdentifier else {
            status = "Waiting for macOS Notification Center"; return
        }
        if currentPID != pid { currentPID = pid; inbox.resumeWithBaseline() }
        // Accessibility coordinates originate at the top-left of the primary display.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let displays = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        let expected = generation
        let callApps = ["com.apple.FaceTime", "com.apple.mobilephone", "com.apple.facetime.NotificationService", "com.apple.facetime.NotificationViewBridgeService"]
        let calls = options.callsEnabled ? NSWorkspace.shared.runningApplications.compactMap { app -> CallBannerSource? in
            guard let id = app.bundleIdentifier, callApps.contains(id) else { return nil }
            let helper = id.hasPrefix("com.apple.facetime.")
            return CallBannerSource(pid: app.processIdentifier, name: helper ? "FaceTime" : app.localizedName ?? "Phone", bundleID: helper ? "com.apple.FaceTime" : id)
        } : []
        task = Task { [weak self, reader] in
            let result = await reader.read(pid: pid, displays: displays, now: now, calls: calls)
            guard let self, self.generation == expected else { return }
            // Release this read even if access was revoked while it was in flight.
            // A result from an older generation must not clear a newer task.
            self.task = nil
            guard !Task.isCancelled, self.options.enabled, !self.locked, self.wasPermitted, AXIsProcessTrusted() else { return }
            switch result {
            case .notices(let notices):
                self.status = "Watching new banners"
                self.liveActions = Dictionary(notices.map { ($0.id, $0.actions) }, uniquingKeysWith: { first, _ in first })
                let resolved = notices.map(NotificationIdentity.resolve)
                let fresh = self.inbox.ingest(resolved, showPreview: self.options.showPreview)
                self.items = self.inbox.items
                if let newest = fresh.last { self.announce(newest, now: now) }
                if let active = self.announcement, active.isCall {
                    if notices.contains(where: { $0.id == active.id }) { self.expiresAt = now.addingTimeInterval(5); self.extended?(self.expiresAt!) }
                    else { self.dismiss(active.id) }
                }
            case .historyOpen:
                self.liveActions = [:]
                self.status = "Paused while Notification Center is open"; self.inbox.resumeWithBaseline()
            case .unavailable: self.liveActions = [:]; self.status = "Waiting for readable macOS banners"
            }
        }
    }
    func preview() {
        guard !locked else { return }
        let sample = NotchNotice(id: "orbit-notification-preview", app: "Orbit · Preview", title: "A little heads-up", body: "New notifications appear here, then your notch returns to what it was doing.", isSample: true, bundleID: Bundle.main.bundleIdentifier)
        announce(options.showPreview ? sample : sample.redacted, now: Date())
    }
    func dismiss(_ id: String) {
        inbox.discard(id); items = inbox.items
        if announcement?.id == id { announcement = nil; expiresAt = nil; cleared?() }
    }
    func clear() { inbox.clearDisplay(); items = []; announcement = nil; expiresAt = nil; cleared?() }
    func openApp(_ notice: NotchNotice) {
        guard !locked, let id = notice.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    func perform(_ action: NoticeAction, notice: NotchNotice) {
        guard options.enabled, wasPermitted, !locked, liveActions[notice.id]?.contains(action) == true else { return }
        let expected = generation
        Task {
            let success = await reader.perform(noticeID: notice.id, actionID: action.id)
            guard generation == expected else { return }
            actionMessage = success ? (action.kind == .reply ? "Continue your reply in the app’s notification." : nil) : "That notification is no longer available. Open the app to continue."
            if success, action.kind != .reply { dismiss(notice.id) }
        }
    }
    private func announce(_ notice: NotchNotice, now: Date) {
        actionMessage = nil
        announcement = notice; expiresAt = now.addingTimeInterval(options.duration)
        received?(notice, expiresAt!)
    }
    private func suspend() { locked = true; reset(); status = options.enabled ? "Paused while your Mac is locked" : "Off" }
    private func reset() {
        holdAnnouncement = false
        generation += 1; task?.cancel(); task = nil; currentPID = nil; inbox.reset()
        liveActions = [:]; actionMessage = nil
        Task { await reader.clear() }
        items = []; announcement = nil; expiresAt = nil; cleared?()
    }
    func shutdown() {
        reset()
        for (center, token) in observers { center.removeObserver(token) }; observers.removeAll()
        for token in distributedObservers { DistributedNotificationCenter.default().removeObserver(token) }; distributedObservers.removeAll()
    }
}
