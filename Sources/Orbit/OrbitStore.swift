import AppKit
import SwiftUI
import Combine
import UserNotifications
import ServiceManagement
import OrbitCore
import UniformTypeIdentifiers

@MainActor final class OrbitStore: ObservableObject {
    @Published var configuration = OrbitConfiguration() { didSet { saveConfiguration() } }
    @Published var selectedSection: OrbitAction = .settings
    @Published var settingsTab = "Controls"
    @Published var wheelPinned = false
    @Published var wheelSection: OrbitAction?
    @Published var menuSection: OrbitAction?
    @Published private var notchNavigation = NotchNavigation()
    var notchSection: OrbitAction { notchNavigation.current }
    var rememberedNotchSection: OrbitAction { notchNavigation.remembered }
    var notchShowsNotification: Bool { notchNavigation.isShowingNotification }
    @Published var notchPinned = false
    @Published var hoveredSlot: Int?
    @Published var wheelVisible = false
    @Published var wheelUsesSelection = false
    @Published var notchExpanded = false { didSet { notchActivityPickerVisible = false; if !notchExpanded { notchAlertUntil = nil; notifications.holdAnnouncement = false } } }
    var notchAlertUntil: Date?
    @Published var selectedFiles: [URL] = []
    @Published var toast: String?
    @Published var toastIsPositive = true
    @Published var error: String?
    @Published var isProcessing = false
    @Published var timerState = OrbitTimer()
    @Published var now = Date()
    @Published var timerFinished = false
    private var timerFinishedAt: Date?
    @Published private(set) var notchActivitySelection = NotchActivitySelection()
    @Published var notchActivityPickerVisible = false { didSet { if !notchActivityPickerVisible { notchActivityPickerPinned = false } } }
    @Published var notchActivityPickerPinned = false
    @Published var preferredNotchAgentID: String?
    @Published var holdNotchMusic = false
    @Published var agents: [AgentStatus] = []
    @Published var agentMetrics: [AgentSessionMetrics] = []
    @Published private(set) var inputPermission = false
    @Published var mouseMonitoring = false
    @Published var mouseTriggerStatus = "Mouse trigger is off"
    @Published var onboardingPresented = !UserDefaults.standard.bool(forKey: "Orbit.onboardingCompleted.v1")
    @Published var onboardingStep = 0
    @Published var triggerStatus = ""
    let clipboardHistory = ItemLibrary(shelf: false)
    let shelf = ItemLibrary(shelf: true)
    let permissions: PermissionCenter
    let calendar: CalendarService
    let downloads = DownloadService()
    let screenText: ScreenTextService
    let agentAwake = AgentAwakeSession()
    @Published var focusCycle = FocusCycle()
    @Published var stopwatch = StopwatchState()
    @Published var timerMode = 0
    @Published var activeWheelProfile: UUID?
    @Published var wheelProfileStack: [UUID?] = []
    @Published var recordingProfile: UUID?
    @Published var recordingGesture = false
    private var featureSubscriptions: Set<AnyCancellable> = []
    private let focusURL = OrbitPaths.support.appendingPathComponent("focus.json")
    private let stopwatchURL = OrbitPaths.support.appendingPathComponent("stopwatch.json")
    @Published var keyboardRecording = false
    @Published var mouseRecording = false
    let selection = TextSelection()
    let scratchpad = Scratchpad()
    let awake = AwakeSession()
    let audio = AudioService()
    let media = MediaService()
    let notifications = NotificationMonitor()
    let codexAccount = AgentAccountConnection(.codex)
    let claudeAccount = AgentAccountConnection(.claude)
    var openWheel: (() -> Void)?
    var hideWheel: (() -> Void)?
    var openSettings: (() -> Void)?
    var previewNotch: (() -> Void)?
    var focusNotch: (() -> Void)?
    var configurationChanged: (() -> Void)?
    private var clock: Timer?
    private var awakeSubscription: AnyCancellable?
    private var toastTimer: Timer?
    private var lastAgentRefresh = Date.distantPast
    private let configURL = OrbitPaths.support.appendingPathComponent("configuration.json")
    private let timerURL = OrbitPaths.support.appendingPathComponent("timer.json")
    private static let notchToolPreference = "Orbit.notch.lastTool.v1"
    private var ready = false
    private let localAgentReader = LocalAgentReader()
    private var localAgentTask: Task<Void, Never>?
    private var localAgents: [AgentStatus] = []
    private var dismissedAgents: [String: Date] = [:]

