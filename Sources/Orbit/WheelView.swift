import SwiftUI
import OrbitCore

struct WheelSector: Shape {
    let index: Int
    let count: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY), sector = 360.0 / Double(max(1, count))
        let start = -90 + Double(index) * sector - sector / 2 + 1.1, end = start + sector - 2.2
        var path = Path()
        path.addArc(center: center, radius: rect.width * 0.473, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: rect.width * 0.213, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath(); return path
    }
}
struct WheelView: View {
    @ObservedObject var store: OrbitStore
    var preview = false
    var hosted = false
    var presentedDiameter: Double?
    @State private var appeared = false
    @Environment(\.colorScheme) private var scheme
    var diameter: Double { preview ? 292 : presentedDiameter ?? store.configuration.wheelDiameter }
    var accent: Color { OrbitDesign.accent(store.configuration.accent) }
    private var choices: [WheelChoice] { preview ? store.configuration.slots.map(WheelChoice.tool) : store.wheelChoices }
    private var textMode: Bool { !preview && store.wheelUsesSelection && store.selection.hasSelection }
    var body: some View {
        ZStack {
            if !hosted { Circle().fill(.clear).orbitGlass(in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.8))
                .shadow(color: .black.opacity(preview ? 0.12 : 0.35), radius: 20, y: 8) }
            Circle().fill(.black.opacity(0.25)).overlay(Circle().strokeBorder(.white.opacity(0.04), lineWidth: 0.5)).frame(width: diameter * 0.39)
            ForEach(Array(choices.enumerated()), id: \.element.id) { index, slot in
                let active = !preview && store.hoveredSlot == index
                let point = WheelGeometry.center(index: index, count: choices.count, diameter: diameter)
                Button { if !preview { store.perform(slot) } } label: {
                    WheelSector(index: index, count: choices.count)
                        .fill(active ? accent.opacity(0.11) : Color.white.opacity(0.018))
                        .overlay(WheelSector(index: index, count: choices.count).stroke(active ? accent.opacity(0.16) : .clear, lineWidth: 0.8))
                        .contentShape(WheelSector(index: index, count: choices.count))
                }.buttonStyle(.plain).disabled(preview).accessibilityLabel(slot.label)
                    .animation(store.reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: active)
                VStack(spacing: preview ? 5 : 7) {
                    Image(systemName: slot.symbol).font(.system(size: preview ? 17 : 21, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? accent : Color.white.opacity(0.72))
                        .frame(width: preview ? 32 : 38, height: preview ? 32 : 38)
                        .orbitGlass(in: Circle(), tint: active ? accent.opacity(0.18) : .clear, interactive: true)
                        .scaleEffect(active && !store.reduceMotion ? 1.06 : 1)
                    if store.configuration.wheel.showLabels { Text(slot.label).font(.system(size: preview ? 9 : 10, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? Color.primary : Color.secondary).lineLimit(2).multilineTextAlignment(.center).frame(width: diameter * 0.19) }
                }.position(x: point.x, y: point.y).allowsHitTesting(false).accessibilityHidden(true)
                    .animation(store.reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.75), value: active)
            }
            VStack(spacing: textMode ? 7 : 9) {
                OrbitMark(size: preview ? 23 : 28, color: .white.opacity(0.8))
                if !preview && !textMode {
                    Menu(store.configuration.wheelProfiles?.first { $0.id == store.activeWheelProfile }?.name ?? "Default wheel") {
                        Button("Default wheel") { store.openProfile(nil) }
                        ForEach(store.configuration.wheelProfiles ?? []) { profile in Button(profile.name) { store.openProfile(profile.id) } }
                    }.font(.system(size: 10)).menuStyle(.borderlessButton).frame(maxWidth: 110)
                    if !store.wheelProfileStack.isEmpty { Button("Back") { store.returnToWheel() }.buttonStyle(.plain).font(.system(size: 10)) }
                }
                Text(centerTitle).font(.system(size: preview ? 12 : 14, weight: .semibold)).tracking(-0.3).lineLimit(1)
                if textMode {
                    Text(String(store.selection.input.prefix(65))).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
                    Text("Text actions copy results").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Button("Your tools") { store.wheelUsesSelection = false; store.hoveredSlot = nil }.font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundStyle(accent)
                } else {
                    Text(preview ? "Within reach" : store.hoveredSlot == nil ? "Choose a tool" : "Release or click").font(.system(size: preview ? 9 : 10)).foregroundStyle(.secondary)
                    if !preview && store.selection.hasSelection {
                        Button("Text actions") { store.wheelUsesSelection = true; store.hoveredSlot = nil }.font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundStyle(accent)
                    } else if !preview && store.hoveredSlot == nil { Text("esc to close").font(.system(size: 9)).foregroundStyle(.tertiary) }
                }
            }.frame(width: diameter * 0.34).allowsHitTesting(!preview)

        }.frame(width: diameter, height: diameter)
            .scaleEffect(appeared || preview || hosted || store.reduceMotion ? 1 : 0.94)
            .opacity(appeared || preview || hosted ? 1 : 0)
            .onAppear { guard !hosted else { return }; withAnimation(store.reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.92)) { appeared = true } }
            .preferredColorScheme(.dark).orbitControls(store)
            .accessibilityElement(children: .contain).accessibilityLabel("Orbit action wheel")
    }
    private var centerTitle: String {
        if !preview, let index = store.hoveredSlot, choices.indices.contains(index) { return choices[index].label }
        return textMode ? "Selected text" : "Orbit"
    }
}
