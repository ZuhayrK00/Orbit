import AppKit
import SwiftUI
import Combine
import OrbitCore

class OrbitPanel: NSPanel {
    var reachesScreenEdge = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        reachesScreenEdge ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}
/// Keep nonactivating notch glass visually active without taking keyboard focus.
/// AppKit's glass currently consults this private appearance query; scope the
/// compatibility override to this panel, never to application windows globally.
final class NotchPanel: OrbitPanel {
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}
@MainActor final class WheelController {
    private let store: OrbitStore
    private var panel: OrbitPanel?
    private var surface: WheelSurface?
    private var tracking: Timer?
    private var globalClick: Any?
    private var localClick: Any?
    private var subscriptions: Set<AnyCancellable> = []
    init(store: OrbitStore) {
        self.store = store
        store.$wheelSection.removeDuplicates().sink { [weak self] section in
            DispatchQueue.main.async {
                guard let self, self.store.wheelSection == section else { return }
                self.surface?.present(section)
            }
        }.store(in: &subscriptions)
    }
    func updateAppearance() { surface?.updateAppearance() }
    func show() {
        dismiss(animated: false)
        store.resetWheelNavigation()
        store.wheelUsesSelection = (store.configuration.contextualTextWheel ?? true) && store.selection.capture()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let metrics = WheelLayout(screen: screen.visibleFrame, pointer: mouse, diameter: store.configuration.wheelDiameter,
                                  toolWidth: store.configuration.wheel.toolWidth, placement: store.configuration.wheel.placement)
        let panel = OrbitPanel(contentRect: metrics.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Orbit wheel"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
        let surface = WheelSurface(store: store, metrics: metrics)
        surface.onMeasured = { [weak self, weak surface] section, height in
            guard let self, self.surface === surface, self.store.wheelSection == section else { return }
            surface?.fit(section: section, height: height)
        }
        panel.contentView = surface
        self.panel = panel; self.surface = surface; store.wheelVisible = true; store.hoveredSlot = nil
        panel.makeKeyAndOrderFront(nil); surface.open()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.track() } }
        RunLoop.main.add(timer, forMode: .common); tracking = timer
        globalClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.dismissOutside() }
        }
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.dismissOutside(); return event
        }
        track()
    }
    private func pointInSurface() -> CGPoint {
        guard let panel else { return .zero }
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
    }
    private func dismissOutside() {
        guard let surface, !surface.contains(pointInSurface()), store.permissions.requesting.isEmpty,
              WheelDismissal.outsideClickCloses(section: store.wheelSection, pinned: store.wheelPinned,
                processing: store.isProcessing, enabled: store.configuration.wheel.dismissOnOutsideClick, modal: NSApp.modalWindow != nil) else { return }
        dismiss()
    }
    private func track() {
        guard let panel, let surface else { return }
        let point = pointInSurface()
        // Transparent parts of the reserved canvas pass through to Finder and
        // other apps. Dragging into File Tools re-enables the drop destination.
        panel.ignoresMouseEvents = !surface.contains(point)
        guard store.wheelSection == nil else { return }
        let diameter = surface.metrics.diameter
        let selected = WheelGeometry.index(x: point.x - surface.bounds.midX + diameter / 2,
            y: point.y - surface.bounds.midY + diameter / 2, diameter: diameter, count: store.wheelChoices.count)
        if store.hoveredSlot != selected { store.hoveredSlot = selected }
    }
    func dismiss(animated: Bool = true) {
        tracking?.invalidate(); tracking = nil
        if let globalClick { NSEvent.removeMonitor(globalClick); self.globalClick = nil }
        if let localClick { NSEvent.removeMonitor(localClick); self.localClick = nil }
        let previous = panel, oldSurface = surface; panel = nil; surface = nil
        store.wheelVisible = false; store.hoveredSlot = nil
        guard let previous else { return }
        let finish = { [weak self, weak oldSurface] in
            oldSurface?.stop(); previous.close()
            if self?.panel == nil { self?.store.resetWheelNavigation() }
        }
        if animated { oldSurface?.close(animated: true, completion: finish) }
        else { oldSurface?.stop(); previous.close() }
    }
}

