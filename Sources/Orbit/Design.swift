import SwiftUI
import AppKit
import OrbitCore

enum OrbitDesign {
    static let background = Color(white: 0.105)
    static let panel = Color(white: 0.075)
    static let surface = Color.white.opacity(0.045)
    static let secondary = Color.secondary
    static let border = Color.white.opacity(0.08)
    static func accent(_ accent: Accent) -> Color {
        switch accent {
        case .violet: return Color(red: 0.61, green: 0.55, blue: 0.94)
        case .mint: return Color(red: 0.30, green: 0.76, blue: 0.60)
        case .coral: return Color(red: 0.95, green: 0.49, blue: 0.40)
        case .blue: return Color(red: 0.34, green: 0.62, blue: 0.98)
        }
    }
}
enum OrbitSurfaceKind { case window, floating, notch, wheel }
private struct OrbitSurfaceKey: EnvironmentKey { static let defaultValue = OrbitSurfaceKind.window }
private struct OrbitAccentKey: EnvironmentKey { static let defaultValue = OrbitDesign.accent(.violet) }
private struct OrbitMotionKey: EnvironmentKey { static let defaultValue = false }
private struct OrbitTransparencyKey: EnvironmentKey { static let defaultValue = 0.68 }
private struct OrbitGlassColorKey: EnvironmentKey { static let defaultValue = NotchColor.black }
struct OrbitGlassOutline { var color: Color; var width: Double }
private struct OrbitGlassOutlineKey: EnvironmentKey { static let defaultValue: OrbitGlassOutline? = nil }
extension EnvironmentValues {
    var orbitReduceMotion: Bool { get { self[OrbitMotionKey.self] } set { self[OrbitMotionKey.self] = newValue } }
    var orbitAccent: Color { get { self[OrbitAccentKey.self] } set { self[OrbitAccentKey.self] = newValue } }
    var orbitSurface: OrbitSurfaceKind { get { self[OrbitSurfaceKey.self] } set { self[OrbitSurfaceKey.self] = newValue } }
    var orbitTransparency: Double { get { self[OrbitTransparencyKey.self] } set { self[OrbitTransparencyKey.self] = newValue } }
    var orbitGlassColor: NotchColor { get { self[OrbitGlassColorKey.self] } set { self[OrbitGlassColorKey.self] = newValue } }
    var orbitGlassOutline: OrbitGlassOutline? { get { self[OrbitGlassOutlineKey.self] } set { self[OrbitGlassOutlineKey.self] = newValue } }
}

extension NotchColor {
    var swiftUI: Color { Color(red: red, green: green, blue: blue) }
    var appKit: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    /// The same dark coloured backing for AppKit surfaces and SwiftUI controls.
    var glassShade: NotchColor {
        let color = normalized
        return .init(0.035 + color.red * 0.18, 0.035 + color.green * 0.18, 0.035 + color.blue * 0.18)
    }
    init(_ color: Color) {
        let value = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(value.redComponent, value.greenComponent, value.blueComponent)
    }
}

struct WindowMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = material
        view.blendingMode = .behindWindow; view.state = .active; return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}
