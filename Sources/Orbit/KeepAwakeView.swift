import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OrbitCore

struct KeepAwakeView: View {
    @ObservedObject var session: AwakeSession
    @ObservedObject var store: OrbitStore
    var compact: Bool
    @State private var minutes = 30
    @State private var useEndTime = false
    @State private var endTime = Date().addingTimeInterval(3600)
    @State private var showsAutomation = false
    private func option<Value>(_ key: WritableKeyPath<AwakeOptions, Value>) -> Binding<Value> {
        Binding(get: { store.configuration.awake[keyPath: key] }, set: {
            var options = store.configuration.awake; options[keyPath: key] = $0; options.normalize()
            store.configuration.awakeSettings = options
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OrbitCard { VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Until agents finish").font(.system(size: 12, weight: .semibold)); Spacer(); Button(store.agentAwake.active ? "Stop" : "Start") { if store.agentAwake.active { store.agentAwake.stop() } else { store.agentAwake.start(store.agents) } }.buttonStyle(OrbitButtonStyle()).disabled(!store.agentAwake.active && store.activeAgents.isEmpty) }
                Text(store.agentAwake.detail).font(.system(size: 10)).foregroundStyle(.secondary)
            } }
            if showsAutomation { automation }
            else { controls }
            if let error = session.error ?? session.lid.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private var controls: some View {
        VStack(spacing: 12) {
            OrbitCard {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: session.active ? "cup.and.saucer.fill" : "cup.and.saucer")
                            .font(.system(size: 25, weight: .regular)).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.paused ? "Paused while locked" : session.active ? "Keeping awake" : "Ready when you are")
                                .font(.system(size: 14, weight: .medium))
                            Text(session.automatic ? "Started by automation" : session.active ? "Until you stop it or the time runs out" : "For downloads, work and everything in between")
                                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        if session.active {
                            Text(session.until.map { NotchLayout.compactDuration($0.timeIntervalSince(max(store.now, Date()))) } ?? "∞")
                                .font(.system(size: 24, weight: .light)).monospacedDigit().foregroundStyle(.orange)
                        }
                    }
                    if !session.active {
                        OrbitSegmentedPicker(selection: $minutes, options: [("15m", 15), ("30m", 30), ("1h", 60), ("2h", 120), ("∞", 0)])
                            .disabled(useEndTime).opacity(useEndTime ? 0.45 : 1)
                        HStack {
                            Button(useEndTime ? "Use duration" : "Until a time…") { useEndTime.toggle() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            if useEndTime { DatePicker("End at", selection: $endTime, displayedComponents: .hourAndMinute).labelsHidden().datePickerStyle(.field).fixedSize() }
                        }
                    }
                    Button(session.active ? "End session" : "Keep awake") {
                        if session.active { session.stop() }
                        else if useEndTime { session.start(until: AwakeTiming.nextEndTime(endTime, now: Date())) }
                        else { session.start(minutes: minutes == 0 ? nil : minutes) }
                    }.buttonStyle(OrbitButtonStyle(prominent: true))
                }
            }
            OrbitCard {
                VStack(spacing: 12) {
                    row("Allow the display to sleep", symbol: "display", value: option(\.allowDisplaySleep))
                    row("Keep awake when Orbit opens", symbol: "power", value: option(\.startOnLaunch))
                    Button { showsAutomation = true } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "bolt.fill").frame(width: 18).foregroundStyle(.secondary)
                            Text("Automation")
                            Spacer()
                            Text(store.configuration.awake.automationEnabled ? "On" : "Off").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        }.font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, minHeight: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    row("Move pointer slightly", symbol: "cursorarrow.motionlines", value: option(\.movePointer))
                    if store.configuration.awake.movePointer {
                        HStack {
                            Text("Interval").foregroundStyle(.secondary)
                            Spacer()
                            Picker("Pointer interval", selection: option(\.pointerInterval)) {
                                Text("15 sec").tag(15); Text("30 sec").tag(30); Text("1 min").tag(60); Text("2 min").tag(120); Text("5 min").tag(300)
                            }.labelsHidden().fixedSize()
                        }.font(.system(size: 11))
                        if !store.inputPermission {
                            Button("Allow Accessibility for pointer movement") { store.requestAccessibility() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.orange)
                        }
                    }
                    Divider().opacity(0.35)
                    row("Keep going with the lid closed", symbol: "laptopcomputer", value: Binding(get: { session.lid.enabled }, set: {
                        if $0 { session.lid.start(until: session.until, batteryCutoff: store.configuration.awake.batteryCutoff) }
                        else { session.lid.stop() }
                    })).disabled(!session.active || session.paused || session.lid.state == .restoring || session.lid.needsRecovery)
                    if session.lid.needsRecovery {
                        Button("Restore normal sleep…") { session.lid.recover() }.buttonStyle(OrbitButtonStyle(prominent: true))
                        Text("A previous closed-lid session was interrupted. Restore sleep before starting another.")
                            .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(session.active ? session.lid.status : "Start a session to enable closed-lid mode.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private var automation: some View {
        VStack(spacing: 12) {
            HStack {
                Button { showsAutomation = false } label: { Label("Keep awake", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
            }.font(.system(size: 12, weight: .medium))
            OrbitCard {
                VStack(spacing: 12) {
                    row("Start automatically", symbol: "bolt.fill", value: option(\.automationEnabled))
                    OrbitSegmentedPicker(selection: option(\.requireAll), options: [("Any condition", false), ("All conditions", true)])
                    row("Connected to power", symbol: "powerplug", value: option(\.onPower))
                    row("External display connected", symbol: "display.2", value: option(\.externalDisplay))
                    row("Selected apps are running", symbol: "app.badge", value: option(\.runningApps))
                    if store.configuration.awake.runningApps {
                        HStack {
                            Button("Choose apps…", action: chooseApps).buttonStyle(OrbitButtonStyle())
                            Spacer()
                            if !store.configuration.awake.apps.isEmpty {
                                Menu("\(store.configuration.awake.apps.count) selected") {
                                    ForEach(store.configuration.awake.apps) { app in
                                        Button("Remove \(app.name)") { var options = store.configuration.awake; options.apps.removeAll { $0.id == app.id }; store.configuration.awakeSettings = options }
                                    }
                                }.fixedSize()
                            }
                        }
                    }
                    Text("Automation ends when the conditions stop matching. Ending a session yourself pauses automation until those conditions clear.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            OrbitCard {
                VStack(spacing: 12) {
                    row("Pause when locked", symbol: "lock", value: option(\.pauseWhenLocked))
                    HStack {
                        Label("Stop on low battery", systemImage: "battery.25percent").font(.system(size: 12))
                        Spacer()
                        Picker("Battery limit", selection: option(\.batteryCutoff)) {
                            ForEach([5, 10, 15, 20, 25, 30, 40, 50], id: \.self) { Text("\($0)%").tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                    Text("Pointer movement and closed-lid mode always pause when your Mac locks.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func row(_ title: String, symbol: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            SettingsToggleRow(title, isOn: value).font(.system(size: 12, weight: .medium))
        }
    }
    private func chooseApps() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.prompt = "Choose apps"
        guard panel.runModal() == .OK else { return }
        var options = store.configuration.awake
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier { options.apps.append(AwakeApp(id: id, name: url.deletingPathExtension().lastPathComponent)) }
        }
        options.normalize(); store.configuration.awakeSettings = options
    }
}
