import AppKit
import Carbon
import OrbitCore

@MainActor final class TriggerController {
    private weak var store: OrbitStore?
    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hotKey: EventHotKeyRef?
    private var extraHotKeys: [EventHotKeyRef] = []
    private var profileKeys: [UInt32: UUID] = [:]
    private var gestureIsDown = false
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private var pendingMouse: DispatchWorkItem?
    private var mouseOpened = false
    private var pressedEvent: CGEvent?
    private var keyIsDown = false
    private var lastConfiguration: OrbitConfiguration?
    private var lastPermission: Bool?
    private static let syntheticTag: Int64 = 0x4F52424954
    init(store: OrbitStore) {
        self.store = store
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<TriggerController>.fromOpaque(context).takeUnretainedValue()
            let kind = GetEventKind(event)
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            let identifier = id.id
            DispatchQueue.main.async { controller.handleRegisteredKey(identifier, pressed: kind == UInt32(kEventHotKeyPressed)) }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let store = self.store else { return event }
            if event.type == .keyDown, event.keyCode == 53, store.mouseRecording { store.mouseRecording = false; return nil }
            if (store.keyboardRecording || store.recordingProfile != nil || store.recordingGesture), event.type == .keyDown { self.record(event); return nil }
            if store.mouseRecording, event.type == .keyDown, event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) { store.recordingGesture = true; self.record(event); store.mouseRecording = false; return nil }
            if store.mouseRecording, [.rightMouseDown, .otherMouseDown].contains(event.type) { store.configuration.mouseButton = event.buttonNumber; store.mouseRecording = false; store.message("Mouse button \(event.buttonNumber + 1) recorded"); return nil }
            // Registered Carbon hotkeys already deliver inside Orbit. The local path
            // is a fallback only, otherwise one shortcut can open and close twice.
            if self.hotKey == nil, [.keyDown, .keyUp].contains(event.type), store.configuration.keyboardEnabled, UInt32(event.keyCode) == store.configuration.keyCode {
                var modifiers: UInt32 = 0
                if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
                if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
                if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
                if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
                if event.type == .keyDown, modifiers == store.configuration.keyModifiers { self.handleHotKey(pressed: true); return nil }
                if event.type == .keyUp, self.keyIsDown { self.handleHotKey(pressed: false); return nil }
            }
            if event.type == .keyDown, event.keyCode == 53, NSApp.modalWindow == nil {
                if store.wheelVisible {
                    if (store.wheelSection != nil || !store.wheelProfileStack.isEmpty), store.configuration.wheel.escapeReturnsToWheel { store.returnToWheel() }
                    else { store.hideWheel?() }
                    return nil
                }
                store.notchExpanded = false; store.notchActivityPickerVisible = false
            }
            return event
        }
        rebuild()
    }
    func rebuild() {
        guard let store else { return }
        let config = store.configuration
        let allowed = store.inputPermission
        let keyboardChanged = lastConfiguration?.keyboardEnabled != config.keyboardEnabled || lastConfiguration?.keyCode != config.keyCode || lastConfiguration?.keyModifiers != config.keyModifiers || lastConfiguration?.wheelProfiles != config.wheelProfiles || lastConfiguration?.productivity != config.productivity
        let mouseChanged = lastConfiguration?.mouseEnabled != config.mouseEnabled || lastConfiguration?.mouseButton != config.mouseButton || lastConfiguration?.consumeMouseButton != config.consumeMouseButton || lastPermission != allowed || (config.mouseEnabled && allowed && eventTap == nil)
        lastConfiguration = config; lastPermission = allowed
        if keyboardChanged {
            keyIsDown = false; gestureIsDown = false
            extraHotKeys.forEach { UnregisterEventHotKey($0) }; extraHotKeys = []; profileKeys = [:]
            if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
            if config.keyboardEnabled {
                let status = RegisterEventHotKey(config.keyCode, config.keyModifiers, EventHotKeyID(signature: 0x4F524254, id: 1), GetApplicationEventTarget(), 0, &hotKey)
                store.triggerStatus = status == noErr ? "Shortcut is ready" : "Shortcut already in use. Record another combination."
            } else { store.triggerStatus = "Keyboard shortcut is off" }
            var occupied = Set<String>()
            if config.keyboardEnabled { occupied.insert("\(config.keyCode):\(config.keyModifiers)") }
            func register(_ key: UInt32, _ modifiers: UInt32, _ id: UInt32, _ name: String) {
                guard modifiers != 0, occupied.insert("\(key):\(modifiers)").inserted else { store.triggerStatus = "\(name) conflicts with another Orbit shortcut"; return }
                var reference: EventHotKeyRef?
                if RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x4F524254, id: id), GetApplicationEventTarget(), 0, &reference) == noErr, let reference { extraHotKeys.append(reference) }
                else { store.triggerStatus = "\(name) is in use. Record another shortcut." }
            }
            if config.productivity.gestureChordEnabled == true { register(config.productivity.gestureKeyCode ?? 48, config.productivity.gestureModifiers ?? 6144, 2, "Gesture chord") }
            for (index, profile) in (config.wheelProfiles ?? []).enumerated() {
                if let key = profile.keyCode, let modifiers = profile.modifiers { let id = UInt32(index + 100); profileKeys[id] = profile.id; register(key, modifiers, id, profile.name) }
            }

        }
        guard mouseChanged else { return }
        stopMouse()
        guard config.mouseEnabled else { store.mouseTriggerStatus = "Mouse trigger is off"; return }
        guard allowed else { store.mouseTriggerStatus = "Accessibility access is needed"; return }
        let eventTypes: [CGEventType] = [.keyDown, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]
        let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: config.consumeMouseButton ? .defaultTap : .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<TriggerController>.fromOpaque(context).takeUnretainedValue()
            // This tap is attached to the main run loop.
            return MainActor.assumeIsolated { controller.handleMouse(type: type, event: event) }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let eventTap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: eventTap, enable: true)
            store.mouseMonitoring = true; store.mouseTriggerStatus = "Mouse controls are connected"
        } else { store.mouseTriggerStatus = "Mouse monitoring could not start. Check Input Monitoring in System Settings, then reopen Orbit." }
    }
    private func stopMouse() {
        pendingMouse?.cancel(); pendingMouse = nil
        store?.mouseMonitoring = false
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); self.source = nil }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap); self.eventTap = nil }
        mouseOpened = false; pressedEvent = nil
    }
    private func handleMouse(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }; return Unmanaged.passUnretained(event) }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticTag, let store else { return Unmanaged.passUnretained(event) }
        if type == .keyDown {
            if store.mouseRecording, let key = NSEvent(cgEvent: event), key.modifierFlags.intersection([.control, .option, .command]).isEmpty == false { store.recordingGesture = true; record(key); store.mouseRecording = false }
            return Unmanaged.passUnretained(event)
        }
        let down = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type)
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        if store.mouseRecording, down {
            // Leave left click available for Cancel and other setup controls.
            if button == 0 { return Unmanaged.passUnretained(event) }
            store.mouseRecording = false; store.configuration.mouseButton = button; store.message("Mouse button \(button + 1) recorded")
            return Unmanaged.passUnretained(event)
        }
        guard button == store.configuration.mouseButton else { return Unmanaged.passUnretained(event) }
        if down {
            pressedEvent = event.copy(); mouseOpened = false
            let task = DispatchWorkItem { [weak self] in
                guard let self, let store = self.store else { return }
                self.mouseOpened = true
                if store.configuration.mouseBehavior == .toggle, store.wheelVisible { store.hideWheel?() } else { store.openWheel?() }
            }
            pendingMouse?.cancel(); pendingMouse = task; DispatchQueue.main.asyncAfter(deadline: .now() + store.configuration.mouseHoldDelay, execute: task)
        } else {
            pendingMouse?.cancel(); pendingMouse = nil
            if mouseOpened, store.configuration.mouseBehavior == .hold { selectAndDismiss() }
            if !mouseOpened, store.configuration.consumeMouseButton, let downEvent = pressedEvent, let upEvent = event.copy() {
                // A short click remains a normal click; only a deliberate hold invokes Orbit.
                downEvent.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag); upEvent.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
                DispatchQueue.main.async { downEvent.post(tap: .cgSessionEventTap); upEvent.post(tap: .cgSessionEventTap) }
            }
            pressedEvent = nil; mouseOpened = false
        }
        return store.configuration.consumeMouseButton ? nil : Unmanaged.passUnretained(event)
    }
    private func handleRegisteredKey(_ id: UInt32, pressed: Bool) {
        guard let store, !store.keyboardRecording, store.recordingProfile == nil, !store.recordingGesture else { return }
        if id == 1 { handleHotKey(pressed: pressed); return }
        if let profile = profileKeys[id] { if pressed { store.openProfile(profile) }; return }
        guard id == 2 else { return }
        if pressed {
            guard !gestureIsDown else { return }; gestureIsDown = true
            if store.configuration.mouseBehavior == .toggle, store.wheelVisible { store.hideWheel?() } else { store.openWheel?() }
        } else { gestureIsDown = false; if store.configuration.mouseBehavior == .hold { selectAndDismiss() } }
    }
    private func handleHotKey(pressed: Bool) {
        guard let store, !store.keyboardRecording else { return }
        if pressed { guard !keyIsDown else { return }; keyIsDown = true } else { keyIsDown = false }
        if pressed { if store.configuration.keyboardBehavior == .toggle, store.wheelVisible { store.hideWheel?() } else { store.openWheel?() } }
        else if store.configuration.keyboardBehavior == .hold { selectAndDismiss() }
    }
    private func selectAndDismiss() {
        guard let store, store.wheelSection == nil else { return }
        if store.wheelVisible, let index = store.hoveredSlot, store.wheelChoices.indices.contains(index) { store.perform(store.wheelChoices[index]) }
        else { store.hideWheel?() }
    }
    private func record(_ event: NSEvent) {
        guard let store else { return }
        if event.keyCode == 53 { store.keyboardRecording = false; store.recordingProfile = nil; store.recordingGesture = false; return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control) || flags.contains(.option) || flags.contains(.command) else { store.message("Include Control, Option or Command"); return }
        var modifiers: UInt32 = 0; var label = ""
        for (flag, bit, symbol) in [(NSEvent.ModifierFlags.control, UInt32(controlKey), "⌃"), (.option, UInt32(optionKey), "⌥"), (.shift, UInt32(shiftKey), "⇧"), (.command, UInt32(cmdKey), "⌘")] {
            if flags.contains(flag) { modifiers |= bit; label += symbol }
        }
        let special: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        label += special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        if let id = store.recordingProfile {
            var profiles = store.configuration.wheelProfiles ?? []
            if let index = profiles.firstIndex(where: { $0.id == id }) { profiles[index].keyCode = UInt32(event.keyCode); profiles[index].modifiers = modifiers; profiles[index].shortcutLabel = label; store.configuration.wheelProfiles = profiles }
            store.recordingProfile = nil; return
        }
        if store.recordingGesture { store.editProductivity { $0.gestureKeyCode = UInt32(event.keyCode); $0.gestureModifiers = modifiers; $0.gestureLabel = label; $0.gestureChordEnabled = true }; store.recordingGesture = false; store.message("Gesture chord recorded: " + label); return }
        var config = store.configuration; config.keyCode = UInt32(event.keyCode); config.keyModifiers = modifiers; config.keyboardLabel = label
        store.keyboardRecording = false; store.configuration = config
    }
    func shutdown() {
        extraHotKeys.forEach { UnregisterEventHotKey($0) }; extraHotKeys = []
        stopMouse(); if let hotKey { UnregisterEventHotKey(hotKey) }; if let handler { RemoveEventHandler(handler) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
