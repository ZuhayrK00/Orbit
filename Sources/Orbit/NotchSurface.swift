import AppKit
import SwiftUI
import QuartzCore
import OrbitCore

/// The window reserves the spring's envelope once. Only compositor layers move;
/// hosted controls keep their final layout throughout an opening or resize.
@MainActor final class NotchSurface: NSView {
    override var isFlipped: Bool { true }
    private weak var store: OrbitStore?
    private var compactSize: CGSize
    private let railTop: Double
    private let options: NotchOptions
    private var expandedSize: CGSize
    private let bodyView = NotchBodyView()
    private let leftRail: NSHostingView<NotchRailView>
    private let rightRail: NSHostingView<NotchRailView>
    private let bottomRail: NSHostingView<NotchRailView>
    private let header: NSHostingView<NotchCompactView>
    private let picker: NSHostingView<NotchActivityPickerView>
    private let content: NSHostingView<NotchContentView>
    private let contentWrapper = NotchBodyView()
    private let headerWrapper = NotchBodyView()
    private let pickerWrapper = NotchBodyView()
    private var pickerSize: CGSize
    private let railWrappers = [NotchBodyView(), NotchBodyView(), NotchBodyView()]
    private let silhouette = CAShapeLayer()
    private let glass: OrbitGlassSurface
    private let backdropOverlay = NotchBodyView()
    private let blackVeil = CALayer()
    private let cameraFade = CAGradientLayer()
    private let cameraCap = CALayer()
    private let camera: CGSize
    private let edge = CAShapeLayer()
    private var motion: NotchMotion?
    private var startedAt: CFTimeInterval = 0
    private var settledSize: CGSize
    private enum Presentation { case compact, picker, expanded }
    private var presentation: Presentation = .compact
    private var compactPresentation: Presentation = .compact
    private var expanded: Bool { presentation == .expanded }
    private var notificationPresentation = false
    private var appearanceEndsAt: CFTimeInterval = 0
    private var completion: DispatchWorkItem?
    private var generation = 0
    private var lastMeasurement: (OrbitAction, Double)?
    var onContentHeight: ((OrbitAction, Double) -> Void)? {
        didSet { if let (section, height) = lastMeasurement { onContentHeight?(section, height) } }
    }

    init(store: OrbitStore, compactSize: CGSize, expandedSize: CGSize, cameraSize: CGSize, physicalCameraSize: CGSize, stripWidth: Double, toolBudget: Double) {
        self.store = store
        self.compactSize = compactSize; self.expandedSize = expandedSize; settledSize = compactSize
        pickerSize = CGSize(width: compactSize.width, height: store.notchActivityPickerHeight)
        camera = cameraSize
        glass = OrbitGlassSurface(transparency: store.configuration.effectiveGlassTransparency, tint: store.configuration.effectiveGlassColor)
        railTop = max(10, cameraSize.height + 6)
        options = store.configuration.notch
        notificationPresentation = store.notchShowsNotification
        header = NSHostingView(rootView: NotchCompactView(store: store, cameraSize: cameraSize, physicalCamera: physicalCameraSize.width > 0, stripWidth: stripWidth))
        picker = NSHostingView(rootView: NotchActivityPickerView(store: store))
        leftRail = NSHostingView(rootView: NotchRailView(store: store, actions: options.visibleActions(at: .left)))
        rightRail = NSHostingView(rootView: NotchRailView(store: store, actions: options.visibleActions(at: .right)))
        bottomRail = NSHostingView(rootView: NotchRailView(store: store, actions: options.visibleActions(at: .bottom), horizontal: true))
        let measurement = NotchMeasurementRelay()
        content = NSHostingView(rootView: NotchContentView(store: store, width: expandedSize.width, cameraSize: physicalCameraSize, toolBudget: toolBudget) { section, height in measurement.report?(section, height) })
        super.init(frame: CGRect(origin: .zero, size: NotchShortcutLayout(bodySize: expandedSize, railTop: railTop, options: options).canvas))
        measurement.report = { [weak self] section, height in
            self?.lastMeasurement = (section, height)
            self?.onContentHeight?(section, height)
        }
        registerForDraggedTypes([.fileURL, .URL])
        content.sizingOptions = []; header.sizingOptions = []; picker.sizingOptions = []
        autoresizesSubviews = false; wantsLayer = true
        bodyView.wantsLayer = true; bodyView.layer?.mask = silhouette
        bodyView.addSubview(glass)
        backdropOverlay.wantsLayer = true; bodyView.addSubview(backdropOverlay)
        blackVeil.backgroundColor = NSColor.black.cgColor
        cameraFade.colors = [NSColor.black.cgColor, NSColor.black.withAlphaComponent(0).cgColor]
        cameraFade.locations = [0.15, 1]
        cameraCap.backgroundColor = NSColor.black.cgColor
        backdropOverlay.layer?.addSublayer(cameraFade); backdropOverlay.layer?.addSublayer(cameraCap); backdropOverlay.layer?.addSublayer(blackVeil)
        addSubview(bodyView)
        for (wrapper, rail) in zip(railWrappers, rails) {
            wrapper.wantsLayer = true; wrapper.addSubview(rail); addSubview(wrapper); wrapper.isHidden = true
        }
        for (wrapper, host) in [(contentWrapper, content as NSView), (pickerWrapper, picker as NSView), (headerWrapper, header as NSView)] {
            wrapper.wantsLayer = true; wrapper.addSubview(host); bodyView.addSubview(wrapper)
        }
        // A fixed top-centre pivot avoids a sliding baseline as the content grows.
        contentWrapper.layer?.anchorPoint = CGPoint(x: 0.5, y: 0)
        pickerWrapper.layer?.anchorPoint = CGPoint(x: 0.5, y: 0)
        edge.fillColor = NSColor.clear.cgColor
        edge.strokeColor = options.outlineEnabled ? options.outlineColor.appKit.cgColor : NSColor.clear.cgColor
        edge.lineWidth = options.outlineWidth * 2; bodyView.layer?.addSublayer(edge)
        contentWrapper.isHidden = true; pickerWrapper.isHidden = true
        setAppearance(.compact)
        layoutSubtreeIfNeeded()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let store, sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else { return [] }
        store.selectNotchTool(.shelf, pinned: true); store.notchExpanded = true
        return .copy
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else { return false }
        store?.shelf.addURLs(urls); return true
    }
    func updateAppearance(_ configuration: OrbitConfiguration) {
        glass.tint = configuration.effectiveGlassColor
        glass.transparency = configuration.effectiveGlassTransparency
    }
    @discardableResult func setNotificationPresentation(_ active: Bool) -> Bool {
        guard notificationPresentation != active else { return false }
        notificationPresentation = active; setRailsVisible(expanded); return true
    }

