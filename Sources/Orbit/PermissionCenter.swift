import AppKit
import ApplicationServices
import Combine
import EventKit
import UserNotifications
import OrbitCore

/// Read-only checks never request access. Requests are owned here so every
/// surface sees the same result, including changes made outside Orbit.
@MainActor final class PermissionCenter: ObservableObject {
    @Published private(set) var statuses: [OrbitPermission: PermissionStatus] = [:]
    @Published private(set) var requesting: Set<OrbitPermission> = []
    @Published private(set) var errors: [OrbitPermission: String] = [:]
    @Published private(set) var notificationDetail: String?
    @Published var guide: OrbitPermission?
    var changed: (() -> Void)?
    var guideRequested: ((OrbitPermission) -> Void)?
    var settingsVisible = false
    private let eventStore = EKEventStore()
    private var surfaces: Set<UUID> = []
    private var notificationRefresh: Task<Void, Never>?
    private var automationRefresh: Task<Void, Never>?
    private var lastLiveCheck = Date.distantPast
    private var lastDetailCheck = Date.distantPast
    private var resetCommand: ProviderCommand?
    private var requestedSystem: Set<OrbitPermission> = []
    private var generation = 0

    init(refreshImmediately: Bool = true) { if refreshImmediately { refresh() } }
    func status(_ kind: OrbitPermission) -> PermissionStatus { statuses[kind] ?? .checking }
    func isAllowed(_ kind: OrbitPermission) -> Bool { status(kind) == .granted }
    func setVisible(_ id: UUID, _ visible: Bool) {
        if visible { surfaces.insert(id); refresh(automation: true) } else { surfaces.remove(id) }
    }
    func tick(now: Date, monitorInput: Bool) {
        let watching = (!surfaces.isEmpty && settingsVisible) || guide != nil
        guard now.timeIntervalSince(lastLiveCheck) >= (watching || monitorInput ? 1 : 5) else { return }
        lastLiveCheck = now; refreshLive()
        if watching, now.timeIntervalSince(lastDetailCheck) >= 4 { refresh(automation: true) }
    }
    func refresh(automation: Bool = false) {
        refreshLive(); lastDetailCheck = Date()
        refreshNotifications()
        if automation { refreshAutomation() }
    }
    private func refreshLive() {
        update(.accessibility, AXIsProcessTrusted() ? .granted : .notGranted)
        update(.screenCapture, CGPreflightScreenCaptureAccess() ? .granted : .notGranted)
        update(.inputMonitoring, CGPreflightListenEventAccess() ? .granted : .notGranted)
        update(.calendar, Self.calendarStatus(EKEventStore.authorizationStatus(for: .event)))
        update(.systemAudio, .unknown); update(.files, .unknown)
    }
    private func update(_ kind: OrbitPermission, _ value: PermissionStatus) {
        guard statuses[kind] != value else { return }
        statuses[kind] = value
        if value == .granted { errors[kind] = nil }
        changed?()
    }
    static func calendarStatus(_ value: EKAuthorizationStatus) -> PermissionStatus {
        switch value {
        case .fullAccess: return .granted
        case .writeOnly: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notRequested
        @unknown default: return .unknown
        }
    }
    static func alertStatus(_ value: UNAuthorizationStatus) -> PermissionStatus {
        switch value {
        case .authorized: return .granted
        case .provisional, .ephemeral: return .limited
        case .denied: return .denied
        case .notDetermined: return .notRequested
        @unknown default: return .unknown
        }
    }
    static var canUseNotifications: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }
    private func refreshNotifications() {
        guard Self.canUseNotifications else { update(.notifications, .unavailable); return }
        guard notificationRefresh == nil, !requesting.contains(.notifications) else { return }
        notificationRefresh = Task { [weak self] in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard let self else { return }
            self.notificationRefresh = nil
            guard !Task.isCancelled, !self.requesting.contains(.notifications) else { return }
            self.applyNotificationSettings(settings)
        }
    }
    private func applyNotificationSettings(_ settings: UNNotificationSettings) {
        update(.notifications, Self.alertStatus(settings.authorizationStatus))
        let detail = settings.authorizationStatus == .authorized && settings.alertSetting != .enabled
            ? "Access is allowed, but banners are off. Change the alert style in System Settings." : nil
        if notificationDetail != detail { notificationDetail = detail }
    }
    private func refreshAutomation() {
        guard automationRefresh == nil else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let version = generation
        automationRefresh = Task { [weak self] in
            let values = await Task.detached(priority: .utility) {
                [OrbitPermission.music, .spotify, .finder].map { kind in
                    (kind, running.contains(kind.automationBundleID!) ? Self.automationStatus(kind, ask: false) : .unknown)
                }
            }.value
            guard let self else { return }; self.automationRefresh = nil
            guard !Task.isCancelled, version == self.generation else { return }
            for (kind, value) in values where !self.requesting.contains(kind) { self.update(kind, value) }
        }
    }
    nonisolated private static func automationStatus(_ kind: OrbitPermission, ask: Bool) -> PermissionStatus {
        guard let bundle = kind.automationBundleID else { return .unknown }
        let address = NSAppleEventDescriptor(bundleIdentifier: bundle)
        switch AEDeterminePermissionToAutomateTarget(address.aeDesc, typeWildCard, typeWildCard, ask) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notRequested
        default: return .unknown
        }
    }
    func request(_ kind: OrbitPermission) {
        guard !requesting.contains(kind) else { return }
        errors[kind] = nil
        switch kind {
        case .accessibility, .screenCapture, .inputMonitoring:
            refreshLive()
            guard !isAllowed(kind) else { return }
            if requestedSystem.insert(kind).inserted {
                switch kind {
                case .accessibility: _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                case .screenCapture: _ = CGRequestScreenCaptureAccess()
                default: _ = CGRequestListenEventAccess()
                }
            }
            refreshLive()
            if !isAllowed(kind) { openSettings(kind, guided: true) }
        case .calendar:
            refreshLive()
            guard !isAllowed(kind) else { return }
            guard kind.canRequest(status(kind)) else { openSettings(kind); return }
            requesting.insert(kind)
            Task { [weak self] in
                guard let self else { return }
                defer { self.requesting.remove(kind); self.refresh() }
                do { _ = try await self.eventStore.requestFullAccessToEvents() }
                catch { self.errors[kind] = error.localizedDescription }
            }
        case .notifications: requestAlerts(openIfDenied: true)
        case .music, .spotify, .finder:
            guard NSRunningApplication.runningApplications(withBundleIdentifier: kind.automationBundleID!).isEmpty == false else { openSettings(kind); return }
            requesting.insert(kind); generation += 1
            Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) { Self.automationStatus(kind, ask: true) }.value
                guard let self else { return }
                self.requesting.remove(kind); self.update(kind, result)
                if result == .denied { self.openSettings(kind) }
            }
        case .systemAudio, .files: openSettings(kind)
        }
    }
    /// A timer may ask once, but starting a timer after declining must never
    /// send the user to Settings or present repeated prompts.
    func requestAlerts(openIfDenied: Bool = false) {
        guard Self.canUseNotifications, requesting.insert(.notifications).inserted else { return }
        notificationRefresh?.cancel(); notificationRefresh = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.requesting.remove(.notifications) }
            let center = UNUserNotificationCenter.current()
            let before = await center.notificationSettings()
            if before.authorizationStatus == .notDetermined {
                do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
                catch { self.errors[.notifications] = error.localizedDescription }
            } else if openIfDenied, before.authorizationStatus == .denied { self.openSettings(.notifications) }
            self.applyNotificationSettings(await center.notificationSettings())
        }
    }
    func openSettings(_ kind: OrbitPermission, guided: Bool = false) {
        if guided { guide = kind; guideRequested?(kind) }
        if !NSWorkspace.shared.open(kind.settingsURL) {
            let fallback = kind == .systemAudio ? OrbitPermission.screenCapture.settingsURL : URL(string: "x-apple.systempreferences:com.apple.preference.security")!
            if !NSWorkspace.shared.open(fallback) { errors[kind] = "Open System Settings → Privacy & Security → \(kind.title)." }
        }
    }
    /// Called only after the user confirms the specific permission in the UI.
    func reset(_ kind: OrbitPermission) {
        guard let service = kind.resetService, let bundle = Bundle.main.bundleIdentifier,
              Bundle.main.bundleURL.pathExtension == "app", resetCommand == nil else { return }
        errors[kind] = nil
        let command = ProviderCommand(); resetCommand = command; requesting.insert(kind)
        Task { [weak self] in
            guard let self else { return }
            do {
                let (_, code) = try await command.run(executable: URL(fileURLWithPath: "/usr/bin/tccutil"), arguments: ["reset", service, bundle], environment: ProcessInfo.processInfo.environment, seconds: 5)
                if code != 0 { throw FileTools.failure("macOS could not reset this permission. Remove Orbit’s entry in System Settings and add this copy again.") }
                self.requestedSystem.remove(kind)
            } catch { self.errors[kind] = error.localizedDescription }
            self.resetCommand = nil; self.requesting.remove(kind); self.refresh()
            // Re-register this bundle after tccutil removed its old entry;
            // merely opening Settings would leave no Orbit switch to enable.
            if self.errors[kind] == nil { self.request(kind) }
        }
    }
    func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    func relaunch() {
        let options = NSWorkspace.OpenConfiguration(); options.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: options) { application, _ in
            if application != nil { DispatchQueue.main.async { NSApp.terminate(nil) } }
        }
    }
    func shutdown() { notificationRefresh?.cancel(); automationRefresh?.cancel(); resetCommand?.cancel() }
}
