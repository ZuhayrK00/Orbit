import AppKit
import SwiftUI
import QuartzCore
import OrbitCore

/// One reserved window, one continuously morphing shell. SwiftUI lays out each
/// tool at its final size; Core Animation handles the presentation between them.
@MainActor final class WheelSurface: NSView {
    override var isFlipped: Bool { true }
    private let store: OrbitStore
    let metrics: WheelLayout
    private let body = NSView()
    private let material: OrbitGlassSurface
    private let shade = NSView()
    private let maskShape = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let shadowLayer = CALayer()
    private let wheel: NSHostingView<WheelView>
    private var tool: NSHostingView<WheelToolView>?
    private var shownSection: OrbitAction?
    private var lastPose: WheelMotion.Pose
    private var motion: WheelMotion?
    private var started: CFTimeInterval = 0
    private var completion: DispatchWorkItem?
    private var generation = 0
    var onMeasured: ((OrbitAction, Double) -> Void)?
    var animates: Bool { store.configuration.wheel.animate && !store.reduceMotion }
    private var sample: WheelMotion.Sample? { motion?.sample(at: CACurrentMediaTime() - started) }
    private var currentPose: WheelMotion.Pose { sample?.pose ?? lastPose }
    var isMorphing: Bool { completion != nil }
    private var circle: WheelMotion.Pose { .init(size: CGSize(width: metrics.diameter, height: metrics.diameter), radius: metrics.diameter / 2) }

    init(store: OrbitStore, metrics: WheelLayout) {
        self.store = store; self.metrics = metrics
        material = OrbitGlassSurface(transparency: store.configuration.effectiveGlassTransparency, tint: store.configuration.effectiveGlassColor)
        lastPose = .init(size: CGSize(width: metrics.diameter * 0.9, height: metrics.diameter * 0.9), radius: metrics.diameter / 2)
        var wheelView = WheelView(store: store)
        wheelView.hosted = true; wheelView.presentedDiameter = metrics.diameter
        wheel = NSHostingView(rootView: wheelView)
        super.init(frame: CGRect(origin: .zero, size: metrics.frame.size))
        wantsLayer = true; appearance = NSAppearance(named: .darkAqua)
        shadowLayer.shadowColor = NSColor.black.cgColor; shadowLayer.shadowOpacity = 0.32
        shadowLayer.shadowRadius = 20; shadowLayer.shadowOffset = CGSize(width: 0, height: -8)
        layer?.addSublayer(shadowLayer)
        body.wantsLayer = true; body.layer?.mask = maskShape; addSubview(body)
        material.wantsLayer = true; body.addSubview(material)
        shade.wantsLayer = true
        shade.layer?.backgroundColor = NSColor(white: 0.035, alpha: max(0, store.configuration.wheelOpacity - 0.85)).cgColor
        body.addSubview(shade)
        body.addSubview(wheel); wheel.sizingOptions = []
        outline.fillColor = NSColor.clear.cgColor; outline.strokeColor = NSColor.white.withAlphaComponent(0.13).cgColor
        outline.lineWidth = 0.8; layer?.addSublayer(outline)
        layer?.opacity = 0
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updateAppearance() {
        material.tint = store.configuration.effectiveGlassColor
        material.transparency = store.configuration.effectiveGlassTransparency
        shade.layer?.backgroundColor = NSColor(white: 0.035, alpha: max(0, store.configuration.wheelOpacity - 0.85)).cgColor
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        body.frame = bounds; material.frame = body.bounds; shade.frame = body.bounds
        wheel.frame = centered(circle.size)
        if let tool { tool.frame = centered(lastPose.size) }
        maskShape.frame = bounds; outline.frame = bounds; shadowLayer.frame = bounds
        apply(lastPose)
        CATransaction.commit()
    }
    private func centered(_ size: CGSize) -> CGRect {
        CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    func contains(_ point: CGPoint) -> Bool { path(currentPose).contains(point) }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard contains(local) else { return nil }
        if shownSection != nil, let tool { return tool.hitTest(convert(local, to: body)) }
        return wheel.hitTest(convert(local, to: body))
    }
    func open() {
        needsLayout = true; layoutSubtreeIfNeeded()
        move(to: circle, animated: animates)
        fade(layer, to: 1, duration: animates ? 0.20 : 0)
    }
    func present(_ section: OrbitAction?) {
        guard section != shownSection else { return }
        shownSection = section
        if let section {
            let height = min(metrics.toolHeightLimit, ToolLayout.contentHeight(section, timerPresetCount: store.configuration.effectiveTimerPresets.count) + WheelToolView.chromeHeight)
            let root = WheelToolView(store: store, section: section, width: metrics.toolWidth, heightLimit: metrics.toolHeightLimit) { [weak self] section, height in
                DispatchQueue.main.async { [weak self] in self?.onMeasured?(section, height) }
            }
            if let tool { tool.rootView = root }
            else {
                let host = NSHostingView(rootView: root); host.sizingOptions = []; host.wantsLayer = true
                body.addSubview(host); tool = host; host.layer?.opacity = 0
            }
            tool?.isHidden = false
            wheel.wantsLayer = true
            fade(wheel.layer, to: 0, duration: animates ? 0.12 : 0)
            move(to: .init(size: CGSize(width: metrics.toolWidth, height: height), radius: 26), animated: animates)
            reveal(tool?.layer, delay: animates ? 0.10 : 0)
        } else {
            // Wheel sectors cannot take clicks through a departing tool.
            wheel.isHidden = false
            fade(tool?.layer, to: 0, duration: animates ? 0.10 : 0)
            move(to: circle, animated: animates)
            reveal(wheel.layer, delay: animates ? 0.08 : 0)
        }
    }
    func fit(section: OrbitAction, height: Double) {
        guard section == shownSection, height.isFinite, height > 0 else { return }
        let size = CGSize(width: metrics.toolWidth, height: min(metrics.toolHeightLimit, ceil(height)))
        guard abs(size.height - lastPose.size.height) > 0.5 else { return }
        move(to: .init(size: size, radius: 26), animated: animates)
    }
    func close(animated: Bool, completion: @escaping () -> Void) {
        let pose = currentPose
        move(to: .init(size: CGSize(width: pose.size.width * 0.96, height: pose.size.height * 0.96), radius: pose.radius), animated: animated && animates)
        fade(layer, to: 0, duration: animated && animates ? 0.14 : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated && animates ? 0.15 : 0), execute: DispatchWorkItem(block: completion))
    }
    func stop() { completion?.cancel(); completion = nil; motion = nil }