struct OrbitGlass<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color = .clear
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.orbitTransparency) private var transparency
    @Environment(\.orbitGlassColor) private var color
    @Environment(\.orbitGlassOutline) private var outline
    func body(content: Content) -> some View {
        // Apply glass to the whole control so GlassEffectContainer excludes its
        // foreground from refraction. Only the backing changes opacity.
        treatment(content)
            .overlay(shape.stroke(outline?.color ?? .clear, lineWidth: outline?.width ?? 0))
    }
    @ViewBuilder private func treatment(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(color.glassShade.swiftUI, in: shape).background(tint, in: shape)
                .overlay(shape.stroke(.white.opacity(0.22), lineWidth: 0.7))
        } else if #available(macOS 26, *) {
            content.background { shape.fill(color.glassShade.swiftUI.opacity(1 - transparency)).overlay(shape.fill(tint)) }
                .glassEffect(Glass.clear.tint(color.swiftUI.opacity(0.18)).interactive(interactive), in: shape)
        } else {
            content.background {
                WindowMaterial(material: .hudWindow).clipShape(shape)
                    .overlay(shape.fill(color.glassShade.swiftUI.opacity(1 - transparency))).overlay(shape.fill(tint))
            }
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 0.7))
        }
    }
}
extension View {
    func orbitGlass<S: Shape>(in shape: S, tint: Color = .clear, interactive: Bool = false) -> some View {
        modifier(OrbitGlass(shape: shape, tint: tint, interactive: interactive))
    }
    func orbitControls(_ store: OrbitStore) -> some View {
        self.tint(OrbitDesign.accent(store.configuration.accent)).modifier(OrbitToggleTreatment()).controlSize(.small)
            .scrollIndicators(.never)
            .environment(\.orbitTransparency, store.configuration.effectiveGlassTransparency)
            .environment(\.orbitGlassColor, store.configuration.effectiveGlassColor)
            .textFieldStyle(OrbitTextFieldStyle()).environment(\.orbitReduceMotion, store.reduceMotion).environment(\.orbitAccent, OrbitDesign.accent(store.configuration.accent))
    }
}
struct OrbitMark: View {
    var size: CGFloat = 28
    var color: Color = OrbitDesign.accent(.violet)
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.45), lineWidth: max(1, size * 0.04)).frame(width: size * 0.7)
            Ellipse().stroke(color, lineWidth: max(1.2, size * 0.04)).frame(width: size, height: size * 0.36).rotationEffect(.degrees(-35))
            Circle().fill(color).frame(width: size * 0.13).offset(x: size * 0.34, y: -size * 0.22)
        }.frame(width: size, height: size).accessibilityLabel("Orbit")
    }
}
struct OrbitCard<Content: View>: View {
    @Environment(\.orbitSurface) private var surface
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(surface == .window ? 16 : 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(surface == .window ? 0.045 : 0.025), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(contrast == .increased ? 0.26 : 0.09), lineWidth: 0.65))
    }
}
struct OrbitButtonStyle: ButtonStyle {
    var prominent = false
    var color: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        OrbitButtonChrome(label: configuration.label, pressed: configuration.isPressed, prominent: prominent, color: color)
    }
}
private struct OrbitButtonChrome<Label: View>: View {
    let label: Label
    let pressed: Bool
    let prominent: Bool
    let color: Color?
    @Environment(\.orbitAccent) private var accent
    private var highlight: Color { color ?? accent }
    @Environment(\.isEnabled) private var enabled
    @Environment(\.orbitReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        label.font(.system(size: 11, weight: .medium)).padding(.horizontal, 11).frame(minHeight: 28)
            .foregroundStyle(prominent ? highlight : Color.primary.opacity(0.85))
            .orbitGlass(in: Capsule(), tint: prominent ? highlight.opacity(0.18) : .clear, interactive: true)
            .contentShape(Rectangle()).opacity(enabled ? 1 : 0.35)
            .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: pressed)
            .onHover { hovered = $0 }
    }
}
struct OrbitIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).frame(width: 30, height: 30)
            .orbitGlass(in: Circle(), interactive: true).contentShape(Circle()).scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
struct OrbitTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).font(.system(size: 12)).padding(.horizontal, 9).padding(.vertical, 7)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14), lineWidth: 0.65))
    }
}
struct OrbitMenuPicker<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [(String, Selection)]
    private var label: String { options.first { $0.1 == selection }?.0 ?? title }
    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                Button { selection = options[index].1 } label: {
                    if selection == options[index].1 { Label(options[index].0, systemImage: "checkmark") }
                    else { Text(options[index].0) }
                }
            }
        } label: {
            HStack(spacing: 8) { Text(label).lineLimit(1); Spacer(minLength: 2); Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary) }
                .font(.system(size: 11)).foregroundStyle(.primary).padding(.horizontal, 9).frame(height: 28)
                .orbitGlass(in: RoundedRectangle(cornerRadius: 10), interactive: true).contentShape(Rectangle())
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .accessibilityLabel(title).accessibilityValue(label)
    }
}
struct SectionTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 21, weight: .semibold)).tracking(-0.35)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 4)
    }
}
struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular)).foregroundStyle(.secondary)
                .frame(width: 34, height: 34).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 9)
    }
}
struct StatusPill: View {
    let title: String
    var symbol = "checkmark.circle.fill"
    var color: Color = .green
    var body: some View {
        Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 4).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
}
struct SettingHeading: View {
    let title: String
    let subtitle: String
    var symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 22, height: 24)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 13, weight: .semibold)); Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
        }
    }
}
extension AgentPhase {
    var color: Color { switch self { case .running: return OrbitDesign.accent(.mint); case .waiting: return .orange; case .completed: return OrbitDesign.accent(.blue); case .failed: return .red; case .idle, .offline: return OrbitDesign.secondary } }
    var label: String { switch self { case .running: return "Working"; case .waiting: return "Needs you"; case .completed: return "Finished"; case .failed: return "Error"; case .idle: return "Ready"; case .offline: return "No recent update" } }
}
extension OrbitAction {
    var toolColor: Color {
        switch self {
        case .timer, .keepAwake: return .orange
        case .music: return .pink
        case .agents: return OrbitDesign.accent(.mint)
        case .clipboard, .textTools: return OrbitDesign.accent(.blue)
        default: return .white.opacity(0.8)
        }
    }
    var shortTitle: String {
        switch self { case .files: return "Files"; case .textTools: return "Text"; case .scratchpad: return "Notes"; case .sound: return "Sound"; case .music: return "Music"; case .keepAwake: return "Keep awake"; default: return title }
    }
}
