import SwiftUI
import AppKit
import OrbitCore

struct NotchSettingsView: View {
    @ObservedObject var store: OrbitStore
    @State private var tab = "Layout"
    private var options: NotchOptions { store.configuration.notch }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SettingsToggleRow("Enable notch", isOn: $store.configuration.notchEnabled)
                Button("Preview notch") { store.previewNotch?() }.buttonStyle(OrbitButtonStyle(prominent: true)).disabled(!store.configuration.notchEnabled)
            }
            OrbitSegmentedPicker(selection: $tab, options: [("Layout", "Layout"), ("Look", "Look"), ("Behaviour", "Behaviour")])
            Group {
                switch tab {
                case "Layout": NotchShortcutEditor(store: store)
                case "Behaviour": behaviour
                default: appearance
                }
            }
        }
    }
    private var appearance: some View {
        VStack(spacing: 12) {
            OrbitCard { VStack(alignment: .leading, spacing: 16) {
                SettingHeading(title: "Make it yours", subtitle: "The same glass on the notch and every floating button.", symbol: "paintpalette")
                GlassAppearanceControls(store: store)
                Text("These are the shared Appearance settings: changes apply across Orbit. The camera area stays black.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider().opacity(0.3)
                SettingsToggleRow("Show outline", isOn: binding(\.outlineEnabled))
                Text("Outlines the notch and its floating shortcut buttons.").font(.system(size: 11)).foregroundStyle(.secondary)
                if options.outlineEnabled {
                    ColorPicker("Outline colour", selection: colorBinding(\.outlineColor), supportsOpacity: false).font(.system(size: 12))
                    SettingSlider(title: "Outline thickness", value: binding(\.outlineWidth), range: 0.5...3, unit: "pt")
                }
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Button("Compact") { store.configuration.notchWidth = 480 }.buttonStyle(OrbitButtonStyle())
                    Button("Spacious") { store.configuration.notchWidth = 560 }.buttonStyle(OrbitButtonStyle())
                    Spacer()
                }
                SettingSlider(title: "Expanded width", value: $store.configuration.notchWidth, range: 360...600, unit: "pt")
                Text("Idle matches the camera. On other displays it follows the menu bar. Timers, agents and music each fit their own activity wings; expanded width is independent.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Height follows the content. Only clipboard history uses the limit below.").font(.system(size: 11)).foregroundStyle(.secondary)
                SettingSlider(title: "Clipboard history height limit", value: $store.configuration.notchHeight, range: 300...620, unit: "pt")
            } }
        }
    }
    private var behaviour: some View {
        VStack(spacing: 12) {
            OrbitCard { VStack(alignment: .leading, spacing: 14) {
                SettingHeading(title: "Opening & placement", subtitle: "Choose when and where the notch appears.", symbol: "cursorarrow")
                SettingsToggleRow("Expand on hover", isOn: $store.configuration.notchHoverEnabled)
                Text("The top edge activates only within the notch’s width. Click to open when hover is off.").font(.system(size: 11)).foregroundStyle(.secondary)
                if store.configuration.notchHoverEnabled { SettingSlider(title: "Hover delay", value: $store.configuration.hoverDelay, range: 0.05...2, unit: "s") }
                SettingSlider(title: "Collapse delay", value: $store.configuration.collapseDelay, range: 0.15...3, unit: "s")
                SettingsToggleRow("Prefer built-in display", isOn: $store.configuration.notchOnlyOnBuiltIn)
                Text("Uses the built-in camera display when available; otherwise the active display. The panel stays centred along the top edge.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 14) {
                SettingHeading(title: "While it’s closed", subtitle: "Choose the live activity shown beside the camera.", symbol: "waveform.path")
                SettingsToggleRow("Allow activity over menu items", isOn: binding(\.allowActivityOverMenus))
                Text("Keeps live indicators visible without Accessibility access. Turn this off to give nearby menu items priority.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SettingsToggleRow("Animate activity icons", isOn: binding(\.animateActivityIcons))
                Text("Gentle motion for running activities and a brief bounce when something arrives. Paused timers stay still. Reduce Motion always takes priority.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider().opacity(0.3)
                SettingsToggleRow("Agent activity & completion", isOn: binding(\.showAgents))
                SettingsToggleRow("Timer countdown & completion", isOn: binding(\.showTimers))
                SettingsToggleRow("Now playing", isOn: binding(\.showMusic))
                SettingsToggleRow("Keep awake countdown", isOn: binding(\.showKeepAwake))
                SettingsToggleRow("Copied-item indicator", isOn: binding(\.showClipboard))
                SettingsToggleRow("Notification indicator", isOn: binding(\.showNotifications))
                Text("These switches change the compact display. Tools keep working in the wheel and menu bar.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("With several activities running, hover to choose a readout. You can pair a running timer with agents or music. Click the camera area to open your last tool, or a side indicator to open that activity.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !options.allowActivityOverMenus {
                    Text("Menu avoidance needs Accessibility access to check the space between menu items. Unknown or crowded space hides side indicators; the activity chooser and open tools still work.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button("Notification settings") { store.settingsTab = "Notifications" }.buttonStyle(OrbitButtonStyle())
            } }
        }
    }
    private func save(_ value: NotchOptions) { var value = value; value.normalize(); store.configuration.notchSettings = value }
    private func set<T>(_ key: WritableKeyPath<NotchOptions, T>, _ newValue: T) { var value = options; value[keyPath: key] = newValue; save(value) }
    private func binding<T>(_ key: WritableKeyPath<NotchOptions, T>) -> Binding<T> { Binding(get: { options[keyPath: key] }, set: { set(key, $0) }) }
    private func colorBinding(_ key: WritableKeyPath<NotchOptions, NotchColor>) -> Binding<Color> { Binding(get: { options[keyPath: key].swiftUI }, set: { set(key, NotchColor($0)) }) }
}
