import AppKit
import Combine
import IOKit.pwr_mgt
import IOKit.ps
import OrbitCore

enum AwakePower {
    static func snapshot() -> (onBattery: Bool, percent: Int)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = data[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = data[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return (data[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue, capacity * 100 / maximum)
        }
        return (false, 100)
    }
}

@MainActor final class AwakeSession: ObservableObject {
    @Published private(set) var until: Date?
    @Published private(set) var active = false
    @Published private(set) var paused = false
    @Published private(set) var automatic = false
    @Published private(set) var error: String?
    @Published private(set) var pointerNeedsPermission = false
    let lid = AwakeLidSession()
    private var options = AwakeOptions()
    private var systemAssertion: IOPMAssertionID?
    private var displayAssertion: IOPMAssertionID?
    private var automation = AwakeAutomation()
    private var matching = false
    private var locked = false
    private var lastEnvironmentCheck = Date.distantPast
    private var nextPointerMove = Date.distantFuture
    private var pointerReturn: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lidSubscription: AnyCancellable?

    init() {
        lidSubscription = lid.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        for (name, isLocked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setLocked(isLocked) }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.setLocked(true) } })
        }
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.setLocked(false) } })
    }

    func configure(_ value: AwakeOptions, launching: Bool = false) {
        var value = value; value.normalize()
        let pointerChanged = value.movePointer != options.movePointer || value.pointerInterval != options.pointerInterval
        options = value
        if pointerChanged { pointerReturn?.cancel(); nextPointerMove = Date().addingTimeInterval(Double(value.pointerInterval)) }
        if active { paused = locked && options.pauseWhenLocked; applyAssertions() }
        if launching && options.startOnLaunch { start(minutes: nil) }
        lastEnvironmentCheck = .distantPast
    }
    func start(minutes: Int?) {
        start(until: minutes.map { Date().addingTimeInterval(Double(min(1440, max(1, $0))) * 60) })
    }
    func start(until end: Date?, automatic: Bool = false) {
        guard end == nil || end! > Date() else { return }
        if let battery = AwakePower.snapshot(), battery.onBattery, battery.percent <= options.batteryCutoff {
            error = "Keep awake is paused below \(options.batteryCutoff)% battery."; return
        }
        until = end; self.automatic = automatic; active = true; paused = locked && options.pauseWhenLocked; error = nil
        nextPointerMove = Date().addingTimeInterval(Double(options.pointerInterval))
        applyAssertions()
        if !paused && systemAssertion == nil { active = false; until = nil; self.automatic = false }
    }
    func stop(userInitiated: Bool = true) {
        if userInitiated { automation.userStopped(matching: matching) }
        active = false; paused = false; automatic = false; until = nil
        releaseAssertions(); pointerReturn?.cancel(); pointerReturn = nil; pointerNeedsPermission = false
        lid.stop()
    }
    func tick(now: Date, permitted: Bool) {
        if active, let until, now >= until { stop() }
        if now.timeIntervalSince(lastEnvironmentCheck) >= 2 {
            lastEnvironmentCheck = now
            let battery = AwakePower.snapshot()
            let external = NSScreen.screens.contains { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                return CGDisplayIsBuiltin(number.uint32Value) == 0
            }
            matching = options.matches(power: battery?.onBattery == false, externalDisplay: external,
                running: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)))
            let batteryOK = battery.map { !$0.onBattery || $0.percent > options.batteryCutoff } ?? true
            if active && !batteryOK { stop(); error = "Session ended at the \(options.batteryCutoff)% battery limit." }
            if active && automatic && !matching { stop(userInitiated: false) }
            if automation.shouldStart(matching: matching, sessionActive: active, allowed: batteryOK && !locked) {
                start(until: nil, automatic: true)
            }
        }
        lid.tick(active: active && !paused, until: until, batteryCutoff: options.batteryCutoff)
        let needs = active && !paused && options.movePointer && !permitted
        if pointerNeedsPermission != needs { pointerNeedsPermission = needs }
        guard active, !paused, options.movePointer, permitted, now >= nextPointerMove else { return }
        nextPointerMove = now.addingTimeInterval(Double(options.pointerInterval))
        nudgePointer()
    }
    private func setLocked(_ value: Bool) {
        locked = value
        if value { pointerReturn?.cancel(); lid.stop() }
        guard active else { return }
        paused = value && options.pauseWhenLocked; applyAssertions()
        nextPointerMove = Date().addingTimeInterval(Double(options.pointerInterval))
    }
    private func applyAssertions() {
        guard active && !paused else { releaseAssertions(); return }
        if systemAssertion == nil { systemAssertion = assertion(kIOPMAssertionTypePreventUserIdleSystemSleep, reason: "Orbit keep awake") }
        if options.allowDisplaySleep {
            if let displayAssertion { IOPMAssertionRelease(displayAssertion); self.displayAssertion = nil }
        } else if displayAssertion == nil {
            displayAssertion = assertion(kIOPMAssertionTypePreventUserIdleDisplaySleep, reason: "Orbit keep display awake")
        }
    }
    private func assertion(_ type: String, reason: String) -> IOPMAssertionID? {
        var id: IOPMAssertionID = 0
        guard IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id) == kIOReturnSuccess else {
            error = "macOS couldn’t apply the keep-awake setting."; return nil
        }
        return id
    }
    private func releaseAssertions() {
        for id in [displayAssertion, systemAssertion].compactMap({ $0 }) { IOPMAssertionRelease(id) }
        systemAssertion = nil; displayAssertion = nil
    }
    private func nudgePointer() {
        guard !locked, AXIsProcessTrusted(),
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              !CGEventSource.buttonState(.combinedSessionState, button: .right),
              !CGEventSource.buttonState(.combinedSessionState, button: .center),
              CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved) > 3,
              let point = CGEvent(source: nil)?.location else { return }
        var count: UInt32 = 0
        var display = CGDirectDisplayID()
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return }
        let bounds = CGDisplayBounds(display).insetBy(dx: 3, dy: 3)
        guard bounds.contains(point) else { return }
        let moved = CGPoint(x: point.x + (point.x + 1 < bounds.maxX ? 1 : -1), y: point.y)
        postMove(moved)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.active, !self.paused, !self.locked, self.options.movePointer,
                  AXIsProcessTrusted(), let current = CGEvent(source: nil)?.location,
                  abs(current.x - moved.x) < 0.1, abs(current.y - moved.y) < 0.1,
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  !CGEventSource.buttonState(.combinedSessionState, button: .right) else { return }
            self.postMove(point)
        }
        pointerReturn?.cancel(); pointerReturn = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    private func postMove(_ point: CGPoint) {
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    func shutdown() {
        stop(userInitiated: false)
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll(); workspaceObservers.removeAll()
    }
}