@MainActor final class NotchController {
    private let store: OrbitStore
    private var panel: OrbitPanel?
    private var screen: NSScreen?
    private var surface: NotchSurface?
    private var expandedSize = CGSize.zero
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var outsideClick: Any?
    private var localClick: Any?
    private var motionObserver: NSObjectProtocol?
    private var timer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var hoverStart: Date?
    private var leaveStart: Date?
    private var previewUntil: Date?
    private var subscriptions: Set<AnyCancellable> = []
    private var lastSignature = ""
    private var lastNotchOptions: NotchOptions?
    private var compactWidth: Double = 220
    private var compactHeight: Double = 34
    private var cameraSize = CGSize.zero
    private var physicalCameraSize = CGSize.zero
    private var barMeasurements = NotchBarMeasurements()
    private let menuSpaceReader = NotchMenuSpaceReader()
    private var menuSpaceTask: Task<Void, Never>?
    private var menuPID: pid_t = 0
    private var lastMenuRead = Date.distantPast
    private var availableCompactWing = 0.0
    init(store: OrbitStore) {
        self.store = store
        store.$notchExpanded.removeDuplicates().sink { [weak self] expanded in DispatchQueue.main.async { guard let self, self.store.notchExpanded == expanded else { return }; self.layout(expanded: expanded) } }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.lastSignature = ""; self?.rebuild() } }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.lastSignature = ""; self?.rebuild() } }
        let motionEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: motionEvents) { [weak self] _ in self?.updateMousePassthrough() }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: motionEvents) { [weak self] event in self?.updateMousePassthrough(); return event }
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.dismissOutsideClick() }
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in self?.dismissOutsideClick(event: event); return event }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in Task { @MainActor in self?.trackHover() } }
        rebuild()
    }
    func rebuild() {
        let config = store.configuration
        surface?.updateAppearance(config)
        let signature = "\(config.notchEnabled)-\(config.notchOnlyOnBuiltIn)-\(config.notchWidth)-\(config.notchHeight)-\(store.reduceMotion)"
        guard signature != lastSignature || lastNotchOptions != config.notch else { return }; lastSignature = signature; lastNotchOptions = config.notch
        surface?.stop(); surface = nil; panel?.close(); panel = nil
        menuSpaceTask?.cancel(); menuSpaceTask = nil
        availableCompactWing = 0; lastMenuRead = .distantPast
        guard config.notchEnabled else { store.notchExpanded = false; return }
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
        screen = config.notchOnlyOnBuiltIn ? (notched ?? NSScreen.main) : NSScreen.main
        guard let screen else { return }
        physicalCameraSize = CGSize(width: screen.auxiliaryTopLeftArea.flatMap { left in screen.auxiliaryTopRightArea.map { $0.minX - left.maxX } } ?? 0, height: screen.safeAreaInsets.top)
        let barHeight = barMeasurements.height(displayID: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
            size: screen.frame.size, scale: screen.backingScaleFactor, visibleGap: screen.frame.maxY - screen.visibleFrame.maxY,
            fallback: NSStatusBar.system.thickness)
        cameraSize = NotchLayout.cameraSize(reported: physicalCameraSize, menuBarHeight: barHeight,
            screenWidth: screen.frame.width, outlined: config.notch.outlineEnabled)
        let compact = desiredCompactSize
        compactWidth = compact.width; compactHeight = compact.height
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.reachesScreenEdge = true; panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .statusBar; panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
        let budget = NotchLayout.contentBudget(screenHeight: availableBodyHeight, cameraHeight: physicalCameraSize.height)
        expandedSize = CGSize(width: NotchLayout.expandedWidth(preferred: config.notchWidth, cameraWidth: cameraSize.width,
            screenWidth: screen.frame.width, shortcutAllowance: 144), height: compactHeight)
        let surface = NotchSurface(store: store, compactSize: CGSize(width: compactWidth, height: compactHeight), expandedSize: expandedSize, cameraSize: cameraSize, physicalCameraSize: physicalCameraSize, stripWidth: desiredStripSize.width, toolBudget: budget)
        surface.onContentHeight = { [weak self, weak surface] section, height in
            // Defer window changes until SwiftUI has finished its layout pass.
            DispatchQueue.main.async {
                guard let self, self.surface === surface, section == self.store.notchSection else { return }
                self.fitContent(height)
            }
        }
        panel.contentView = surface; panel.acceptsMouseMovedEvents = true
        self.surface = surface; self.panel = panel
        layout(expanded: store.notchExpanded); panel.orderFrontRegardless()
    }
    func preview() {
        guard store.configuration.notchEnabled else { return }
        previewUntil = nil
        store.expandNotch(pinned: true)
        panel?.makeKeyAndOrderFront(nil)
    }
    func focus() { panel?.makeKeyAndOrderFront(nil) }
    private func fitContent(_ measuredHeight: Double) {
        guard let panel, let surface, screen != nil else { return }
        guard measuredHeight.isFinite, measuredHeight > 0 else { return }
        let height = NotchLayout.fittedHeight(measured: measuredHeight, screenHeight: availableBodyHeight)
        let next = CGSize(width: expandedSize.width, height: height)
        guard next != expandedSize else { return }
        let expanded = store.notchExpanded
        let reserve = surface.reservation(for: next, expanded: expanded)
        expandedSize = next
        if expanded { panel.setFrame(frame(for: reserve), display: false) }
        surface.resizeExpanded(to: next, expanded: expanded, animated: expanded && panel.isVisible && !store.reduceMotion) { [weak self, weak panel, weak surface] in
            guard let self, let panel, let surface, self.surface === surface, !surface.isAnimating else { return }
            panel.setFrame(self.frame(for: self.store.notchExpanded ? surface.canvasSize : CGSize(width: self.compactWidth, height: self.compactHeight)), display: false)
            surface.needsLayout = true; surface.layoutSubtreeIfNeeded(); self.updateMousePassthrough()
        }
    }
    private var availableHeight: Double {
        guard let screen else { return 800 }
        return screen.frame.maxY - max(screen.frame.minY, screen.visibleFrame.minY)
    }
    private var availableBodyHeight: Double {
        availableHeight - NotchShortcutLayout.bottomAllowance(count: store.configuration.notch.visibleActions(at: .bottom).count)
    }
    private func frame(for size: CGSize) -> CGRect {
        guard let screen else { return .zero }
        return CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }
    private var compactReadout: NotchHeaderView {
        var view = NotchHeaderView(store: store, cameraWidth: cameraSize.width, stripHeight: cameraSize.height)
        view.physicalCamera = physicalCameraSize.width > 0
        return view
    }
    private var activityRoom: Double {
        store.configuration.notch.allowActivityOverMenus
            ? max(0, ((screen?.frame.width ?? 800) - cameraSize.width) / 2 - 12) : availableCompactWing
    }
    private var desiredStripSize: CGSize {
        compactReadout.stripSize(for: store.currentNotchActivity, companion: store.notchCompanion,
                                 availableWing: activityRoom, screenWidth: Double(screen?.frame.width ?? 800))
    }
    private var desiredCompactSize: CGSize {
        var size = desiredStripSize
        if store.notchActivityPickerVisible {
            let readout = compactReadout, activities = store.availableNotchActivities
            let screenWidth = screen?.frame.width ?? 800
            let strips = activities.flatMap { kind -> [Double] in
                let companions: [NotchActivityKind?] = [nil] + NotchActivitySelection.companions(for: kind,
                    available: activities, timerRunning: store.timerState.end != nil).map { Optional($0) }
                return companions.map { readout.stripSize(for: kind, companion: $0,
                    availableWing: activityRoom, screenWidth: screenWidth).width }
            }
            let label = activities.map { ($0.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width }.max() ?? 0
            size.width = NotchLayout.pickerWidth(stripWidths: strips, count: activities.count, labelWidth: label, screenWidth: screenWidth)
            size.height += store.notchActivityPickerHeight
        }
        return size
    }
    private func refreshMenuSpace() {
        guard !store.configuration.notch.allowActivityOverMenus else { return }
        guard cameraSize.width > 0, let screen, let panel, let front = NSWorkspace.shared.frontmostApplication else { return }
        let pid = front.processIdentifier
        if menuPID != pid {
            menuPID = pid; availableCompactWing = 0; lastMenuRead = .distantPast
            menuSpaceTask?.cancel(); menuSpaceTask = nil
        }
        guard menuSpaceTask == nil, Date().timeIntervalSince(lastMenuRead) >= 1.5 else { return }
        lastMenuRead = Date()
        let frame = screen.frame, top = NSScreen.screens.first?.frame.maxY ?? frame.maxY, width = cameraSize.width
        menuSpaceTask = Task { [weak self, weak panel] in
            guard let self else { return }
            let room = await self.menuSpaceReader.availableWing(pid: pid, screen: frame, cameraWidth: width,
                primaryTop: top, excludingPID: ProcessInfo.processInfo.processIdentifier)
            guard !Task.isCancelled, self.menuPID == pid, self.panel === panel, self.screen?.frame == frame else { return }
            self.menuSpaceTask = nil; self.availableCompactWing = room ?? 0
            self.fitCompactActivity()
        }
    }
    private func fitCompactActivity() {
        guard let panel, let surface, !store.notchExpanded else { return }
        let next = desiredCompactSize
        surface.updateStripWidth(desiredStripSize.width)
        guard next != CGSize(width: compactWidth, height: compactHeight) else { return }
        // Reserve both endpoints while the compositor morphs; do not resize per frame.
        let reserve = surface.reservation(for: next, expanded: false, steadyWidth: next.height == compactHeight)
        compactWidth = next.width; compactHeight = next.height
        panel.setFrame(frame(for: reserve), display: false)
        surface.needsLayout = true; surface.layoutSubtreeIfNeeded()
        surface.resizeCompact(to: next, pickerVisible: store.notchActivityPickerVisible, animated: !store.reduceMotion) { [weak self, weak panel, weak surface] in
            guard let self, let panel, let surface, self.surface === surface, !self.store.notchExpanded else { return }
            panel.setFrame(self.frame(for: CGSize(width: self.compactWidth, height: self.compactHeight)), display: false)
            surface.needsLayout = true; surface.layoutSubtreeIfNeeded(); self.updateMousePassthrough()
        }
    }
    private func layout(expanded: Bool) {
        guard let panel, let surface else { return }
        surface.setNotificationPresentation(store.notchShowsNotification)
        if !expanded {
            previewUntil = nil; store.notchPinned = false
            // Resolve the destination now: a timer or agent may have changed
            // while the expanded page was open. Never close to stale geometry.
            let compact = desiredCompactSize
            compactWidth = compact.width; compactHeight = compact.height
            surface.prepareCompact(to: compact, stripWidth: desiredStripSize.width, pickerVisible: store.notchActivityPickerVisible)
        }
        let animate = panel.isVisible && !store.reduceMotion
        // Reserve the spring's overshoot as well as both endpoints. The shape
        // stays centred at the screen edge throughout, including reversals.
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let target = expanded ? expandedSize : CGSize(width: compactWidth, height: compactHeight)
        panel.setFrame(frame(for: surface.reservation(for: target, expanded: expanded)), display: false)
        surface.needsLayout = true; surface.layoutSubtreeIfNeeded()
        surface.transition(expanded: expanded, animated: animate) { [weak self, weak panel, weak surface] in
            guard let self, let panel, let surface, self.surface === surface else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            panel.setFrame(self.frame(for: expanded ? surface.canvasSize : CGSize(width: self.compactWidth, height: self.compactHeight)), display: false)
            surface.needsLayout = true; surface.layoutSubtreeIfNeeded()
            CATransaction.commit()
            self.updateMousePassthrough()
        }
        CATransaction.commit()
        hoverStart = nil; leaveStart = nil
        updateMousePassthrough()
    }
    private func updateMousePassthrough() {
        guard let panel, let surface else { return }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        // A settled panel must accept the first click, even before a mouse-move callback.
        panel.ignoresMouseEvents = surface.isAnimating && !surface.containsInteraction(local)
    }
    private func trackHover() {
        guard let panel, panel.isVisible, let screen, let surface else { return }
        if surface.setNotificationPresentation(store.notchShowsNotification) { layout(expanded: store.notchExpanded) }
        if store.notchActivityPickerVisible, store.availableNotchActivities.isEmpty { store.notchActivityPickerVisible = false }
        refreshMenuSpace()
        fitCompactActivity()
        updateMousePassthrough()
        // During collapse, hovering the still-visible surface reverses smoothly.
        // Once closed, this is exactly the compact island width, not the canvas.
        var activeSize = store.notchExpanded ? surface.canvasSize : surface.visibleSize
        if !store.notchExpanded, !store.notchActivityPickerVisible, !surface.isAnimating, cameraSize.width > 0, store.notifications.announcement == nil { activeSize.width = cameraSize.width }
        let inside = NotchActivation.contains(point: NSEvent.mouseLocation, screen: screen.frame, panel: frame(for: activeSize))
        store.notifications.holdAnnouncement = inside && store.notchExpanded && store.notchShowsNotification
        if inside {
            leaveStart = nil
            if !store.notchExpanded, store.configuration.notchHoverEnabled {
                if hoverStart == nil { hoverStart = Date() }
                if Date().timeIntervalSince(hoverStart!) >= store.configuration.hoverDelay {
                    if store.notifications.announcement != nil { store.openNotchActivity(.notification, focus: false) }
                    else if store.availableNotchActivities.count > 1, !store.notchActivityPickerVisible {
                        store.notchActivityPickerVisible = true
                        fitCompactActivity()
                    }
                    else if !store.notchActivityPickerVisible { store.expandNotch() }
                }
            }
        } else {
            hoverStart = nil
            if store.notchActivityPickerVisible, !store.notchActivityPickerPinned {
                if leaveStart == nil { leaveStart = Date() }
                if Date().timeIntervalSince(leaveStart!) >= store.configuration.collapseDelay {
                    store.notchActivityPickerVisible = false; store.holdNotchMusic = false
                    fitCompactActivity()
                }
            } else if !store.notchActivityPickerVisible, store.holdNotchMusic { store.holdNotchMusic = false }
            let editingText = panel.isKeyWindow && panel.firstResponder is NSTextView
            let previewing = (previewUntil.map { Date() < $0 } ?? false) || (store.notchAlertUntil.map { Date() < $0 } ?? false)
            if store.notchExpanded, !store.notchPinned, !editingText, !previewing, NSApp.modalWindow == nil, store.permissions.requesting.isEmpty {
                if leaveStart == nil { leaveStart = Date() }
                if Date().timeIntervalSince(leaveStart!) >= store.configuration.collapseDelay { store.notchExpanded = false }
            }
        }
    }
    private func dismissOutsideClick(event: NSEvent? = nil) {
        guard let panel, store.notchExpanded || store.notchActivityPickerVisible, NSApp.modalWindow == nil, store.permissions.requesting.isEmpty else { return }
        if event?.window === panel { return }
        if !panel.frame.contains(NSEvent.mouseLocation) { store.notchExpanded = false; store.notchPinned = false; store.notchActivityPickerVisible = false }
    }
    func shutdown() {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        if let localClick { NSEvent.removeMonitor(localClick) }
        timer?.invalidate(); menuSpaceTask?.cancel(); surface?.stop(); panel?.close()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }
}
