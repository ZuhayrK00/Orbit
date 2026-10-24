import SwiftUI
import OrbitCore

private struct ToolNavigationKey: EnvironmentKey {
    static let defaultValue: (OrbitAction) -> Void = { _ in }
}
extension EnvironmentValues {
    var openOrbitTool: (OrbitAction) -> Void {
        get { self[ToolNavigationKey.self] }
        set { self[ToolNavigationKey.self] = newValue }
    }
}

/// All three entry points use the same controls and the same live store.
struct SurfaceToolView: View {
    @Environment(\.orbitSurface) private var surface
    @ObservedObject var store: OrbitStore
    let section: OrbitAction
    var navigate: (OrbitAction) -> Void
    var body: some View {
        VStack(spacing: 10) {
            if surface == .notch {
                UtilityContent(store: store, compact: true, section: section)
                    .frame(maxWidth: .infinity, alignment: .leading).id(section)
            } else {
                ScrollView {
                    UtilityContent(store: store, compact: true, section: section)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                }.scrollIndicators(.never).id(section)
            }
            if let error = store.error {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(OrbitIconButtonStyle()).accessibilityLabel("Dismiss error")
                }
            } else if let toast = store.toast {
                Text(toast).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.orbitControls(store).environment(\.openOrbitTool, navigate)
    }
}

enum ToolLayout {
    static func contentHeight(_ action: OrbitAction, timerPresetCount: Int = 4) -> Double {
        switch action {
        case .timer: return timerPresetCount > 4 ? 284 : 244
        case .music: return 260
        case .keepAwake: return 510
        case .agents: return 286
        case .clipboard: return 286
        case .scratchpad: return 310
        default: return 326
        }
    }
    static func menuHeight(_ action: OrbitAction?, timerPresetCount: Int = 4) -> Double { action.map { contentHeight($0, timerPresetCount: timerPresetCount) + 106 } ?? Double((OrbitAction.surfaceTools.count + 2) / 3) * 41 + 159 }
}

struct SurfaceIcon: View {
    let action: OrbitAction
    var selected = false
    var accent = OrbitDesign.accent(.violet)
    var targetSize: CGFloat = 44
    var title: String?
    var perform: () -> Void
    @State private var hovered = false
    @Environment(\.orbitReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: perform) {
            Image(systemName: action.symbol).font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? accent : .white.opacity(hovered ? 0.95 : 0.55))
                .frame(width: targetSize - 6, height: targetSize - 6)
                .orbitGlass(in: Circle(), tint: selected ? accent.opacity(0.18) : .clear, interactive: true)
                .frame(width: targetSize, height: targetSize).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .help(title ?? action.title).accessibilityLabel(title ?? action.title).accessibilityValue(selected ? "Selected" : "")
    }
}

struct SurfaceNavigation: View {
    let selection: OrbitAction?
    var select: (OrbitAction) -> Void
    var body: some View {
        OrbitGlassGroup { HStack(spacing: 1) {
            ForEach(OrbitAction.surfaceTools) { action in
                SurfaceIcon(action: action, selected: action == selection, accent: action.toolColor, targetSize: 33) { select(action) }
            }
        }.frame(maxWidth: .infinity).padding(3) }
    }
}