    private var current: NotchMotion.Sample? { motion?.sample(at: CACurrentMediaTime() - startedAt) }
    private var presentedSize: CGSize { current?.size ?? settledSize }
    private var rails: [NSHostingView<NotchRailView>] { [leftRail, rightRail, bottomRail] }
    private var geometry: NotchShortcutLayout { NotchShortcutLayout(bodySize: expandedSize, railTop: railTop, options: options) }
    var canvasSize: CGSize { notificationPresentation ? expandedSize : geometry.canvas }
    var isAnimating: Bool { completion != nil }
    var visibleSize: CGSize {
        let size = presentedSize
        guard railWrappers.contains(where: { !$0.isHidden && ($0.layer?.presentation()?.opacity ?? $0.layer?.opacity ?? 0) > 0.1 }) else { return size }
        let layout = NotchShortcutLayout(bodySize: size, railTop: railTop, options: options)
        return layout.canvas
    }

    /// Include both endpoints and any elastic excursion before changing the window.
    func reservation(for size: CGSize, expanded: Bool, steadyWidth: Bool = false) -> CGSize {
        let next = NotchMotion(from: presentedSize, velocity: current?.velocity ?? .zero, to: size, steadyWidth: steadyWidth)
        let body = next.envelope
        let result = self.expanded || expanded || isAnimating
            ? NotchShortcutLayout(bodySize: body, railTop: railTop, options: options).canvas : body
        // Equal whole-point margins keep the physical camera centred when settling.
        return CGSize(width: size.width + ceil(max(0, result.width - size.width) / 2) * 2, height: ceil(result.height))
    }