    init() {
        permissions = PermissionCenter()
        calendar = CalendarService(permissions: permissions)
        screenText = ScreenTextService(permissions: permissions)
        notchNavigation = NotchNavigation(savedTool: UserDefaults.standard.string(forKey: Self.notchToolPreference))
        do {
            try OrbitPaths.prepare()
            if FileManager.default.fileExists(atPath: configURL.path) { configuration = try ConfigurationIO.load(from: configURL) }
            if let data = try? Data(contentsOf: timerURL), let state = try? JSONDecoder().decode(OrbitTimer.self, from: data) { timerState = state }
        } catch { self.error = "Orbit could not load its settings: \(error.localizedDescription)" }
        if let data = try? Data(contentsOf: focusURL), let state = try? JSONDecoder().decode(FocusCycle.self, from: data) { focusCycle = state; if !timerState.isActive { focusCycle.running = false } }
        if let data = try? Data(contentsOf: stopwatchURL), let state = try? JSONDecoder().decode(StopwatchState.self, from: data) { stopwatch = state }
        if focusCycle.running { timerMode = 1 }
        for publisher in [clipboardHistory.objectWillChange, shelf.objectWillChange, calendar.objectWillChange, permissions.objectWillChange, downloads.objectWillChange, screenText.objectWillChange, agentAwake.objectWillChange] {
            publisher.sink { [weak self] in DispatchQueue.main.async { self?.objectWillChange.send() } }.store(in: &featureSubscriptions)
        }
        configureProductivity()
        ready = true
        inputPermission = permissions.isAllowed(.accessibility)
        permissions.changed = { [weak self] in self?.applyPermissionChanges() }
        awakeSubscription = awake.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
        audio.configure(configuration.mixer)
        audio.preferencesChanged = { [weak self] options in self?.configuration.mixerSettings = options }
        awake.configure(configuration.awake, launching: true)
        notifications.received = { [weak self] notice, until in
            guard let self, self.configuration.notchEnabled else { return }
            if self.configuration.notifications.expandAutomatically && (notice.isSample || !self.notchExpanded) {
                self.notchNavigation.showNotification()
                self.notchPinned = false; self.notchExpanded = true
                self.notchAlertUntil = until
            } else if self.notchAlertUntil != nil { self.notchAlertUntil = until }
            // A settings preview is an explicit interaction; real arrivals never steal focus.
            if notice.isSample { DispatchQueue.main.async { [weak self] in self?.focusNotch?() } }
        }
        notifications.cleared = { [weak self] in
            guard let self else { return }
            if self.notchAlertUntil != nil && !self.notchPinned { self.notchExpanded = false }
            self.notchAlertUntil = nil
        }
        notifications.extended = { [weak self] until in
            if self?.notchAlertUntil != nil { self?.notchAlertUntil = until }
        }
        notifications.configure(configuration.notifications, permitted: inputPermission)
        refreshAgentActivity(); agentMetrics = AgentSessionMetrics.read()
        let clock = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(clock, forMode: .common)
        self.clock = clock
    }
    func editProductivity(_ update: (inout ProductivityOptions) -> Void) { var options = configuration.productivity; update(&options); options.normalize(); configuration.productivitySettings = options }
    func saveConfiguration() {
        guard ready else { return }
        do { try ConfigurationIO.save(configuration, to: configURL) }
        catch { self.error = "Could not save settings: \(error.localizedDescription)" }
        configureProductivity()
        notifications.configure(configuration.notifications, permitted: inputPermission)
        configurationChanged?()
        awake.configure(configuration.awake)
        audio.configure(configuration.mixer)
    }
    func message(_ text: String, positive: Bool = true) {
        toastIsPositive = positive; toast = text; toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in Task { @MainActor in self?.toast = nil } }
    }
    private func tick() {
        now = Date()
        calendar.refresh(); downloads.tick(); agentAwake.update(agents, batteryCutoff: configuration.awake.batteryCutoff)
        awake.tick(now: now, permitted: inputPermission)
        permissions.tick(now: now, monitorInput: configuration.mouseEnabled || configuration.notifications.enabled || configuration.contextualTextWheel != false)
        notifications.tick(now: now, permitted: inputPermission)
        if timerState.end != nil, timerState.remaining(at: now) <= 0 {
            if focusCycle.running {
                focusCycle.advance(rounds: configuration.productivity.focusRounds ?? 4)
                timerState.start(seconds: focusCycle.seconds(configuration.productivity), now: now); persistFocus()
            } else { timerState.cancel() }
            persistTimer(); timerFinished = !focusCycle.running; timerFinishedAt = now
            NSSound(named: "Glass")?.play()
            let content = UNMutableNotificationContent(); content.title = "Time’s up"; content.body = focusCycle.running ? "\(focusCycle.title) started." : "Your Orbit timer has finished."; content.sound = .default
            if PermissionCenter.canUseNotifications { UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
            message(focusCycle.running ? "\(focusCycle.title) started" : "Your timer has finished")
        }
        if now.timeIntervalSince(lastAgentRefresh) >= 2 {
            lastAgentRefresh = now; refreshAgentActivity(); agentMetrics = AgentSessionMetrics.read(); audio.refresh()
            if configuration.mediaEnabled { media.refresh() }
        }
        if configuration.clipboardEnabled { clipboardHistory.poll(excludedApps: configuration.productivity.clipboardExcludedApps ?? []) }
        var selection = notchActivitySelection
        selection.reconcile(available: availableNotchActivities)
        if selection != notchActivitySelection { notchActivitySelection = selection }
    }
    var reduceMotion: Bool { configuration.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func refreshPermissions(announce: Bool = false) {
        permissions.refresh(automation: true)
        if announce { message(inputPermission ? "Accessibility access is confirmed by macOS" : "Access is not enabled for this copy. Open “Already enabled?” for help.", positive: inputPermission) }
    }
    private func applyPermissionChanges() {
        let allowed = permissions.isAllowed(.accessibility)
        if allowed != inputPermission {
            inputPermission = allowed
            notifications.configure(configuration.notifications, permitted: allowed)
            configurationChanged?()
            if allowed { message("Accessibility access is enabled") }
        }
        if calendar.allowed != permissions.isAllowed(.calendar) { calendar.refresh(force: true) }
    }
    func requestAccessibility() { permissions.request(.accessibility) }
    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "Orbit.onboardingCompleted.v1")
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.9)) { onboardingPresented = false }
    }
    func startOnboarding() { onboardingStep = 0; onboardingPresented = true; openSettings?() }
    func startTimer(minutes: Double) {
        // The deadline and its first rendered countdown must share one timestamp.
        // Otherwise the previous half-second tick rounds a new timer up by 1 s.
        now = Date()
        focusCycle.running = false; persistFocus()
        timerFinished = false; timerFinishedAt = nil; timerState.start(seconds: minutes * 60, now: now); persistTimer()
        permissions.requestAlerts()
        message("Timer started · \(Int(minutes)) min")
    }
    func toggleTimer() {
        now = Date()
        if timerState.end != nil { timerState.pause(now: now) } else { timerState.resume(now: now) }
        persistTimer()
    }
    func cancelTimer() { focusCycle.running = false; persistFocus(); timerState.cancel(); timerFinished = false; timerFinishedAt = nil; persistTimer() }
    private func persistTimer() { if let data = try? JSONEncoder().encode(timerState) { try? data.write(to: timerURL, options: .atomic) } }
    private func configureProductivity() {
        clipboardHistory.configure(enabled: configuration.clipboardEnabled, persistence: configuration.productivity.clipboardPersistence == true, limit: configuration.clipboardLimit)
        calendar.configure(configuration.productivity); downloads.configure(configuration.productivity)
    }
    func copy(_ text: String) {
        clipboardHistory.copy(StoredItem(kind: .text, text: text)); message("Copied to clipboard")
    }
    func startFocus() {
        now = Date(); timerFinished = false; focusCycle = FocusCycle(); focusCycle.running = true
        permissions.requestAlerts()
        timerState.start(seconds: focusCycle.seconds(configuration.productivity), now: now); persistFocus(); persistTimer()
    }
    func skipFocus() { guard focusCycle.running else { return }; now = Date(); focusCycle.advance(rounds: configuration.productivity.focusRounds ?? 4); timerState.start(seconds: focusCycle.seconds(configuration.productivity), now: now); persistFocus(); persistTimer() }
    private func persistFocus() { if let data = try? JSONEncoder().encode(focusCycle) { try? data.write(to: focusURL, options: .atomic) } }
    func changeStopwatch(_ action: Int) { now = Date(); if action == 0 { stopwatch.toggle(at: now) } else if action == 1 { stopwatch.lap(at: now) } else { stopwatch = .init() }; if let data = try? JSONEncoder().encode(stopwatch) { try? data.write(to: stopwatchURL, options: .atomic) } }
    func captureScreenText() {
        hideWheel?(); notchExpanded = false
        screenText.capture { [weak self] text in self?.copy(text); self?.selection.useText(text, source: "Screen text") }
    }
    func refreshAgentActivity() {
        let merged = AgentActivity.merge(hooks: AgentBridge.read(), local: localAgents, now: now)
        agents = merged.filter { $0.updatedAt > (dismissedAgents[$0.id] ?? .distantPast) }
        guard localAgentTask == nil else { return }
        var roots: [LocalAgentRoot] = []
        if codexAccount.localMonitoringEnabled { roots.append(LocalAgentRoot(provider: .codex, directory: ProviderRuntime.configurationDirectory(.codex).appendingPathComponent("sessions"))) }
        if claudeAccount.localMonitoringEnabled { roots.append(LocalAgentRoot(provider: .claude, directory: ProviderRuntime.configurationDirectory(.claude, account: claudeAccount.account).appendingPathComponent("projects"))) }
        let reader = localAgentReader
        localAgentTask = Task { [weak self] in
            let found = await reader.scan(roots: roots)
            guard let self else { return }
            self.localAgentTask = nil
            // A toggle can change while the actor is reading. Apply it before publishing.
            self.localAgents = found.filter { $0.provider == "Codex" ? self.codexAccount.localMonitoringEnabled : self.claudeAccount.localMonitoringEnabled }
            self.codexAccount.lastLocalActivity = self.localAgents.filter { $0.provider == "Codex" }.map(\.updatedAt).max()
            self.claudeAccount.lastLocalActivity = self.localAgents.filter { $0.provider == "Claude" }.map(\.updatedAt).max()
            self.agents = AgentActivity.merge(hooks: AgentBridge.read(), local: self.localAgents, now: self.now)
                .filter { $0.updatedAt > (self.dismissedAgents[$0.id] ?? .distantPast) }
        }
    }
    func dismissAgent(_ agent: AgentStatus) {
        dismissedAgents[agent.id] = agent.updatedAt
        try? FileManager.default.removeItem(at: OrbitPaths.agents.appendingPathComponent(AgentBridge.fileName(for: agent.id)))
        agents.removeAll { $0.id == agent.id }
    }
    var activeAgents: [AgentStatus] { AgentActivity.live(agents, now: now) }
    var liveNotchAgent: AgentStatus? {
        AgentActivity.focused(agents, selectedID: preferredNotchAgentID, now: now)
    }
    var finishedNotchAgent: AgentStatus? { AgentActivity.recentCompletion(agents, now: now) }
    var meetingIsNear: Bool { calendar.nextMeeting.map { $0.start.timeIntervalSince(now) <= 900 && $0.end > now } ?? false }
    var availableNotchActivities: [NotchActivityKind] {
        let visible = configuration.notch
        return NotchActivity.available(timer: visible.showTimers && timerState.isActive,
            agent: visible.showAgents && !activeAgents.isEmpty,
            music: visible.showMusic && configuration.mediaEnabled && (media.isPlaying || (holdNotchMusic && media.provider != nil)),
            keepAwake: visible.showKeepAwake && (awake.active || agentAwake.active), download: downloads.live != nil, meeting: meetingIsNear, stopwatch: visible.showTimers && stopwatch.started != nil)
    }
    var selectedNotchActivity: NotchActivityKind? { notchActivitySelection.current(in: availableNotchActivities) }
    var notchCompanion: NotchActivityKind? {
        guard currentNotchActivity == selectedNotchActivity else { return nil }
        return notchActivitySelection.visibleCompanion(available: availableNotchActivities, timerRunning: timerState.end != nil)
    }
    var notchCompanionChoices: [NotchActivityKind] {
        NotchActivitySelection.companions(for: selectedNotchActivity, available: availableNotchActivities, timerRunning: timerState.end != nil)
    }
    var notchActivityPickerHeight: Double {
        guard notchActivityPickerVisible else { return 0 }
        let activities = availableNotchActivities
        let extras = activeAgents.count > 1 || activities.contains { kind in
            !NotchActivitySelection.companions(for: kind, available: activities, timerRunning: timerState.end != nil).isEmpty
        }
        let rows = max(1, (activities.count + 2) / 3)
        return Double(rows * 44 + (rows - 1) * 6 + 48 + (extras ? 36 : 0))
    }
    func selectNotchActivity(_ kind: NotchActivityKind, companion: NotchActivityKind? = nil) {
        notchActivitySelection.select(kind, companion: companion, available: availableNotchActivities, timerRunning: timerState.end != nil)
    }
    func showNotchActivityPicker() {
        guard !availableNotchActivities.isEmpty else { return }
        notchActivityPickerVisible = true; notchActivityPickerPinned = true; focusNotch?()
    }
    func openNotchActivity(_ kind: NotchActivityKind, focus: Bool = true) {
        notchActivityPickerVisible = false
        if kind == .stopwatch { timerMode = 2 }
        if kind == .timer { timerMode = focusCycle.running ? 1 : 0 }
        if kind == .notification, notifications.announcement != nil {
            notchNavigation.showNotification(); notchPinned = false
            notchAlertUntil = notifications.expiresAt; notchExpanded = true
            notifications.holdAnnouncement = true; if focus { focusNotch?() }; return
        }
        selectNotchTool(kind.section, pinned: true); notchExpanded = true
        if focus { focusNotch?() }
    }
    func stepNotchAgent(_ direction: Int) {
        let pool = activeAgents.sorted { $0.id < $1.id }
        guard !pool.isEmpty else { return }
        let index = pool.firstIndex { $0.id == liveNotchAgent?.id } ?? 0
        preferredNotchAgentID = pool[(index + direction + pool.count) % pool.count].id
    }
    var currentNotchActivity: NotchActivityKind? {
        let visible = configuration.notch
        return NotchActivity.choose(waitingAgent: visible.showAgents && liveNotchAgent?.displayedPhase(now: now) == .waiting,
            activeAgent: visible.showAgents && liveNotchAgent != nil, timer: visible.showTimers && timerState.isActive,
            timerFinished: visible.showTimers && timerFinished && NotchActivity.isRecent(timerFinishedAt, now: now, duration: 8),
            music: availableNotchActivities.contains(.music),
            copiedAt: visible.showClipboard && configuration.clipboardEnabled ? clipboardHistory.items.first?.date : nil, now: now,
            agentFinished: visible.showAgents && finishedNotchAgent != nil, notification: visible.showNotifications && notifications.announcement != nil,
            keepAwake: visible.showKeepAwake && (awake.active || agentAwake.active), download: downloads.live != nil, meeting: meetingIsNear, stopwatch: visible.showTimers && stopwatch.started != nil, selection: notchActivitySelection)
    }
    var wheelChoices: [WheelChoice] {
        guard wheelUsesSelection, selection.hasSelection else { return (configuration.wheelProfiles?.first { $0.id == activeWheelProfile }?.slots ?? configuration.slots).map(WheelChoice.tool) }
        return [.copy, .transform(.uppercase), .transform(.lowercase), .transform(.titleCase),
                .transform(.trim), .transform(TextActions.webURL(selection.input) == nil ? .uniqueLines : .cleanLink), .search, .workspace]
    }
    func showConnections() { settingsTab = "Connections"; openSettings?() }
    func resetWheelNavigation() { wheelSection = nil; hoveredSlot = nil; wheelPinned = false; wheelProfileStack = [] }
    func returnToWheel() {
        if wheelSection == nil, !wheelProfileStack.isEmpty { activeWheelProfile = wheelProfileStack.removeLast() }
        wheelSection = nil; hoveredSlot = nil; wheelPinned = false
    }
    func openProfile(_ id: UUID?, nested: Bool = false) {
        if nested { wheelProfileStack.append(activeWheelProfile) } else { wheelProfileStack = [] }
        activeWheelProfile = id; wheelUsesSelection = false; wheelSection = nil; hoveredSlot = nil
        if !wheelVisible { openWheel?(); wheelUsesSelection = false }
    }
    var wheelHoldsOpen: Bool { wheelPinned || (wheelSection == .files || wheelSection == .shelf) || isProcessing }
    func showWheelTool(_ action: OrbitAction) {
        guard let section = action.utilitySection else { return }
        hoveredSlot = nil; wheelSection = section
    }
    func selectNotchTool(_ action: OrbitAction, pinned: Bool = false) {
        guard action.utilitySection != nil else { return }
        notchNavigation.select(action)
        notifications.holdAnnouncement = false
        notchAlertUntil = nil
        if pinned { notchPinned = true }
        UserDefaults.standard.set(notchNavigation.remembered.rawValue, forKey: Self.notchToolPreference)
    }
    func expandNotch(pinned: Bool = false) {
        notchActivityPickerVisible = false
        if configuration.productivity.homeOnOpen == true { notchNavigation.showHome() }
        else { notchNavigation.reopen() }
        notchAlertUntil = nil
        notchPinned = pinned; notchExpanded = true
    }
    func perform(_ choice: WheelChoice) {
        if case .tool(let slot) = choice { perform(slot); return }
        switch choice {
        case .copy: copy(selection.input); hideWheel?()
        case .transform(let action):
            do { let result = try action.apply(to: selection.input); selection.transform = action; copy(result); hideWheel?() }
            catch { selection.feedback = error.localizedDescription; showWheelTool(.textTools) }
        case .search:
            if let url = TextActions.searchURL(selection.input) { NSWorkspace.shared.open(url); hideWheel?() }
            else { selection.feedback = "Search supports selections up to 4 KB."; showWheelTool(.textTools) }
        case .workspace: showWheelTool(.textTools)
        case .tool: break
        }
    }
    func perform(_ slot: WheelSlot) {
        hoveredSlot = nil
        if slot.action == .wheelProfile {
            guard let id = UUID(uuidString: slot.argument), configuration.wheelProfiles?.contains(where: { $0.id == id }) == true else { message("Choose a profile for this action in Wheel settings", positive: false); return }
            guard wheelProfileStack.count < 6 else { return }; openProfile(id, nested: true); return
        }
        if slot.action.utilitySection != nil {
            showWheelTool(slot.action)
            return
        }
        hideWheel?()
        switch slot.action {
        case .settings: openSettings?()
        case .calendar:
            if !NSWorkspace.shared.open(URL(string: "ical://")!) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) }
        case .openURL:
            guard let url = URL(string: slot.argument), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { error = "Enter a valid http, https or mailto link in this action’s settings."; openSettings?(); return }
            NSWorkspace.shared.open(url)
        case .openApp:
            let url = slot.argument.hasPrefix("/") ? URL(fileURLWithPath: slot.argument) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: slot.argument)
            guard let url else { error = "Choose an installed app in the wheel settings."; openSettings?(); return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .shortcut:
            guard !slot.argument.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Enter the name of an Apple Shortcut in wheel settings."; openSettings?(); return }
            var parts = URLComponents(); parts.scheme = "shortcuts"; parts.host = "run-shortcut"; parts.queryItems = [URLQueryItem(name: "name", value: slot.argument)]
            if let url = parts.url { NSWorkspace.shared.open(url) }
        default: break
        }
    }
    func acceptDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        Task {
            var added: [URL] = []
            for provider in files {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        let value = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                        continuation.resume(returning: value)
                    }
                }
                guard let url, url.isFileURL,
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let file = url.standardizedFileURL
                if !selectedFiles.contains(file), !added.contains(file) { added.append(file) }
            }
            if !added.isEmpty { selectedFiles.append(contentsOf: added); error = nil; message("\(added.count) file\(added.count == 1 ? "" : "s") added") }
            else if selectedFiles.isEmpty { error = "Drop files from Finder, or use Choose files. Folders aren’t supported here." }
        }
        return true
    }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.prompt = "Add to Orbit"; panel.message = "Choose files to compress, convert, rename or zip. Originals are preserved."
        if panel.runModal() == .OK { selectedFiles = panel.urls }
    }
    func importFinderSelection() {
        Task {
            do {
                let result = try await ScriptRunner.run("tell application \"Finder\"\nset output to \"\"\nrepeat with itemRef in selection\nset output to output & POSIX path of (itemRef as alias) & ASCII character 31\nend repeat\nreturn output\nend tell")
                let files = result.split(separator: "\u{1f}").map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .newlines)) }
                guard !files.isEmpty else { message("No files selected in Finder"); return }
                selectedFiles = files
            } catch { self.error = "Finder selection needs Automation permission. You can also use Choose files or drag files here." }
        }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; configuration.launchAtLogin = enabled }
        catch { self.error = "Login item could not be changed: \(error.localizedDescription)" }
    }
    func reset() { configuration = OrbitConfiguration(); message("Settings restored") }
}
