import AppKit
import SwiftUI
import OrbitCore

/// Glass lives behind the content, so changing clarity never fades labels.
@MainActor final class OrbitGlassSurface: NSView {
    private let effect: NSView
    private let shade = NSView()
    var tint: NotchColor { didSet { if oldValue != tint { updateAppearance() } } }
    var transparency: Double { didSet { if oldValue != transparency { updateAppearance() } } }
    init(transparency: Double, tint: NotchColor = .black) {
        self.transparency = transparency
        self.tint = tint
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(); glass.cornerRadius = 0; glass.style = .clear
            if #available(macOS 27, *) { glass.effectIsInteractive = false }
            effect = glass
        } else {
            let blur = NSVisualEffectView(); blur.material = .hudWindow; blur.blendingMode = .behindWindow; blur.state = .active; effect = blur
        }
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true; shade.wantsLayer = true
        addSubview(effect); addSubview(shade); updateAppearance()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func layout() { super.layout(); effect.frame = bounds; shade.frame = bounds; updateAppearance() }
    private func updateAppearance() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        effect.isHidden = reduce
        if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
            let colour = tint.appKit.withAlphaComponent(0.18)
            if glass.tintColor != colour { glass.tintColor = colour }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shade.layer?.backgroundColor = tint.glassShade.appKit.withAlphaComponent(reduce ? 1 : 1 - transparency).cgColor
        CATransaction.commit()
    }
}

struct OrbitBackdrop: NSViewRepresentable {
    var transparency: Double
    var tint: NotchColor
    func makeNSView(context: Context) -> OrbitGlassSurface { OrbitGlassSurface(transparency: transparency, tint: tint) }
    func updateNSView(_ view: OrbitGlassSurface, context: Context) { view.tint = tint; view.transparency = transparency }
}

struct OrbitToggleTreatment: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.toggleStyle(OrbitGlassToggleStyle()) }
        else { content.toggleStyle(.switch) }
    }
}

@available(macOS 15, *)
struct OrbitGlassToggleStyle: ToggleStyle {
    @Environment(\.orbitAccent) private var accent
    @Environment(\.orbitReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @Environment(\.labelsVisibility) private var labelsVisibility
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            if labelsVisibility != .hidden { configuration.label; Spacer(minLength: 12) }
            Button { configuration.isOn.toggle() } label: {
                Capsule().fill(configuration.isOn ? accent.opacity(0.55) : .white.opacity(0.06))
                    .frame(width: 38, height: 22)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white.opacity(0.95)).frame(width: 17, height: 17).shadow(color: .black.opacity(0.18), radius: 1, y: 1).padding(2.5)
                    }.orbitGlass(in: Capsule(), interactive: true)
            }.buttonStyle(.plain)
                .opacity(enabled ? 1 : 0.4)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85), value: configuration.isOn)
        }.accessibilityRepresentation {
            Toggle(isOn: Binding(get: { configuration.isOn }, set: { configuration.isOn = $0 })) { configuration.label }.toggleStyle(.switch)
        }
    }
}

struct OrbitGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: 0) { content } }
        else { content }
    }
}
