import SwiftUI
import OrbitCore

/// Direct manipulation of the same saved layout used by the live notch.
struct NotchShortcutEditor: View {
    @ObservedObject var store: OrbitStore
    @State private var editing: OrbitAction?
    @State private var adding: NotchShortcutPosition?
    @State private var dragging: OrbitAction?
    @State private var translation = CGSize.zero
    @State private var dragPoint: CGPoint?
    @State private var resizeStart: Double?
    @State private var resizeScale: CGFloat = 1
    @State private var feedback: String?
    private let sides: [NotchShortcutPosition] = [.left, .right, .bottom]
    private var options: NotchOptions { store.configuration.notch }
    private var unused: [OrbitAction] { NotchOptions.availableShortcuts.filter { action in !options.shortcuts.contains { $0.action == action && $0.position != .hidden } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Floating buttons").font(.system(size: 14, weight: .semibold))
                    Text("Drag to arrange. Click to edit. + to add.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Show floating buttons", isOn: Binding(get: { options.shortcutsEnabled }, set: { value in update { $0.shortcutsEnabled = value } }))
                    .labelsHidden().toggleStyle(.switch).accessibilityLabel("Show floating buttons")
            }
            GeometryReader { proxy in
                let geometry = ShortcutEditorGeometry(width: proxy.size.width, notchWidth: store.configuration.notchWidth)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.16))
                    preview(geometry)
                    if dragging != nil {
                        ForEach(sides, id: \.self) { side in
                            let target = geometry.dropZone(side)
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.accentColor.opacity(target.contains(dragPoint ?? .zero) ? 0.18 : 0.04))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                                .frame(width: target.width, height: target.height).position(x: target.midX, y: target.midY).allowsHitTesting(false)
                        }
                    }
                    ForEach(sides, id: \.self) { side in
                        let actions = options.actions(at: side)
                        let showAdd = options.hasRoom(at: side) && !unused.isEmpty
                        let count = actions.count + (showAdd ? 1 : 0)
                        ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                            let point = geometry.point(index, count: count, side: side)
                            shortcut(action, side: side)
                                .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("orbit.shortcut.editor"))
                                    .onChanged { value in
                                        editing = nil; adding = nil; dragging = action
                                        translation = value.translation; dragPoint = value.location
                                    }
                                    .onEnded { value in
                                        drop(action, at: value.location, geometry: geometry)
                                        dragging = nil; translation = .zero; dragPoint = nil
                                    })
                                .offset(dragging == action ? translation : .zero)
                                .position(point).zIndex(dragging == action ? 2 : 1)
                        }
                        if showAdd {
                            addButton(side).position(geometry.point(actions.count, count: count, side: side))
                        }
                    }
                    resizeGrip(geometry).position(x: geometry.body.maxX - 9, y: geometry.body.maxY - 9)
                    Text(options.shortcutsEnabled ? "\(Int(store.configuration.notchWidth)) pt wide · height follows content" : "Buttons hidden · your layout is saved")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(width: proxy.size.width - 24).position(x: proxy.size.width / 2, y: 362)
                }.coordinateSpace(name: "orbit.shortcut.editor")
                    .animation(store.reduceMotion || dragging != nil || resizeStart != nil ? nil : .spring(response: 0.3, dampingFraction: 0.9), value: options.shortcuts)
            }.frame(height: 386)
            if let feedback { Text(feedback).font(.system(size: 11)).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
            OrbitCard {
                VStack(spacing: 14) {
                    SettingSlider(title: "Expanded width", value: $store.configuration.notchWidth, range: 360...600, unit: "pt")
                    HStack {
                        SettingsToggleRow("Show notification inbox button", isOn: Binding(get: { options.showInbox }, set: { value in update { $0.showInbox = value } }))
                        Spacer(minLength: 8)
                        Button("Reset layout") { editing = nil; adding = nil; update { $0.shortcuts = NotchOptions.defaultShortcuts }; feedback = "Default button positions restored" }
                            .buttonStyle(OrbitButtonStyle()).help("Restore button positions without changing your appearance or visibility settings")
                    }
                }
            }
            Text("Place up to six buttons on either side and twelve below. Removing a button keeps its tool in the notch menu, wheel and menu bar.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func update(_ change: (inout NotchOptions) -> Void) {
        var value = options; change(&value); value.normalize()
        if value != options { store.configuration.notchSettings = value }
    }
    private func shortcut(_ action: OrbitAction, side: NotchShortcutPosition) -> some View {
        Button { editing = action; adding = nil } label: {
            Image(systemName: action.symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(editing == action ? action.toolColor : .white.opacity(0.9))
                .frame(width: 32, height: 32).orbitGlass(in: Circle())
                .overlay(Circle().strokeBorder(editing == action ? action.toolColor : .white.opacity(0.15), lineWidth: 1))
                .opacity(options.shortcutsEnabled ? 1 : 0.45).padding(2).contentShape(Circle())
        }.buttonStyle(.plain).help("Edit \(options.shortcutTitle(action)) · drag to move")
            .accessibilityLabel("Edit \(options.shortcutTitle(action)) button").accessibilityValue(side.title)
            .popover(isPresented: Binding(get: { editing == action }, set: { if !$0 { editing = nil } }), arrowEdge: edge(side)) {
                editor(action).padding(18).frame(width: 338).preferredColorScheme(.dark).orbitControls(store)
            }
            .contextMenu {
                ForEach(sides, id: \.self) { target in
                    Button("Move \(target.title.lowercased())") { move(action, to: target) }.disabled(!options.hasRoom(at: target, moving: action) || side == target)
                }
                Divider()
                Button("Remove button") { remove(action) }
            }
    }
    private func addButton(_ side: NotchShortcutPosition) -> some View {
        Button { adding = side; editing = nil } label: {
            Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32).background(.white.opacity(0.035), in: Circle())
                .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .padding(2).contentShape(Circle())
        }.buttonStyle(.plain).help("Add button \(side.title.lowercased())").accessibilityLabel("Add button \(side.title.lowercased())")
            .popover(isPresented: Binding(get: { adding == side }, set: { if !$0 { adding = nil } }), arrowEdge: edge(side)) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Add a button · \(side.title)").font(.system(size: 15, weight: .semibold))
                    ShortcutToolPicker(actions: unused) { action in
                        move(action, to: side); adding = nil
                    }
                }.padding(18).frame(width: 338).preferredColorScheme(.dark).orbitControls(store)
            }
    }
    private func editor(_ action: OrbitAction) -> some View {
        let side = options.shortcuts.first { $0.action == action }?.position ?? .left
        let siblings = options.actions(at: side), index = siblings.firstIndex(of: action) ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Edit button", systemImage: action.symbol).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { editing = nil } label: { Image(systemName: "xmark") }.buttonStyle(OrbitIconButtonStyle()).accessibilityLabel("Done editing button")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Button name").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(action.title, text: Binding(get: { options.shortcuts.first { $0.action == action }?.label ?? "" }, set: { name in
                    update { value in if let i = value.shortcuts.firstIndex(where: { $0.action == action }) { value.shortcuts[i].label = name } }
                })).textFieldStyle(OrbitTextFieldStyle()).accessibilityLabel("Button name")
            }
            HStack(spacing: 6) {
                ForEach(sides, id: \.self) { position in
                    Button(position.title) { move(action, to: position) }
                        .buttonStyle(OrbitButtonStyle(prominent: side == position))
                        .disabled(side != position && !options.hasRoom(at: position, moving: action))
                        .accessibilityValue(side == position ? "Selected" : "")
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button { update { $0.reorderShortcut(action, by: -1) } } label: { Label("Earlier", systemImage: side == .bottom ? "arrow.left" : "arrow.up") }.disabled(index == 0)
                Button { update { $0.reorderShortcut(action, by: 1) } } label: { Label("Later", systemImage: side == .bottom ? "arrow.right" : "arrow.down") }.disabled(index + 1 == siblings.count)
            }.buttonStyle(OrbitButtonStyle())
            Divider().opacity(0.3)
            Text("Action").font(.system(size: 11)).foregroundStyle(.secondary)
            ShortcutToolPicker(actions: NotchOptions.availableShortcuts.filter { $0 == action || unused.contains($0) }, selected: action) { replacement in
                guard replacement != action else { return }
                // Close the popover before its source button changes identity.
                editing = nil
                update { $0.replaceShortcut(action, with: replacement) }
            }
            Button(role: .destructive) { remove(action) } label: { Label("Remove button", systemImage: "minus.circle") }.buttonStyle(OrbitButtonStyle())
        }
    }
    private func edge(_ side: NotchShortcutPosition) -> Edge { side == .left ? .trailing : side == .right ? .leading : .top }
    private func move(_ action: OrbitAction, to side: NotchShortcutPosition, before next: OrbitAction? = nil) {
        guard options.hasRoom(at: side, moving: action) else { feedback = "\(side.title) is full. Move or remove a button first."; return }
        if next == nil, options.shortcuts.first(where: { $0.action == action })?.position == side { return }
        update { $0.moveShortcut(action, to: side, before: next) }; feedback = nil
    }
    private func remove(_ action: OrbitAction) { editing = nil; update { $0.moveShortcut(action, to: .hidden) }; feedback = "\(action.title) is available to add again with +" }
    private func drop(_ action: OrbitAction, at point: CGPoint, geometry: ShortcutEditorGeometry) {
        guard let side = sides.first(where: { geometry.dropZone($0).contains(point) }) else { return }
        guard options.hasRoom(at: side, moving: action) else { feedback = "\(side.title) is full. Move or remove a button first."; return }
        let siblings = options.actions(at: side).filter { $0 != action }
        let before = siblings.enumerated().first { index, _ in
            let center = geometry.point(index, count: siblings.count, side: side)
            if side == .bottom { return center.y > point.y + 16 || (abs(center.y - point.y) <= 16 && center.x > point.x) }
            return center.y > point.y
        }?.element
        update { $0.moveShortcut(action, to: side, before: before) }; feedback = nil
    }
    private func preview(_ geometry: ShortcutEditorGeometry) -> some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24)
        return VStack(spacing: 12) {
            Capsule().fill(.black).frame(width: min(100, geometry.body.width * 0.38), height: 10)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ForEach(["waveform", "timer", "sparkles"], id: \.self) { symbol in
                    Image(systemName: symbol).font(.system(size: 17, weight: .light)).foregroundStyle(.white.opacity(0.6))
                        .frame(width: 39, height: 39).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Text("Your tools, within reach.").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
        }.padding(14).frame(width: geometry.body.width, height: geometry.body.height)
            .orbitGlass(in: shape)
            .overlay(alignment: .top) { LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 38).clipShape(shape).allowsHitTesting(false) }
            .overlay(shape.strokeBorder(options.outlineEnabled ? options.outlineColor.swiftUI : .clear, lineWidth: options.outlineWidth))
            .position(x: geometry.body.midX, y: geometry.body.midY).accessibilityHidden(true)
    }
    private func resizeGrip(_ geometry: ShortcutEditorGeometry) -> some View {
        Image(systemName: "arrow.left.and.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.accentColor)
            .frame(width: 26, height: 26).background(.black.opacity(0.8), in: Circle()).overlay(Circle().strokeBorder(.white.opacity(0.2)))
            .contentShape(Circle()).help("Drag to resize the expanded notch")
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("orbit.shortcut.editor")).onChanged { value in
                if resizeStart == nil { resizeStart = store.configuration.notchWidth; resizeScale = geometry.scale }
                store.configuration.notchWidth = min(600, max(360, (resizeStart ?? 480) + value.translation.width * 2 / resizeScale))
            }.onEnded { _ in resizeStart = nil })
            .accessibilityHidden(true)
    }
}