/// The wheel becomes the selected utility. Navigation belongs in its header;
/// no second tool bar competes with the utility or steals vertical space.
struct WheelToolView: View {
    static let chromeHeight = 101.0
    @ObservedObject var store: OrbitStore
    let section: OrbitAction
    let width: Double
    let heightLimit: Double
    var measured: (OrbitAction, Double) -> Void
    @State private var contentHeight = 260.0
    private var budget: Double { max(80, heightLimit - Self.chromeHeight) }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { store.returnToWheel() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .medium)).frame(width: 32, height: 32).contentShape(Rectangle())
                }.buttonStyle(OrbitIconButtonStyle()).foregroundStyle(.secondary).accessibilityLabel("Back to wheel").help("Back to wheel")
                Image(systemName: section.symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(section.toolColor)
                if section != .music { Text(section.title).font(.system(size: 16, weight: .semibold)).tracking(-0.3) }
                Spacer(minLength: 6)
                Button { store.wheelPinned.toggle() } label: {
                    Image(systemName: store.wheelHoldsOpen ? "pin.fill" : "pin").font(.system(size: 12))
                        .foregroundStyle(store.wheelHoldsOpen ? section.toolColor : .secondary)
                        .frame(width: 30, height: 32).contentShape(Rectangle())
                }.buttonStyle(OrbitIconButtonStyle()).disabled((section == .files || section == .shelf) || store.isProcessing)
                    .accessibilityLabel(section == .files ? "File tools stays open for drops" : store.wheelPinned ? "Unpin tool" : "Keep tool open")
                    .help(section == .files ? "Stays open while you select files in Finder" : "Keep this tool open when clicking elsewhere")
                Button { store.hideWheel?() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).frame(width: 30, height: 32).contentShape(Rectangle())
                }.buttonStyle(OrbitIconButtonStyle()).foregroundStyle(.secondary).accessibilityLabel("Close wheel").help("Close")
            }.frame(height: 36)
            Rectangle().fill(.white.opacity(0.07)).frame(height: 0.5)
            ScrollView {
                VStack(spacing: 12) {
                    UtilityContent(store: store, compact: true, section: section)
                    if let error = store.error {
                        HStack(alignment: .top) {
                            Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(OrbitIconButtonStyle()).accessibilityLabel("Dismiss error")
                        }
                    } else if let toast = store.toast {
                        Text(toast).font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { proxy in Color.clear.preference(key: WheelContentHeight.self, value: proxy.size.height) })
            }.frame(height: min(budget, contentHeight)).scrollIndicators(.never)
                .onPreferenceChange(WheelContentHeight.self) { height in
                    if height.isFinite, height > 0, abs(height - contentHeight) > 0.5 { contentHeight = ceil(height) }
                }.id(section)
        }.padding(20).frame(width: width).fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in Color.clear.preference(key: WheelPanelHeight.self, value: proxy.size.height) })
            .onPreferenceChange(WheelPanelHeight.self) { measured(section, $0) }
            .preferredColorScheme(.dark).environment(\.orbitSurface, .wheel).orbitControls(store)
            .environment(\.openOrbitTool, store.showWheelTool)
    }
}
private struct WheelContentHeight: PreferenceKey {
    static var defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = max(value, nextValue()) }
}
private struct WheelPanelHeight: PreferenceKey {
    static var defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = max(value, nextValue()) }
}

struct MenuBarView: View {
    @ObservedObject var store: OrbitStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { store.menuSection = nil } label: { OrbitMark(size: 20, color: .white.opacity(0.8)) }.buttonStyle(.plain).help("All tools").accessibilityLabel("All tools")
                if store.menuSection != .music { Text(store.menuSection?.title ?? "Orbit").font(.system(size: 13, weight: .semibold)) }
                Spacer()
                Button { store.openWheel?() } label: { Image(systemName: "circle.hexagongrid") }.buttonStyle(OrbitIconButtonStyle()).help("Open wheel").accessibilityLabel("Open wheel")
                Button { store.openSettings?() } label: { Image(systemName: "gearshape") }.buttonStyle(OrbitIconButtonStyle()).accessibilityLabel("Orbit settings")
            }
            if store.menuSection != nil { Menu("Switch tool") { ForEach(OrbitAction.surfaceTools) { action in Button(action.title) { store.menuSection = action } } }.menuStyle(.borderlessButton) }
            if let section = store.menuSection { SurfaceToolView(store: store, section: section) { store.menuSection = $0 } }
            else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(OrbitAction.surfaceTools) { action in
                        Button { store.menuSection = action } label: {
                            HStack(spacing: 9) {
                                Image(systemName: action.symbol).font(.system(size: 13)).foregroundStyle(action.toolColor).frame(width: 20)
                                Text(action.shortTitle).font(.system(size: 10, weight: .medium)).lineLimit(1); Spacer(minLength: 0)
                            }.padding(.horizontal, 10).frame(height: 35).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Circle().fill(.mint).frame(width: 4, height: 4); Text("On this Mac"); Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.padding(16).frame(width: 400, height: ToolLayout.menuHeight(store.menuSection, timerPresetCount: store.configuration.effectiveTimerPresets.count))
            .background(OrbitBackdrop(transparency: store.configuration.effectiveGlassTransparency, tint: store.configuration.effectiveGlassColor)).preferredColorScheme(.dark).environment(\.orbitSurface, .floating).orbitControls(store)
    }
}
