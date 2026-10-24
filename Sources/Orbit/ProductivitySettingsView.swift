import SwiftUI
import AppKit
import OrbitCore

struct ProductivitySettingsView: View {
    @ObservedObject var store: OrbitStore
    private func toggle(_ key: WritableKeyPath<ProductivityOptions, Bool?>) -> Binding<Bool> { Binding(get: { store.configuration.productivity[keyPath: key] == true }, set: { value in store.editProductivity { $0[keyPath: key] = value } }) }
    private func number(_ key: WritableKeyPath<ProductivityOptions, Int?>, fallback: Int) -> Binding<Int> { Binding(get: { store.configuration.productivity[keyPath: key] ?? fallback }, set: { value in store.editProductivity { $0[keyPath: key] = value } }) }
    private func apps(_ key: WritableKeyPath<ProductivityOptions, [String]?>) -> Binding<String> { Binding(get: { (store.configuration.productivity[keyPath: key] ?? []).joined(separator: ", ") }, set: { value in store.editProductivity { $0[keyPath: key] = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } }) }
    var body: some View {
        VStack(spacing: 12) {
            OrbitCard { VStack(alignment: .leading, spacing: 12) {
                SettingHeading(title: "Notch Home", subtitle: "Music, agents, files and your agenda in one place.", symbol: "square.grid.2x2")
                SettingsToggleRow("Open Home when expanding the notch", isOn: toggle(\.homeOnOpen))
                Text("Turning this off returns to your remembered tool. You can also choose Home from any tool menu.").font(.system(size: 11)).foregroundStyle(.secondary)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 12) {
                SettingHeading(title: "Clipboard", subtitle: "Text, images, files, previews and pinned favourites.", symbol: "clipboard")
                SettingsToggleRow("Keep clipboard history", isOn: $store.configuration.clipboardEnabled)
                SettingsToggleRow("Save history across restarts", isOn: toggle(\.clipboardPersistence))
                Stepper("Keep \(store.configuration.clipboardLimit) recent items, plus pins", value: $store.configuration.clipboardLimit, in: 5...100)
                TextField("Excluded app bundle IDs, separated by commas", text: apps(\.clipboardExcludedApps)).textFieldStyle(OrbitTextFieldStyle())
                Text("Concealed, transient and generated clipboard content is skipped. Images use a private local cache. Unless saving is enabled, history is removed when Orbit exits. Apps do not always mark sensitive content.").font(.system(size: 11)).foregroundStyle(.secondary)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 12) {
                SettingHeading(title: "Downloads", subtitle: "Show transfers and completed files in the notch.", symbol: "arrow.down.circle")
                SettingsToggleRow("Watch downloads", isOn: toggle(\.downloadsEnabled))
                HStack { Text(store.configuration.productivity.downloadFolder ?? "~/Downloads").font(.system(size: 11)).lineLimit(1).truncationMode(.middle); Spacer(); Button("Choose folder…") { let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; if panel.runModal() == .OK, let url = panel.url { store.editProductivity { $0.downloadFolder = url.path } } }.buttonStyle(OrbitButtonStyle()) }
                Text("Safari, Chromium and Firefox temporary download files are detected. A percentage appears only when the browser publishes a total; other transfers show bytes received.").font(.system(size: 11)).foregroundStyle(.secondary)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 12) {
                SettingHeading(title: "Calendar & meetings", subtitle: "A local, read-only agenda with recognised meeting links.", symbol: "calendar")
                SettingsToggleRow("Show calendar events", isOn: toggle(\.calendarEnabled))
                Button(store.calendar.allowed ? "Refresh calendars" : store.calendar.accessButtonTitle) { if store.calendar.allowed { store.calendar.refresh(force: true) } else { store.calendar.requestAccess() } }.buttonStyle(OrbitButtonStyle()).disabled(store.calendar.requestingAccess)
                ForEach(store.calendar.calendars, id: \.id) { calendar in
                    Toggle(calendar.title, isOn: Binding(get: { let ids = store.configuration.productivity.calendarIDs ?? []; return ids.isEmpty || ids.contains(calendar.id) }, set: { value in
                        store.editProductivity { options in var ids = options.calendarIDs ?? []; if ids.isEmpty { ids = store.calendar.calendars.map(\.id) }; ids.removeAll { $0 == calendar.id }; if value { ids.append(calendar.id) }; options.calendarIDs = ids.isEmpty ? ["none"] : ids }
                    }))
                }
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 12) {
                SettingHeading(title: "Focus cycles", subtitle: "Pomodoro durations and long breaks.", symbol: "timer")
                Stepper("Focus: \(store.configuration.productivity.focusMinutes ?? 25) min", value: number(\.focusMinutes, fallback: 25), in: 1...180)
                Stepper("Break: \(store.configuration.productivity.breakMinutes ?? 5) min", value: number(\.breakMinutes, fallback: 5), in: 1...60)
                Stepper("Long break: \(store.configuration.productivity.longBreakMinutes ?? 15) min", value: number(\.longBreakMinutes, fallback: 15), in: 1...120)
                Stepper("Long break every \(store.configuration.productivity.focusRounds ?? 4) rounds", value: number(\.focusRounds, fallback: 4), in: 2...12)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 12) {
                SettingHeading(title: "Actions beside selected text", subtitle: "A small Orbit palette appears after selecting text.", symbol: "cursorarrow.rays")
                SettingsToggleRow("Show selection actions", isOn: toggle(\.selectionActionsEnabled))
                TextField("Excluded app bundle IDs, separated by commas", text: apps(\.selectionExcludedApps)).textFieldStyle(OrbitTextFieldStyle())
                Text("Uses Accessibility. Secure fields are excluded. Copy and transformations stay local; Search opens your chosen text in a browser only when clicked.").font(.system(size: 11)).foregroundStyle(.secondary)
            } }
            OrbitCard { VStack(alignment: .leading, spacing: 12) {
                SettingHeading(title: "Logitech gesture button", subtitle: "Recognise a gesture button that arrives as a keyboard chord.", symbol: "computermouse")
                SettingsToggleRow("Enable gesture chord", isOn: toggle(\.gestureChordEnabled))
                HStack { Text(store.configuration.productivity.gestureLabel ?? "⌃⌥Tab").font(.system(size: 12)); Spacer(); Button(store.recordingGesture ? "Cancel recording" : "Record gesture chord") { store.recordingGesture.toggle() }.buttonStyle(OrbitButtonStyle()) }
                Text("Press your MX Master’s gesture button while recording. If Options+ remaps it, assign a keyboard shortcut there and record that chord here. Recognition cannot identify which physical device sent the chord.").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(store.triggerStatus).font(.system(size: 10)).foregroundStyle(.secondary)
            } }
        }
    }
}

