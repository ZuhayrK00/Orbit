import SwiftUI
import AppKit
import OrbitCore

struct SettingsView: View {
    @ObservedObject var store: OrbitStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: store.settingsTab, subtitle: sectionDetail)
            Group {
                switch store.settingsTab {
                case "Controls": TriggerSettingsView(store: store)
                case "Appearance": AppearanceSettingsView(store: store)
                case "Notch": NotchSettingsView(store: store)
                case "Notifications": NotificationSettingsView(store: store, monitor: store.notifications)
                case "Timers": TimerSettingsView(store: store)
                case "Productivity": ProductivitySettingsView(store: store)
                case "Wheel": WheelSettingsView(store: store)
                case "Sound": OrbitCard { MixerPreferencesView(audio: store.audio) }
                case "Connections": ConnectionSettingsView(store: store)
                case "Permissions": PermissionsSettingsView(store: store, permissions: store.permissions)
                default: PrivacySettingsView(store: store)
                }
            }.id(store.settingsTab).transition(.opacity)
        }.animation(store.reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.settingsTab)
    }
    private var sectionDetail: String {
        switch store.settingsTab {
        case "Controls": return "Shortcuts, mouse gestures and ways to open Orbit."
        case "Appearance": return "Glass, colour and motion across Orbit."
        case "Notch": return "Your tools, your layout, your space at the top of the screen."
        case "Notifications": return "New Mac notifications, at a glance in your notch."
        case "Timers": return "Make your favourite durations one click away."
        case "Productivity": return "Files, clipboard, calendar and focus, close at hand."
        case "Wheel": return "Choose and arrange the actions around your cursor."
        case "Sound": return "App volumes, output routes and mixer preferences."
        case "Connections": return "Link your local agents and their activity."
        case "Permissions": return "Clear access, live status and help whenever you need it."
        default: return "Manage optional access and local data."
        }
    }

}
struct OrbitSegmentedPicker<Selection: Hashable>: View {
    @Binding var selection: Selection
    let options: [(String, Selection)]
    @Namespace private var selectionSpace
    @Environment(\.orbitReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index], selected = selection == option.1
                Button { withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { selection = option.1 } } label: {
                    Text(option.0).font(.system(size: 12, weight: selected ? .semibold : .medium)).foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background { if selected { RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.12)).matchedGeometryEffect(id: "selected", in: selectionSpace) } }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(selected ? "Selected" : "")
            }
        }.padding(3).background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct PermissionCard: View {
    @ObservedObject var store: OrbitStore
    @State private var surfaceID = UUID()
    var body: some View {
        OrbitCard {
            VStack(alignment: .leading, spacing: 14) {
                PermissionRow(permissions: store.permissions, kind: .accessibility)
                HStack {
                    Button("All permissions") { store.settingsTab = "Permissions"; store.openSettings?() }.buttonStyle(OrbitButtonStyle())
                    Spacer()
                    Button("Check access") { store.refreshPermissions(announce: true) }.buttonStyle(OrbitButtonStyle())
                }
            }
        }.onAppear { store.permissions.setVisible(surfaceID, true) }
            .onDisappear { store.permissions.setVisible(surfaceID, false) }
    }
}
struct TriggerSettingsView: View {
    @ObservedObject var store: OrbitStore
    @State private var logitechExpanded = false
    var body: some View {
        VStack(spacing: 12) {
            PermissionCard(store: store)
            OrbitCard { VStack(alignment: .leading, spacing: 12) {
                SettingsToggleRow("Text actions in the wheel", isOn: Binding(get: { store.configuration.contextualTextWheel ?? true }, set: { store.configuration.contextualTextWheel = $0 })).font(.system(size: 13, weight: .medium))
                Text("When you highlight text in a supported app, the wheel offers copy, case changes, clean links and search. Your tools are still one click away. Selection stays on this Mac unless you choose Search web.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 14) {
                HStack { SettingHeading(title: "Keyboard", subtitle: "Open or hold the wheel with a key combination.", symbol: "keyboard"); Toggle("Keyboard shortcut", isOn: $store.configuration.keyboardEnabled).labelsHidden() }
                HStack {
                    Text(store.keyboardRecording ? "Press your shortcut…" : store.configuration.keyboardLabel).font(.system(size: 15, weight: .medium, design: .monospaced)).padding(.horizontal, 16).padding(.vertical, 8).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    Spacer(); Button(store.keyboardRecording ? "Cancel" : "Record shortcut") { store.keyboardRecording.toggle() }.buttonStyle(OrbitButtonStyle())
                }
                OrbitSegmentedPicker(selection: $store.configuration.keyboardBehavior, options: [("Press to toggle", .toggle), ("Hold & release", .hold)])
                Text(store.keyboardRecording ? "Include Control, Option or Command. Escape cancels." : store.triggerStatus).font(.system(size: 11)).foregroundStyle(.secondary)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 14) {
                HStack { SettingHeading(title: "Mouse", subtitle: "Hold a button, move to an action, release.", symbol: "computermouse"); Toggle("Mouse button", isOn: $store.configuration.mouseEnabled).labelsHidden() }
                HStack {
                    OrbitMenuPicker(title: "Mouse button", selection: $store.configuration.mouseButton, options: [("Left button", 0), ("Right button", 1), ("Middle button", 2)] + (3..<32).map { ("Button \($0 + 1)", $0) }).frame(maxWidth: 220)
                    Spacer(); Button(store.mouseRecording ? "Cancel" : "Record button") { store.mouseRecording.toggle() }.buttonStyle(OrbitButtonStyle())
                }
                if store.mouseRecording { Text("Press a side or middle button. Escape cancels. Choose left click from the menu to avoid recording the Cancel button.").font(.system(size: 11)).foregroundStyle(.secondary) }
                OrbitSegmentedPicker(selection: $store.configuration.mouseBehavior, options: [("Hold & release", .hold), ("Hold to toggle", .toggle)])
                SettingSlider(title: "Hold delay", value: $store.configuration.mouseHoldDelay, range: 0.05...1.5, unit: "s")
                SettingsToggleRow("Reserve held button for Orbit", isOn: $store.configuration.consumeMouseButton).font(.system(size: 12))
                DisclosureGroup("Using a Logitech gesture button?", isExpanded: $logitechExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("In Logi Options+, select your mouse → Global settings → Gestures → Custom → Click → Keyboard shortcut. Record \(store.configuration.keyboardLabel) using your physical keyboard.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                        Text("Then use shortcut toggle below. Logitech sends the shortcut on a click; directional gestures can keep their existing actions.").font(.system(size: 11)).foregroundStyle(.secondary)
                        HStack { Button("Open Logi Options+") { openLogitech() }.buttonStyle(OrbitButtonStyle()); Button("Use shortcut toggle") { store.configuration.keyboardBehavior = .toggle; store.configuration.keyboardEnabled = true; store.configuration.mouseEnabled = false; store.message("Orbit is ready for your Logitech shortcut") }.buttonStyle(OrbitButtonStyle(prominent: true)) }
                    }.padding(.top, 12)
                }.font(.system(size: 12, weight: .medium))
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 14) {
                SettingHeading(title: "Always within reach", subtitle: "Choose where Orbit lives.", symbol: "macwindow")
                SettingsToggleRow("Menu bar", isOn: $store.configuration.menuBarEnabled)
                Button("Notch settings") { store.settingsTab = "Notch" }.buttonStyle(OrbitButtonStyle())
                SettingsToggleRow("Launch at login", isOn: Binding(get: { store.configuration.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                Button("Run quick setup again") { store.startOnboarding() }.buttonStyle(OrbitButtonStyle())
            } }
        }
    }
    private func openLogitech() {
        let application = URL(fileURLWithPath: "/Applications/logioptionsplus.app")
        if FileManager.default.fileExists(atPath: application.path) { NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration()) }
        else { store.message("Open your mouse software and assign Orbit’s shortcut") }
    }
}
struct SettingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    private var readout: String {
        if unit == "s" { return String(format: "%.2f s", value) }
        if unit == "pt", range.upperBound <= 3 { return String(format: "%.1f pt", value) }
        return "\(Int(value)) \(unit)"
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack { Text(title).font(.system(size: 12, weight: .medium)); Spacer(); Text(readout).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 4).background(Color.primary.opacity(0.035), in: Capsule()) }
            Slider(value: $value, in: range).controlSize(.small).accessibilityLabel(title)
        }
    }
}
struct AppearanceSettingsView: View {
    @ObservedObject var store: OrbitStore
    var body: some View {
        VStack(spacing: 12) {
            OrbitCard { VStack(alignment: .leading, spacing: 16) {
                SettingHeading(title: "Liquid Glass", subtitle: "One finish for your notch, wheel, menu bar and settings.", symbol: "drop.halffull")
                GlassAppearanceControls(store: store)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 14) {
                SettingHeading(title: "The wheel", subtitle: "Size and colour of the radial controls.", symbol: "circle.hexagongrid")
                SettingSlider(title: "Size", value: $store.configuration.wheelDiameter, range: 340...680, unit: "pt")
                SettingSlider(title: "Wheel opacity", value: Binding(get: { store.configuration.wheelOpacity * 100 }, set: { store.configuration.wheelOpacity = $0 / 100 }), range: 65...100, unit: "%")
                HStack(spacing: 14) {
                    Text("Accent").font(.system(size: 12, weight: .medium)); Spacer()
                    ForEach(Accent.allCases, id: \.self) { accent in
                        Button { store.configuration.accent = accent } label: { Circle().fill(OrbitDesign.accent(accent).gradient).frame(width: 27, height: 27).overlay { if store.configuration.accent == accent { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) } }.padding(4).background(Color.primary.opacity(store.configuration.accent == accent ? 0.06 : 0), in: Circle()) }.buttonStyle(.plain).accessibilityLabel(accent.rawValue.capitalized)
                    }
                }
                SettingsToggleRow("Reduce animation", isOn: $store.configuration.reducedMotion).font(.system(size: 12))
                Button("Preview wheel") { store.openWheel?() }.buttonStyle(OrbitButtonStyle())
            } }

        }
    }
}
struct GlassAppearanceControls: View {
    @ObservedObject var store: OrbitStore
    private let swatches: [(String, NotchColor)] = [
        ("Black", .black), ("Graphite", .init(0.7, 0.7, 0.75)), ("Midnight", .init(0.25, 0.5, 1)),
        ("Plum", .init(0.7, 0.35, 0.9)), ("Forest", .init(0.2, 0.75, 0.5)), ("Ember", .init(1, 0.4, 0.25))
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Glass colour").font(.system(size: 12, weight: .medium))
            HStack(spacing: 8) {
                ForEach(swatches, id: \.0) { name, color in
                    Button { store.configuration.glassColor = color } label: {
                        Circle().fill(color.glassShade.swiftUI).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                            .overlay { if store.configuration.effectiveGlassColor == color {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            } }
                            .frame(width: 36, height: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Glass colour: \(name)")
                        .accessibilityValue(store.configuration.effectiveGlassColor == color ? "Selected" : "").help(name)
                }
                Spacer(minLength: 4)
                ColorPicker("Custom glass colour", selection: Binding(get: { store.configuration.effectiveGlassColor.swiftUI }, set: { store.configuration.glassColor = NotchColor($0) }), supportsOpacity: false)
                    .labelsHidden().accessibilityLabel("Custom glass colour")
            }
            SettingSlider(title: "Glass transparency", value: Binding(get: { store.configuration.effectiveGlassTransparency * 100 }, set: { store.configuration.glassTransparency = $0 / 100 }), range: 15...90, unit: "%")
            Text("Colour and transparency apply to every glass surface and button, including the shortcuts outside the notch. Higher transparency lets more of your desktop through; text stays clear. macOS Reduce Transparency takes priority.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
struct WheelSettingsView: View {
    @ObservedObject var store: OrbitStore
    private var options: WheelOptions { store.configuration.wheel }
    private func binding<T>(_ key: WritableKeyPath<WheelOptions, T>) -> Binding<T> {
        Binding(get: { options[keyPath: key] }, set: { value in
            var updated = options; updated[keyPath: key] = value; updated.normalize(); store.configuration.wheelSettings = updated
        })
    }
    var body: some View {
        VStack(spacing: 12) {
            WheelProfilesSettingsView(store: store)
            HStack(spacing: 24) {
                WheelView(store: store, preview: true).frame(width: 300, height: 300)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your favourites.\nOne gesture away.").font(.system(size: 23, weight: .semibold)).tracking(-0.5)
                    Text("Keep 4–12 actions in your wheel. Add your apps, links and Shortcuts.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    Button("Try your wheel") { store.openWheel?() }.buttonStyle(OrbitButtonStyle(prominent: true))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 5)
            OrbitCard { VStack(alignment: .leading, spacing: 8) {
                SettingsToggleRow("Show labels under icons", isOn: binding(\.showLabels))
                Text("Turn off for an icon-only wheel. The centre label stays visible and names the action you hover over.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 14) {
                SettingHeading(title: "Opening & navigation", subtitle: "Choose where the wheel lives and how it behaves.", symbol: "cursorarrow.rays")
                OrbitSegmentedPicker(selection: binding(\.placement), options: [("At pointer", .pointer), ("Screen centre", .screenCenter)])
                SettingsToggleRow("Click outside to close", isOn: binding(\.dismissOnOutsideClick))
                SettingsToggleRow("Escape returns to the wheel first", isOn: binding(\.escapeReturnsToWheel))
                Text("File Tools stays open for dragging from Finder. Pin any other tool to keep it open. Back returns to your wheel; × closes it.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Keyboard & mouse triggers") { store.settingsTab = "Controls" }.buttonStyle(OrbitButtonStyle())
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 14) {
                SettingHeading(title: "Shape & motion", subtitle: "A wheel that opens into your tools.", symbol: "circle.square")
                SettingSlider(title: "Wheel size", value: $store.configuration.wheelDiameter, range: 340...680, unit: "pt")
                SettingSlider(title: "Tool width", value: binding(\.toolWidth), range: 400...600, unit: "pt")
                SettingSlider(title: "Wheel opacity", value: Binding(get: { store.configuration.wheelOpacity * 100 }, set: { store.configuration.wheelOpacity = $0 / 100 }), range: 65...100, unit: "%")
                SettingsToggleRow("Animate opening and tool transitions", isOn: binding(\.animate))
                Text("Tool height follows its content. Long pages scroll only when they reach the screen limit. Reduce Motion takes priority over animations.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } }
            ForEach(Array(store.configuration.slots.enumerated()), id: \.element.id) { index, slot in
                OrbitCard { VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: slot.action.symbol).font(.system(size: 18, weight: .light)).foregroundStyle(OrbitDesign.accent(store.configuration.accent)).frame(width: 28)
                        TextField("Action label", text: Binding(get: { store.configuration.slots[safe: index]?.label ?? "" }, set: { if store.configuration.slots.indices.contains(index) { store.configuration.slots[index].label = String($0.prefix(36)) } })).textFieldStyle(OrbitTextFieldStyle())
                        OrbitMenuPicker(title: "Action", selection: Binding(get: { store.configuration.slots[safe: index]?.action ?? .files }, set: { action in if store.configuration.slots.indices.contains(index) { store.configuration.slots[index].action = action; store.configuration.slots[index].label = action.title; store.configuration.slots[index].argument = "" } }), options: OrbitAction.allCases.map { ($0.title, $0) }).frame(width: 155)
                        Button { if index > 0 { store.configuration.slots.swapAt(index, index - 1) } } label: { Image(systemName: "chevron.up") }.buttonStyle(OrbitIconButtonStyle()).disabled(index == 0).help("Move earlier")
                        Button { if index < store.configuration.slots.count - 1 { store.configuration.slots.swapAt(index, index + 1) } } label: { Image(systemName: "chevron.down") }.buttonStyle(OrbitIconButtonStyle()).disabled(index == store.configuration.slots.count - 1).help("Move later")
                        Button { store.configuration.slots.remove(at: index) } label: { Image(systemName: "minus") }.buttonStyle(OrbitIconButtonStyle()).disabled(store.configuration.slots.count <= 4).help("Remove action")
                    }
                    if slot.action == .wheelProfile {
                        Picker("Submenu profile", selection: Binding(get: { store.configuration.slots[safe: index]?.argument ?? "" }, set: { if store.configuration.slots.indices.contains(index) { store.configuration.slots[index].argument = $0 } })) { Text("Choose…").tag(""); ForEach(store.configuration.wheelProfiles ?? []) { Text($0.name).tag($0.id.uuidString) } }
                    }
                    if [.openURL, .openApp, .shortcut].contains(slot.action) {
                        HStack {
                            TextField(slot.action == .openURL ? "https://example.com" : slot.action == .openApp ? "App identifier or .app path" : "Apple Shortcut name", text: Binding(get: { store.configuration.slots[safe: index]?.argument ?? "" }, set: { if store.configuration.slots.indices.contains(index) { store.configuration.slots[index].argument = $0 } })).textFieldStyle(OrbitTextFieldStyle())
                            if slot.action == .openApp { Button("Choose app") { chooseApp(index: index) }.buttonStyle(OrbitButtonStyle()) }
                        }
                    }
                } }
            }
            HStack {
                Button { store.configuration.slots.append(WheelSlot(action: .shortcut)) } label: { Label("Add action", systemImage: "plus") }.buttonStyle(OrbitButtonStyle(prominent: true)).disabled(store.configuration.slots.count >= 12)
                Spacer(); Button("Restore defaults") { store.configuration.slots = OrbitConfiguration().slots }.buttonStyle(OrbitButtonStyle())
            }
        }
    }
    private func chooseApp(index: Int) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.prompt = "Choose app"
        if panel.runModal() == .OK, let url = panel.url, store.configuration.slots.indices.contains(index) { store.configuration.slots[index].argument = url.path; store.configuration.slots[index].label = url.deletingPathExtension().lastPathComponent }
    }
}
struct PrivacySettingsView: View {
    @ObservedObject var store: OrbitStore
    @State private var confirmReset = false
    var body: some View {
        VStack(spacing: 12) {
            PermissionCard(store: store)
            OrbitCard { VStack(alignment: .leading, spacing: 14) {
                SettingHeading(title: "Private by design", subtitle: "Your files and settings stay on this Mac.", symbol: "lock.shield")
                SettingsToggleRow("Keep clipboard history", isOn: $store.configuration.clipboardEnabled)
                if store.configuration.clipboardEnabled { Stepper("Keep \(store.configuration.clipboardLimit) entries", value: $store.configuration.clipboardLimit, in: 5...100) }
                Text("History can stay for this session or persist locally. Choose storage and excluded apps in Productivity settings. Apps do not always mark sensitive content.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                Divider().opacity(0.4)
                SettingsToggleRow("Music & Spotify controls", isOn: $store.configuration.mediaEnabled)
                Text("macOS asks for Automation permission when connecting to a player.").font(.system(size: 11)).foregroundStyle(.secondary)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 12) {
                SettingHeading(title: "Your settings", subtitle: "Take your Orbit with you.", symbol: "slider.horizontal.3")
                HStack { Button("Export") { export() }.buttonStyle(OrbitButtonStyle()); Button("Import") { importSettings() }.buttonStyle(OrbitButtonStyle()); Spacer(); Button("Open local data") { NSWorkspace.shared.open(OrbitPaths.support) }.buttonStyle(OrbitButtonStyle()) }
                Divider().opacity(0.4)
                HStack { Button("Quick setup") { store.startOnboarding() }.buttonStyle(OrbitButtonStyle()); Spacer(); Button("Reset settings") { confirmReset = true }.font(.system(size: 12)).foregroundStyle(.secondary).buttonStyle(.plain) }
            } }
            Text("Free to use. No accounts, ads, analytics or paid model calls.").font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }.confirmationDialog("Restore Orbit's default settings?", isPresented: $confirmReset) { Button("Reset settings", role: .destructive) { store.reset() } }
    }
    private func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Orbit settings.json"
        if panel.runModal() == .OK, let url = panel.url { do { try ConfigurationIO.save(store.configuration, to: url); store.message("Settings exported") } catch { store.error = error.localizedDescription } }
    }
    private func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { do { store.configuration = try ConfigurationIO.load(from: url); store.message("Settings imported") } catch { store.error = "This file is not a valid Orbit settings export." } }
    }
}
extension Collection { subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil } }

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; self._isOn = isOn }
    var body: some View {
        HStack {
            Text(title).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn).labelsHidden().accessibilityLabel(title)
        }
    }
}