    private func move(to pose: WheelMotion.Pose, animated: Bool) {
        let previous = sample
        let next = WheelMotion(from: currentPose, velocity: previous?.velocity ?? .zero, radiusVelocity: previous?.radiusVelocity ?? 0, to: pose)
        completion?.cancel(); generation += 1
        let token = generation
        motion = nil; lastPose = pose
        CATransaction.begin(); CATransaction.setDisableActions(true)
        needsLayout = true; layoutSubtreeIfNeeded()
        [maskShape, outline, shadowLayer].forEach { $0.removeAnimation(forKey: "orbit.wheel.path") }
        apply(pose)
        if animated {
            motion = next; started = CACurrentMediaTime()
            let frames = max(1, Int(ceil(next.duration * 120)))
            let times = (0...frames).map { Double($0) / Double(frames) }
            let paths = times.map { path(next.sample(at: $0 * next.duration).pose) }
            for (layer, key) in [(maskShape as CALayer, "path"), (outline, "path"), (shadowLayer, "shadowPath")] {
                let animation = CAKeyframeAnimation(keyPath: key)
                animation.values = paths; animation.keyTimes = times.map(NSNumber.init(value:)); animation.duration = next.duration
                animation.calculationMode = .linear; layer.add(animation, forKey: "orbit.wheel.path")
            }
        }
        CATransaction.commit()
        let settle = { [weak self] in
            guard let self, token == self.generation else { return }
            self.motion = nil; self.completion = nil
            self.wheel.isHidden = self.shownSection != nil
            self.tool?.isHidden = self.shownSection == nil
        }
        if animated { let work = DispatchWorkItem(block: settle); completion = work; DispatchQueue.main.asyncAfter(deadline: .now() + next.duration, execute: work) }
        else { settle() }
    }
    private func path(_ pose: WheelMotion.Pose) -> CGPath {
        let rect = centered(pose.size)
        let r = max(0, min(pose.radius, min(rect.width, rect.height) / 2))
        // Explicitly keep all four line/curve pairs, including the zero-length
        // lines of a circle, so Core Animation can interpolate every path.
        let k = r * 0.5522847498, p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control1: CGPoint(x: rect.maxX - r + k, y: rect.minY), control2: CGPoint(x: rect.maxX, y: rect.minY + r - k))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control1: CGPoint(x: rect.maxX, y: rect.maxY - r + k), control2: CGPoint(x: rect.maxX - r + k, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control1: CGPoint(x: rect.minX + r - k, y: rect.maxY), control2: CGPoint(x: rect.minX, y: rect.maxY - r + k))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control1: CGPoint(x: rect.minX, y: rect.minY + r - k), control2: CGPoint(x: rect.minX + r - k, y: rect.minY))
        p.closeSubpath(); return p
    }
    private func apply(_ pose: WheelMotion.Pose) {
        let shape = path(pose); maskShape.path = shape; outline.path = shape; shadowLayer.shadowPath = shape
    }
    private func fade(_ layer: CALayer?, to opacity: Float, duration: Double, delay: Double = 0) {
        guard let layer else { return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin(); CATransaction.setDisableActions(true); layer.opacity = opacity; CATransaction.commit()
        layer.removeAnimation(forKey: "orbit.wheel.fade")
        guard duration > 0 else { return }
        let animation = CABasicAnimation(keyPath: "opacity"); animation.fromValue = from; animation.toValue = opacity
        animation.duration = duration; animation.beginTime = CACurrentMediaTime() + delay; animation.fillMode = .backwards
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "orbit.wheel.fade")
    }
    private func reveal(_ layer: CALayer?, delay: Double) {
        fade(layer, to: 1, duration: animates ? 0.23 : 0, delay: delay)
        guard let layer, animates else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = layer.presentation()?.value(forKeyPath: "transform.scale") ?? 0.94
        animation.toValue = 1; animation.duration = 0.32
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        layer.add(animation, forKey: "orbit.wheel.reveal")
    }
}
