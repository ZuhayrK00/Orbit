import AppKit
import SwiftUI
import OrbitCore

struct SoundView: View {
    @ObservedObject var audio: AudioService
    var compact: Bool
    @State private var showOptions = false
    @Environment(\.orbitReduceMotion) private var reduceMotion
    @Environment(\.orbitSurface) private var surface
    @Environment(\.notchToolBudget) private var budget
    private var showsMicrophone: Bool { audio.options.showMicrophone && audio.microphone != nil }
    private var appListHeight: Double {
        // Keep device controls in place; only the app list needs to scroll.
        let limit = surface == .floating ? 132.0 : surface == .notch ? min(228, max(44, budget - (showsMicrophone ? 172 : 130))) : 228
        return min(limit, max(40, Double(audio.visibleApps.count) * 44 - 4))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "hifispeaker.fill").foregroundStyle(.secondary)
                OrbitMenuPicker(title: "Audio output", selection: Binding(get: { audio.defaultOutput }, set: audio.selectOutput), options: audio.outputs.map { ($0.name, $0.id) })
                    .frame(maxWidth: .infinity)
                Button { showOptions.toggle() } label: { Image(systemName: showOptions ? "xmark" : "slider.horizontal.3") }
                    .buttonStyle(OrbitIconButtonStyle()).accessibilityLabel(showOptions ? "Close mixer options" : "Mixer options")
            }
            if showOptions { MixerPreferencesView(audio: audio) }
            else {
                VStack(spacing: 10) {
                    VStack(spacing: 2) {
                        deviceFader(audio.primary, title: "Output", symbol: "speaker.wave.2.fill")
                        if showsMicrophone { deviceFader(audio.microphone, title: "Mic", symbol: "mic.fill") }
                    }
                    Rectangle().fill(.white.opacity(0.09)).frame(height: 0.5)
                    if !audio.options.enabled {
                        mixerMessage("Mixer paused", detail: "Your saved levels return when you turn it on.")
                    } else if audio.visibleApps.isEmpty {
                        mixerMessage("Play something", detail: audio.options.hideInactive ? "Active apps appear here." : "Apps with an audio connection appear here.")
                    } else {
                        HStack {
                            Text("APPS").tracking(0.8)
                            Spacer()
                            Text("\(audio.visibleApps.count)").monospacedDigit()
                        }.font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 4) {
                                ForEach(audio.visibleApps) { app in appFader(app) }
                            }
                        }.scrollIndicators(.never).frame(height: appListHeight)
                            .accessibilityLabel("App volumes")
                    }
                }
            }
            if let error = audio.error {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button { audio.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss audio error")
                }
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: showOptions)
            .onAppear { audio.refresh() }
    }
    private func mixerMessage(_ title: String, detail: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: "waveform").font(.system(size: 22)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, minHeight: 110)
    }
    private func deviceFader(_ device: AudioOutput?, title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.white.opacity(0.75)).frame(width: 28)
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.frame(width: 128)
            MixerFader(value: Binding(get: { Double(device?.volume ?? 0) }, set: { value in
                if let device { audio.setVolume(Float(value), device: device.id, input: device.input) }
            }), maximum: 1, muted: device?.muted ?? false, enabled: device?.volume != nil, label: "\(title) volume")
                .frame(maxWidth: .infinity)
            if let device, let volume = device.volume {
                MixerPercent(value: Double(volume), maximum: 1, label: "\(title) percent") { audio.setVolume(Float($0), device: device.id, input: device.input) }
                Button { audio.toggleMute(device) } label: { Image(systemName: device.muted ? (device.input ? "mic.slash.fill" : "speaker.slash.fill") : (device.input ? "mic.fill" : "speaker.wave.2.fill")) }
                    .buttonStyle(.plain).disabled(!device.canMute && device.volume == nil).foregroundStyle(device.muted ? .orange : .secondary)
                    .frame(width: 28, height: 30).contentShape(Rectangle()).accessibilityLabel("\(device.muted ? "Unmute" : "Mute") \(title)")
            } else {
                Text("Fixed").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 54, height: 25)
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.tertiary).frame(width: 28, height: 30)
            }
        }.frame(height: 40).help(device?.name ?? "No device")
    }
    private func appFader(_ app: AudioApp) -> some View {
        HStack(spacing: 8) {
            Menu {
                Button(audio.options.pinned.contains(app.id) ? "Unpin app" : "Pin app") { audio.pin(app.id) }
                Button("Move earlier") { audio.move(app.id, by: -1) }
                Button("Move later") { audio.move(app.id, by: 1) }
                Divider()
                Menu("Play through") {
                    Button { audio.setAppOutput(app.id, uid: nil) } label: { Label("System output", systemImage: app.level.outputUID == nil ? "checkmark" : "speaker.wave.2") }
                    ForEach(audio.outputs) { output in
                        Button { audio.setAppOutput(app.id, uid: output.uid) } label: { Label(output.name, systemImage: app.level.outputUID == output.uid ? "checkmark" : "hifispeaker") }
                    }
                }
                if let uid = app.level.outputUID, !audio.outputs.contains(where: { $0.uid == uid }) { Text("Saved output disconnected · using system output") }
                Divider()
                Button("Reset volume & output") { audio.resetApp(app.id) }
                if app.issue != nil { Button("Retry audio connection") { audio.retry(app.id) } }
            } label: {
                HStack(spacing: 9) {
                    ZStack(alignment: .bottomTrailing) {
                        if let icon = app.icon { Image(nsImage: icon).resizable().interpolation(.high).frame(width: 25, height: 25) }
                        else { Image(systemName: "app.fill").font(.system(size: 22)).foregroundStyle(.secondary) }
                        if audio.options.pinned.contains(app.id) { Image(systemName: "pin.fill").font(.system(size: 7)).padding(2).background(.black, in: Circle()) }
                        else { Circle().fill(app.playing ? .mint : .gray.opacity(0.4)).frame(width: 5, height: 5) }
                    }.frame(width: 28, height: 28)
                    Text(app.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                }.frame(width: 128, height: 40).contentShape(Rectangle())
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(app.name) options")
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 128).accessibilityLabel("\(app.name) options")
            MixerFader(value: Binding(get: { MixerCurve.position(gain: audio.apps.first { $0.id == app.id }?.level.volume ?? app.level.volume) }, set: { audio.setAppGain(app.id, value: MixerCurve.gain(position: $0)) }),
                       maximum: 2, muted: app.level.volume <= 0.001, enabled: true, label: "\(app.name) volume")
                .frame(maxWidth: .infinity)
                .overlay(alignment: .center) { if app.pending { ProgressView().controlSize(.small).allowsHitTesting(false) } }
            MixerPercent(value: MixerCurve.position(gain: app.level.volume), maximum: 2, label: "\(app.name) percent") { audio.setAppGain(app.id, value: MixerCurve.gain(position: $0)) }
            if let issue = app.issue {
                Menu {
                    Text(issue)
                    Button("Retry") { audio.retry(app.id) }
                    Button("Open audio privacy settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!) }
                    Button("Use native playback") { audio.resetApp(app.id) }
                } label: { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).frame(width: 28, height: 30) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).help(issue).accessibilityLabel("\(app.name) volume not applied")
            } else {
                Button { audio.toggleAppMute(app.id) } label: { Image(systemName: app.level.volume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill") }
                    .buttonStyle(.plain).foregroundStyle(app.level.volume <= 0.001 ? .orange : .secondary)
                    .frame(width: 28, height: 30).contentShape(Rectangle()).accessibilityLabel("\(app.level.volume <= 0.001 ? "Unmute" : "Mute") \(app.name)")
            }
        }.frame(height: 40).help(app.level.outputUID.flatMap { uid in audio.outputs.first { $0.uid == uid }?.name } ?? "System output")
    }
}

private struct MixerFader: View {
    @Binding var value: Double
    let maximum: Double
    var muted: Bool
    var enabled: Bool
    let label: String
    private var tint: Color { value > 1.001 ? .orange : .white.opacity(0.85) }
    var body: some View {
        // A native horizontal slider keeps trackpad/wheel scrolling separate
        // from dragging a level and supplies keyboard + VoiceOver adjustment.
        Slider(value: $value, in: 0...maximum)
            .tint(muted ? .secondary : tint).controlSize(.small).disabled(!enabled)
            .accessibilityLabel(label)
            .accessibilityValue(enabled ? "\(Int(value * 100)) percent" : "Fixed volume")
            .help(maximum > 1 ? "0–200% · 100% at the centre" : label)
    }
}
private struct MixerPercent: View {
    let value: Double
    let maximum: Double
    let label: String
    var commit: (Double) -> Void
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        Group {
            if editing {
                TextField("%", text: $text).textFieldStyle(.plain).multilineTextAlignment(.center).focused($focused)
                    .onSubmit { finish() }.onChange(of: focused) { _, active in if !active { finish() } }
                    .accessibilityLabel(label)
            } else {
                Button { text = String(Int((value * 100).rounded())); editing = true; focused = true } label: {
                    Text("\(Int((value * 100).rounded()))%").monospacedDigit().foregroundStyle(value > 1.001 ? .orange : .secondary)
                }.buttonStyle(.plain).accessibilityLabel("Edit \(label)")
            }
        }.font(.system(size: 11, weight: .medium)).frame(width: 54, height: 25)
            .background(editing ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
    private func finish() {
        guard editing else { return }; editing = false
        if let number = Double(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)), number.isFinite { commit(min(maximum, max(0, number / 100))) }
    }
}

struct MixerPreferencesView: View {
    @ObservedObject var audio: AudioService
    private func binding(_ key: WritableKeyPath<MixerOptions, Bool>) -> Binding<Bool> {
        Binding(get: { audio.options[keyPath: key] }, set: { value in audio.updateOptions { $0[keyPath: key] = value } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsToggleRow("App mixer", isOn: binding(\.enabled))
            SettingsToggleRow("Show only active apps", isOn: binding(\.hideInactive))
            SettingsToggleRow("Show microphone fader", isOn: binding(\.showMicrophone))
            if !audio.inputs.isEmpty {
                HStack {
                    Label("Microphone", systemImage: "mic").font(.system(size: 11))
                    Spacer()
                    OrbitMenuPicker(title: "Microphone input", selection: Binding(get: { audio.defaultInput }, set: audio.selectInput), options: audio.inputs.map { ($0.name, $0.id) }).frame(maxWidth: 230)
                }
            }
            HStack {
                Label("Sound effects", systemImage: "bell").font(.system(size: 11))
                Spacer()
                OrbitMenuPicker(title: "Sound effects output", selection: Binding(get: { audio.systemOutput }, set: audio.selectSystemOutput), options: audio.outputs.map { ($0.name, $0.id) }).frame(maxWidth: 230)
            }
            Text("App levels and output choices are remembered. Click an app icon to pin, reorder or route it. Click a percentage to type a level; amber is boost above 100%.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("macOS may ask for system-audio access when you adjust an app. Audio stays on this Mac. Fixed-volume devices keep their own hardware controls.")
                .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            Button("Reset all app levels & outputs") { audio.resetLevels() }.buttonStyle(OrbitButtonStyle())
        }
    }
}