struct WheelProfilesSettingsView: View {
    @ObservedObject var store: OrbitStore
    @State private var selected: UUID?
    private var profiles: [WheelProfile] { store.configuration.wheelProfiles ?? [] }
    private func change(_ id: UUID, _ edit: (inout WheelProfile) -> Void) { var list = profiles; guard let i = list.firstIndex(where: { $0.id == id }) else { return }; edit(&list[i]); list[i].normalize(); store.configuration.wheelProfiles = list }
    var body: some View {
        OrbitCard { VStack(alignment: .leading, spacing: 12) {
            SettingHeading(title: "Wheel profiles & submenus", subtitle: "Separate wheels for different jobs, with independent shortcuts.", symbol: "circle.hexagongrid")
            HStack { Menu(profiles.first { $0.id == selected }?.name ?? "Choose a profile") { ForEach(profiles) { profile in Button(profile.name) { selected = profile.id } } }; Spacer(); Button("Add profile") { var list = profiles; let profile = WheelProfile(name: "New profile", actions: [.home, .shelf, .calendar, .timer]); list.append(profile); store.configuration.wheelProfiles = list; selected = profile.id }.disabled(profiles.count >= 12) }
            if profiles.isEmpty { Button("Add Work, Media & Files profiles") { store.configuration.wheelProfiles = WheelProfile.starters; selected = store.configuration.wheelProfiles?.first?.id }.buttonStyle(OrbitButtonStyle(prominent: true)) }
            if let profile = profiles.first(where: { $0.id == selected }) {
                TextField("Profile name", text: Binding(get: { profiles.first { $0.id == profile.id }?.name ?? "" }, set: { value in change(profile.id) { $0.name = value } })).textFieldStyle(OrbitTextFieldStyle())
                HStack { Button("Open profile") { store.openProfile(profile.id) }; Button(store.recordingProfile == profile.id ? "Press a shortcut…" : profile.shortcutLabel ?? "Record shortcut") { store.recordingProfile = store.recordingProfile == profile.id ? nil : profile.id }; Button("Clear shortcut") { change(profile.id) { $0.keyCode = nil; $0.modifiers = nil; $0.shortcutLabel = nil } } }.buttonStyle(OrbitButtonStyle())
                ForEach(Array(profile.slots.enumerated()), id: \.element.id) { i, slot in
                    VStack(spacing: 8) {
                        HStack { TextField("Label", text: Binding(get: { profiles.first { $0.id == profile.id }?.slots[safe: i]?.label ?? "" }, set: { value in change(profile.id) { $0.slots[i].label = value } })).textFieldStyle(OrbitTextFieldStyle()); Picker("Action", selection: Binding(get: { profiles.first { $0.id == profile.id }?.slots[safe: i]?.action ?? .home }, set: { action in change(profile.id) { $0.slots[i].action = action; $0.slots[i].label = action.title } })) { ForEach(OrbitAction.allCases) { Text($0.title).tag($0) } }.labelsHidden(); Button { change(profile.id) { $0.slots.remove(at: i) } } label: { Image(systemName: "minus") }.disabled(profile.slots.count <= 4) }
                        if slot.action == .wheelProfile { Picker("Submenu", selection: Binding(get: { profiles.first { $0.id == profile.id }?.slots[safe: i]?.argument ?? "" }, set: { value in change(profile.id) { $0.slots[i].argument = value } })) { Text("Choose…").tag(""); ForEach(profiles.filter { $0.id != profile.id }) { Text($0.name).tag($0.id.uuidString) } } }
                        else if [.openURL, .openApp, .shortcut].contains(slot.action) { TextField("URL, app path / bundle ID, or Shortcut name", text: Binding(get: { profiles.first { $0.id == profile.id }?.slots[safe: i]?.argument ?? "" }, set: { value in change(profile.id) { $0.slots[i].argument = value } })).textFieldStyle(OrbitTextFieldStyle()) }
                    }
                }
                HStack { Button("Add action") { change(profile.id) { $0.slots.append(.init(action: .home)) } }.disabled(profile.slots.count >= 12); Spacer(); Button("Remove profile") { store.configuration.wheelProfiles = profiles.filter { $0.id != profile.id }; selected = nil } }.buttonStyle(OrbitButtonStyle())
            }
        } }
    }
}