    private func setRailsVisible(_ visible: Bool) {
        for (wrapper, position) in zip(railWrappers, [NotchShortcutPosition.left, .right, .bottom]) {
            wrapper.isHidden = !visible || notificationPresentation || options.visibleActions(at: position).isEmpty
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bodyView.frame = bounds
        glass.frame = bounds
        backdropOverlay.frame = bounds
        blackVeil.frame = bounds
        cameraFade.frame = CGRect(x: 0, y: 0, width: bounds.width, height: camera.height + 64)
        cameraCap.frame = CGRect(x: (bounds.width - camera.width) / 2, y: 0, width: camera.width, height: camera.height)
        let x = (bounds.width - expandedSize.width) / 2
        let layout = geometry, offset = (bounds.width - layout.canvas.width) / 2
        for (wrapper, rect) in zip(railWrappers, [layout.left, layout.right, layout.bottom]) {
            wrapper.frame = rect.offsetBy(dx: offset, dy: 0)
        }
        for (wrapper, rail) in zip(railWrappers, rails) { rail.frame = wrapper.bounds }
        headerWrapper.frame = CGRect(x: (bounds.width - compactSize.width) / 2, y: 0, width: compactSize.width, height: camera.height)
        header.frame = headerWrapper.bounds
        // Keep the outgoing chooser at its laid-out size until its fade ends.
        // Shrinking this host with the closing shell would reflow/disappear it.
        pickerWrapper.frame = CGRect(x: (bounds.width - pickerSize.width) / 2, y: camera.height, width: pickerSize.width, height: pickerSize.height)
        picker.frame = pickerWrapper.bounds
        contentWrapper.frame = CGRect(x: x, y: 0, width: expandedSize.width, height: expandedSize.height)
        content.frame = contentWrapper.bounds
        silhouette.frame = bounds; edge.frame = bounds
        applyGeometry(motion?.target ?? settledSize)
        // AppKit can relayout when the reserved window changes. Rebase the paths
        // into that canvas while keeping the original animation clock running.
        if let motion { installGeometry(motion) }
        CATransaction.commit()
    }

    func transition(expanded: Bool, animated: Bool, completion onComplete: @escaping () -> Void) {
        move(to: expanded ? expandedSize : compactSize, presentation: expanded ? .expanded : compactPresentation, animated: animated, completion: onComplete)
    }

    func updateStripWidth(_ width: Double) {
        guard header.rootView.stripWidth != width else { return }
        header.rootView.stripWidth = width
    }

    /// Set the next closing endpoint without starting a second animation.
    func prepareCompact(to size: CGSize, stripWidth: Double, pickerVisible: Bool) {
        compactSize = size
        compactPresentation = pickerVisible ? .picker : .compact
        if pickerVisible { pickerSize = CGSize(width: size.width, height: max(0, size.height - camera.height)) }
        updateStripWidth(stripWidth)
    }

    func resizeCompact(to size: CGSize, pickerVisible: Bool, animated: Bool, completion onComplete: @escaping () -> Void) {
        let steady = size.height == compactSize.height
        prepareCompact(to: size, stripWidth: header.rootView.stripWidth, pickerVisible: pickerVisible)
        move(to: size, presentation: compactPresentation, animated: animated, steadyWidth: steady, completion: onComplete)
    }

    func resizeExpanded(to size: CGSize, expanded: Bool, animated: Bool, completion onComplete: @escaping () -> Void) {
        expandedSize = size
        if expanded { move(to: size, presentation: .expanded, animated: animated, completion: onComplete) }
        else {
            // Measurement while closed prepares the next opening. It must not
            // cancel a collapse that is still carrying the old page out.
            needsLayout = true; layoutSubtreeIfNeeded()
            onComplete()
        }
    }

    private func move(to size: CGSize, presentation: Presentation, animated: Bool, steadyWidth: Bool = false, completion onComplete: @escaping () -> Void) {
        completion?.cancel(); completion = nil; generation += 1
        let token = generation
        let next = NotchMotion(from: presentedSize, velocity: current?.velocity ?? .zero, to: size, steadyWidth: steadyWidth)
        let changesVisibility = self.presentation != presentation
        self.presentation = presentation
        contentWrapper.acceptsInteraction = presentation == .expanded
        headerWrapper.acceptsInteraction = presentation != .expanded
        pickerWrapper.acceptsInteraction = presentation == .picker
        motion = nil; settledSize = size
        CATransaction.begin(); CATransaction.setDisableActions(true)
        removeGeometry()
        func visible(_ wrapper: NSView) -> Bool { (wrapper.layer?.presentation()?.opacity ?? wrapper.layer?.opacity ?? 0) > 0.01 }
        contentWrapper.isHidden = presentation != .expanded && !visible(contentWrapper)
        headerWrapper.isHidden = presentation == .expanded && !visible(headerWrapper)
        pickerWrapper.isHidden = presentation != .picker && !visible(pickerWrapper)
        contentWrapper.setAccessibilityHidden(presentation != .expanded)
        headerWrapper.setAccessibilityHidden(presentation == .expanded)
        pickerWrapper.setAccessibilityHidden(presentation != .picker)
        setRailsVisible(presentation == .expanded || railWrappers.contains(where: visible))
        for wrapper in railWrappers { wrapper.setAccessibilityHidden(presentation != .expanded || notificationPresentation) }
        needsLayout = true; layoutSubtreeIfNeeded()
        applyGeometry(size)
        if animated {
            motion = next; startedAt = CACurrentMediaTime()
            installGeometry(next)
            if changesVisibility { animateAppearance(presentation) }
        } else {
            removeAppearance(); setAppearance(presentation); appearanceEndsAt = 0
        }
        CATransaction.commit()
        let finish = { [weak self] in
            guard let self, self.generation == token else { return }
            self.motion = nil; self.completion = nil
            CATransaction.begin(); CATransaction.setDisableActions(true)
            self.removeGeometry(); self.removeAppearance(); self.applyGeometry(size); self.setAppearance(presentation)
            self.contentWrapper.isHidden = presentation != .expanded
            self.headerWrapper.isHidden = presentation == .expanded
            self.pickerWrapper.isHidden = presentation != .picker
            self.setRailsVisible(presentation == .expanded)
            CATransaction.commit()
            onComplete()
        }
        if animated {
            let delay = max(next.duration, appearanceEndsAt - CACurrentMediaTime())
            let work = DispatchWorkItem(block: finish); completion = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else { finish() }
    }

    private func installGeometry(_ motion: NotchMotion) {
        let count = max(1, Int(ceil(motion.duration * 120)))
        let times = (0...count).map { Double($0) / Double(count) }
        let sizes = times.map { motion.sample(at: $0 * motion.duration).size }
        for layer in [silhouette, edge] {
            animate(layer, key: "path", values: sizes.map(path), times: times, duration: motion.duration)
        }
        for (index, wrapper) in railWrappers.enumerated() {
            guard let layer = wrapper.layer else { continue }
            let key = index == 2 ? "transform.translation.y" : "transform.translation.x"
            animate(layer, key: key, values: sizes.map { railOffset(index, size: $0) }, times: times, duration: motion.duration)
        }
    }

    private func animateAppearance(_ presentation: Presentation) {
        let now = CACurrentMediaTime()
        let expanded = presentation == .expanded
        // The shell gets a head start. The incoming page grows from its top
        // centre; outgoing controls leave promptly before the shell closes.
        appearanceEndsAt = now + (presentation == .compact ? 0.36 : 0.45)
        fade(blackVeil, to: presentation == .compact ? 1 : 0, duration: presentation == .compact ? 0.16 : 0.3, delay: 0)
        if let layer = contentWrapper.layer {
            fade(layer, to: expanded ? 1 : 0, duration: expanded ? 0.2925 : 0.16, delay: expanded ? 0.1575 : 0)
            let shown = layer.presentation() ?? layer
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = shown.opacity < 0.01 && expanded ? 0.86 : (shown.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue ?? 1
            scale.toValue = expanded ? 1.0 : 0.94
            scale.duration = expanded ? 0.45 : 0.16
            scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            layer.setValue(expanded ? 1.0 : 0.94, forKeyPath: "transform.scale")
            layer.add(scale, forKey: "orbit.appearance.scale")
        }
        if let layer = headerWrapper.layer { fade(layer, to: expanded ? 0 : 1, duration: expanded ? 0.10 : 0.20, delay: expanded ? 0 : 0.16) }
        if let layer = pickerWrapper.layer {
            let opening = presentation == .picker
            fade(layer, to: opening ? 1 : 0, duration: opening ? 0.25 : 0.12, delay: opening ? 0.10 : 0)
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = layer.presentation()?.value(forKeyPath: "transform.translation.y") ?? layer.value(forKeyPath: "transform.translation.y")
            slide.toValue = opening ? 0 : -6
            slide.duration = opening ? 0.35 : 0.12
            slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            layer.setValue(opening ? 0 : -6, forKeyPath: "transform.translation.y")
            layer.add(slide, forKey: "orbit.appearance.slide")
        }
        for wrapper in railWrappers {
            if let layer = wrapper.layer { fade(layer, to: expanded ? 1 : 0, duration: expanded ? 0.24 : 0.12, delay: expanded ? 0.12 : 0) }
        }
    }

    private func fade(_ layer: CALayer, to opacity: Float, duration: Double, delay: Double) {
        let initial = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = opacity
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = initial; fade.toValue = opacity; fade.duration = duration
        fade.beginTime = layer.convertTime(CACurrentMediaTime() + (initial > 0.01 && initial < 0.99 ? 0 : delay), from: nil)
        fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: opacity == 0 ? .easeIn : .easeOut)
        layer.add(fade, forKey: "orbit.appearance.opacity")
    }

    private func setAppearance(_ presentation: Presentation) {
        let expanded = presentation == .expanded
        blackVeil.opacity = presentation == .compact ? 1 : 0
        contentWrapper.layer?.opacity = expanded ? 1 : 0
        contentWrapper.layer?.setValue(expanded ? 1.0 : 0.86, forKeyPath: "transform.scale")
        headerWrapper.layer?.opacity = expanded ? 0 : 1
        pickerWrapper.layer?.opacity = presentation == .picker ? 1 : 0
        pickerWrapper.layer?.setValue(presentation == .picker ? 0 : -6, forKeyPath: "transform.translation.y")
        for wrapper in railWrappers { wrapper.layer?.opacity = expanded ? 1 : 0 }
    }

    func stop() {
        let size = presentedSize
        generation += 1; completion?.cancel(); completion = nil; motion = nil; settledSize = size
        removeGeometry(); removeAppearance()
    }

    func containsInteraction(_ local: CGPoint) -> Bool {
        path(presentedSize).contains(local) || railWrappers.contains { wrapper in
            guard !wrapper.isHidden, let layer = wrapper.layer, (layer.presentation()?.opacity ?? layer.opacity) > 0.8 else { return false }
            return (layer.presentation()?.frame ?? wrapper.frame).contains(local)
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for wrapper in railWrappers where !wrapper.isHidden && wrapper.frame.contains(local) {
            if (wrapper.layer?.presentation()?.opacity ?? wrapper.layer?.opacity ?? 0) > 0.8 { return wrapper.hitTest(local) }
        }
        guard path(presentedSize).contains(local) else { return nil }
        return bodyView.hitTest(local)
    }

    private func path(_ size: CGSize) -> CGPath {
        let x = (bounds.width - size.width) / 2
        let radius = min(size.width / 2, NotchLayout.cornerRadius(height: size.height))
        let shoulder = min(size.width / 4, NotchLayout.shoulder(height: size.height))
        let left = x + shoulder, right = x + size.width - shoulder
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x + size.width, y: 0))
        path.addQuadCurve(to: CGPoint(x: right, y: shoulder), control: CGPoint(x: right, y: 0))
        path.addLine(to: CGPoint(x: right, y: size.height - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: size.height), control: CGPoint(x: right, y: size.height))
        path.addLine(to: CGPoint(x: left + radius, y: size.height))
        path.addQuadCurve(to: CGPoint(x: left, y: size.height - radius), control: CGPoint(x: left, y: size.height))
        path.addLine(to: CGPoint(x: left, y: shoulder))
        path.addQuadCurve(to: CGPoint(x: x, y: 0), control: CGPoint(x: left, y: 0))
        path.closeSubpath(); return path
    }
    private func railOffset(_ index: Int, size: CGSize) -> Double {
        if index == 2 { return size.height - expandedSize.height }
        return (size.width - expandedSize.width) / 2 * (index == 0 ? -1 : 1)
    }
    private func applyGeometry(_ size: CGSize) {
        silhouette.path = path(size); edge.path = path(size)
        for (index, wrapper) in railWrappers.enumerated() {
            wrapper.layer?.setValue(railOffset(index, size: size), forKeyPath: index == 2 ? "transform.translation.y" : "transform.translation.x")
        }
    }
    private func animate(_ layer: CALayer, key: String, values: [Any], times: [Double], duration: Double) {
        let animation = CAKeyframeAnimation(keyPath: key)
        animation.values = values; animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.duration = duration; animation.calculationMode = .linear
        animation.beginTime = layer.convertTime(startedAt, from: nil)
        layer.add(animation, forKey: "orbit.notch.\(key)")
    }
    private func removeGeometry() {
        for layer in [silhouette, edge] + railWrappers.compactMap(\.layer) {
            for key in layer.animationKeys() ?? [] where key.hasPrefix("orbit.notch.") { layer.removeAnimation(forKey: key) }
        }
    }
    private func removeAppearance() {
        blackVeil.removeAllAnimations()
        for wrapper in [contentWrapper, headerWrapper, pickerWrapper] + railWrappers {
            guard let layer = wrapper.layer else { continue }
            for key in layer.animationKeys() ?? [] where key.hasPrefix("orbit.appearance.") { layer.removeAnimation(forKey: key) }
        }
    }
}

private final class NotchBodyView: NSView {
    override var isFlipped: Bool { true }
    var acceptsInteraction = true
    override func hitTest(_ point: NSPoint) -> NSView? {
        acceptsInteraction ? super.hitTest(point) : nil
    }
}
@MainActor private final class NotchMeasurementRelay {
    var report: ((OrbitAction, Double) -> Void)?
}