private struct ShortcutEditorGeometry {
    let scale: CGFloat
    let body: CGRect
    init(width: CGFloat, notchWidth: Double) {
        scale = min(0.78, max(0.35, (width - 40) / (notchWidth + 144)))
        body = CGRect(x: (width - notchWidth * scale) / 2, y: 24, width: notchWidth * scale, height: 300 * scale)
    }
    func point(_ index: Int, count: Int, side: NotchShortcutPosition) -> CGPoint {
        if side == .bottom {
            let columns = max(1, min(6, count))
            return CGPoint(x: body.midX + (CGFloat(index % 6) - CGFloat(columns - 1) / 2) * 52 * scale, y: body.maxY + (32 + CGFloat(index / 6) * 52) * scale)
        }
        return CGPoint(x: side == .left ? body.minX - 32 * scale : body.maxX + 32 * scale, y: body.minY + (66 + CGFloat(index) * 52) * scale)
    }
    func dropZone(_ side: NotchShortcutPosition) -> CGRect {
        if side == .bottom { return CGRect(x: body.minX, y: body.maxY - 6, width: body.width, height: 116 * scale) }
        return CGRect(x: side == .left ? body.minX - 62 * scale : body.maxX, y: body.minY, width: 62 * scale, height: max(body.height, 354 * scale))
    }
}

private struct ShortcutToolPicker: View {
    let actions: [OrbitAction]
    var selected: OrbitAction?
    var choose: (OrbitAction) -> Void
    @State private var search = ""
    private var matches: [OrbitAction] { actions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 10) {
            TextField("Find a tool", text: $search).textFieldStyle(OrbitTextFieldStyle()).accessibilityLabel("Find a tool")
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(matches) { action in
                        Button { choose(action) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: action.symbol).foregroundStyle(action.toolColor).frame(width: 18)
                                Text(action.title).font(.system(size: 11)).lineLimit(2)
                                Spacer(minLength: 0)
                            }.padding(9).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                                .background(selected == action ? action.toolColor.opacity(0.15) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(action.title).accessibilityValue(selected == action ? "Selected" : "")
                    }
                }
                if matches.isEmpty { Text("No matching tools").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 28) }
            }.scrollIndicators(.never).frame(height: 198)
        }
    }
}
