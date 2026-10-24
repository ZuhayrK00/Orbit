import AppKit
import CoreAudio
import AudioToolbox
import Combine
import OrbitCore

struct AudioOutput: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let uid: String
    var volume: Float?
    var muted: Bool
    var canMute = false
    var input = false
    var scope: AudioObjectPropertyScope { input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput }
}
struct AudioApp: Identifiable {
    let id: String
    let pid: pid_t
    let name: String
    let bundleID: String
    var processes: [AudioObjectID]
    var playing: Bool
    var level: MixerLevel
    var routed = false
    var pending = false
    var issue: String?
    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

@MainActor final class AudioService: ObservableObject {
    @Published var outputs: [AudioOutput] = []
    @Published var inputs: [AudioOutput] = []
    @Published var defaultOutput: AudioObjectID = 0
    @Published var defaultInput: AudioObjectID = 0
    @Published var systemOutput: AudioObjectID = 0
    @Published var apps: [AudioApp] = []
    @Published var error: String?
    @Published private(set) var options = MixerOptions()
    var preferencesChanged: ((MixerOptions) -> Void)?
    private var routes: [String: AppAudioRoute] = [:]
    private var builds: [String: UUID] = [:]
    private var failures: [String: String] = [:]
    private var failedSignatures: [String: String] = [:]
    private let builder = DispatchQueue(label: "Orbit.audio.setup", qos: .userInitiated)
    private var lastDeviceLevels: [String: Float] = [:]
    private var stopped = false
    private var refreshing = false
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private let system = AudioObjectID(kAudioObjectSystemObject)
    init() {
        var selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice]
        if #available(macOS 14.2, *) { selectors.append(kAudioHardwarePropertyProcessObjectList) }
        for selector in selectors {
            var address = AudioProperties.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(system, &address, .main, block) == noErr { listeners.append((address, block)) }
        }
        refresh()
    }
    var primary: AudioOutput? { outputs.first { $0.id == defaultOutput } }
    var microphone: AudioOutput? { inputs.first { $0.id == defaultInput } }
    var visibleApps: [AudioApp] {
        let map = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        return options.ordered(apps.map(\.id)).compactMap { map[$0] }.filter { options.isVisible($0.id, playing: $0.playing) }
    }
    func configure(_ value: MixerOptions) {
        guard value != options else { return }; options = value; options.normalize(); refresh()
    }
    func updateOptions(_ change: (inout MixerOptions) -> Void) {
        change(&options); options.normalize(); preferencesChanged?(options); refresh()
    }
    func refresh() {
        guard !stopped, !refreshing else { return }; refreshing = true; defer { refreshing = false }
        defaultOutput = AudioProperties.scalar(system, selector: kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(0)) ?? 0
        defaultInput = AudioProperties.scalar(system, selector: kAudioHardwarePropertyDefaultInputDevice, initial: AudioObjectID(0)) ?? 0
        systemOutput = AudioProperties.scalar(system, selector: kAudioHardwarePropertyDefaultSystemOutputDevice, initial: AudioObjectID(0)) ?? 0
        let devices = AudioProperties.list(system, selector: kAudioHardwarePropertyDevices)
        outputs = devices.compactMap { device($0, input: false) }
        inputs = devices.compactMap { device($0, input: true) }
        guard #available(macOS 14.2, *) else { return }
        let owners = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var grouped: [String: AudioApp] = [:]
        for object in AudioProperties.list(system, selector: kAudioHardwarePropertyProcessObjectList) {
            guard let pid: pid_t = AudioProperties.scalar(object, selector: kAudioProcessPropertyPID, initial: pid_t(0)),
                  pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { continue }
            let application = Self.owner(pid: pid, owners: owners)
            let bundle = application?.bundleIdentifier ?? AudioProperties.string(object, selector: kAudioProcessPropertyBundleID) ?? ""
            guard !bundle.hasPrefix("com.apple.audio."), !bundle.hasPrefix("com.apple.WindowServer"),
                  bundle != Bundle.main.bundleIdentifier else { continue }
            let id = bundle.isEmpty ? "process:\(pid)" : bundle
            let playing = (AudioProperties.scalar(object, selector: kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) ?? 0) != 0
            // Core Audio also lists daemons, widgets and extensions. Resolve
            // helpers to their owning app and keep system services out of the desk.
            guard let application, application.bundleURL?.pathExtension == "app",
                  application.activationPolicy == .regular || playing || options.pinned.contains(id) || options.levels[id] != nil else { continue }
            if var row = grouped[id] { row.processes.append(object); row.playing = row.playing || playing; grouped[id] = row }
            else {
                let name = application.localizedName ?? bundle.split(separator: ".").last.map(String.init) ?? "Process \(pid)"
                grouped[id] = AudioApp(id: id, pid: application.processIdentifier, name: name, bundleID: bundle,
                    processes: [object], playing: playing, level: options.levels[id] ?? MixerLevel())
            }
        }
        for id in Set(routes.keys).subtracting(grouped.keys) { retire(id) }
        for id in Set(builds.keys).subtracting(grouped.keys) { builds.removeValue(forKey: id) }
        apps = grouped.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for row in apps { reconcile(row) }
        updateRows()
    }
    private func device(_ id: AudioObjectID, input: Bool) -> AudioOutput? {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        guard !AudioProperties.list(id, selector: kAudioDevicePropertyStreams, scope: scope).isEmpty,
              let uid = AudioProperties.string(id, selector: kAudioDevicePropertyDeviceUID), !uid.hasPrefix("orbit-mix-") else { return nil }
        var address = AudioProperties.address(kAudioDevicePropertyMute, scope: scope), settable = DarwinBoolean(false)
        let canMute = AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
        let volume = AudioProperties.volume(id, scope: scope)
        return AudioOutput(id: id, name: AudioProperties.string(id, selector: kAudioObjectPropertyName) ?? "Audio device", uid: uid,
            volume: volume, muted: canMute ? (AudioProperties.scalar(id, selector: kAudioDevicePropertyMute, scope: scope, initial: UInt32(0)) ?? 0) != 0 : (volume.map { $0 <= 0.001 } ?? false),
            canMute: canMute, input: input)
    }
    private static func owner(pid: pid_t, owners: [NSRunningApplication]) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 {
            if let owner = owners.first(where: { $0.processIdentifier == current }) { return owner }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1, info.pbi_ppid != current else { break }
            current = pid_t(info.pbi_ppid)
        }
        let app = NSRunningApplication(processIdentifier: pid)
        if let path = app?.bundleURL?.path, let owner = owners.first(where: { owner in
            guard let parent = owner.bundleURL?.path else { return false }; return path.hasPrefix(parent + "/")
        }) { return owner }
        return app
    }
    func setVolume(_ value: Float, device id: AudioObjectID, input: Bool = false) {
        guard value.isFinite else { return }
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        let level = min(1, max(0, value))
        var successes = 0
        for channel in [UInt32(0), 1, 2] {
            var address = AudioProperties.address(kAudioDevicePropertyVolumeScalar, scope: scope, element: channel)
            var settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue,
               AudioProperties.set(id, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: channel, value: level) == noErr {
                successes += 1; if channel == 0 { break }
            }
        }
        if successes == 0 { error = "This device does not offer software volume control." }
        else if let device = (input ? inputs : outputs).first(where: { $0.id == id }), device.canMute {
            _ = AudioProperties.set(id, selector: kAudioDevicePropertyMute, scope: scope, value: UInt32(level == 0 ? 1 : 0))
        }
        refresh()
    }
    func toggleMute(_ device: AudioOutput) {
        guard device.canMute else {
            guard let volume = device.volume else { return }
            if volume > 0.001 { lastDeviceLevels[device.uid] = volume; setVolume(0, device: device.id, input: device.input) }
            else { setVolume(lastDeviceLevels[device.uid] ?? 0.5, device: device.id, input: device.input) }
            return
        }
        let muted: UInt32 = AudioProperties.scalar(device.id, selector: kAudioDevicePropertyMute, scope: device.scope, initial: UInt32(0)) ?? 0
        if AudioProperties.set(device.id, selector: kAudioDevicePropertyMute, scope: device.scope, value: UInt32(muted == 0 ? 1 : 0)) != noErr { error = "This device did not accept the mute change." }
        refresh()
    }
    func selectOutput(_ id: AudioObjectID) { selectDevice(id, selector: kAudioHardwarePropertyDefaultOutputDevice) }
    func selectInput(_ id: AudioObjectID) { selectDevice(id, selector: kAudioHardwarePropertyDefaultInputDevice) }
    func selectSystemOutput(_ id: AudioObjectID) { selectDevice(id, selector: kAudioHardwarePropertyDefaultSystemOutputDevice) }
    private func selectDevice(_ id: AudioObjectID, selector: AudioObjectPropertySelector) {
        if AudioProperties.set(system, selector: selector, value: id) != noErr { error = "macOS could not switch to that audio device." }
        refresh()
    }
    func setAppGain(_ id: String, value: Double) { changeLevel(id) { $0.setVolume(value) } }
    func toggleAppMute(_ id: String) { changeLevel(id) { $0.toggleMute() } }
    func setAppOutput(_ id: String, uid: String?) { changeLevel(id) { $0.outputUID = uid } }
    func resetApp(_ id: String) { changeLevel(id) { $0 = MixerLevel() } }
    private func changeLevel(_ id: String, change: (inout MixerLevel) -> Void) {
        var level = options.levels[id] ?? MixerLevel(); change(&level); options.levels[id] = level
        failures.removeValue(forKey: id); failedSignatures.removeValue(forKey: id)
        preferencesChanged?(options)
        if let index = apps.firstIndex(where: { $0.id == id }) { apps[index].level = level; reconcile(apps[index]); updateRows() }
    }
    func retry(_ id: String) { failedSignatures.removeValue(forKey: id); failures.removeValue(forKey: id); refresh() }
    func pin(_ id: String) { updateOptions { if $0.pinned.contains(id) { $0.pinned.removeAll { $0 == id } } else { $0.pinned.append(id) } } }
    func move(_ id: String, by offset: Int) { let ids = apps.map(\.id); updateOptions { $0.move(id, by: offset, visible: ids) } }
    func resetLevels() { updateOptions { $0.levels = [:] }; failures = [:]; failedSignatures = [:]; refresh() }
    private func updateRows() {
        for i in apps.indices {
            let id = apps[i].id
            apps[i].routed = routes[id] != nil; apps[i].pending = builds[id] != nil
            apps[i].issue = failures[id]
        }
    }
    private func reconcile(_ app: AudioApp) {
        guard options.enabled, app.level.needsRoute else { retire(app.id); failures.removeValue(forKey: app.id); failedSignatures.removeValue(forKey: app.id); return }
        guard #available(macOS 14.4, *) else { failures[app.id] = "App mixing requires macOS 14.4 or later."; return }
        // A missing explicit destination falls back to the current output while
        // retaining the preference, so reconnecting restores that route.
        guard let output = outputs.first(where: { $0.uid == app.level.outputUID }) ?? primary else { retire(app.id); return }
        let signature = AppAudioRoute.signature(processes: app.processes, output: output)
        if let route = routes[app.id], route.signature == signature {
            if route.failedToRender(playing: app.playing) {
                retire(app.id); failedSignatures[app.id] = signature
                failures[app.id] = "This route received no playable audio. Native playback was restored. Try another output or Retry."
            } else { route.gain = Float(app.level.volume); route.refreshCompensation(fallback: defaultOutput) }
            return
        }
        guard builds[app.id] == nil, failedSignatures[app.id] != signature else { return }
        let token = UUID(); builds[app.id] = token
        let objects = app.processes, id = app.id, initialGain = Float(app.level.volume)
        builder.async { [weak self] in
            let result = Result { try AppAudioRoute(processes: objects, output: output, gain: initialGain) }
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.builds[id] == token else {
                    if case .success(let route) = result { route.stop() }; return
                }
                self.builds.removeValue(forKey: id)
                guard self.options.enabled, let latest = self.apps.first(where: { $0.id == id }), latest.level.needsRoute,
                      latest.processes.sorted() == objects.sorted(),
                      let destination = self.outputs.first(where: { $0.uid == latest.level.outputUID }) ?? self.primary,
                      AppAudioRoute.signature(processes: latest.processes, output: destination) == signature else {
                    if case .success(let route) = result { route.stop() }; self.refresh(); return
                }
                switch result {
                case .success(let route):
                    route.gain = Float(latest.level.volume)
                    let old = self.routes.updateValue(route, forKey: id)
                    // Release the old path only after its replacement started.
                    if let old { self.builder.async(execute: DispatchWorkItem { old.stop() }) }
                    self.failures.removeValue(forKey: id); self.failedSignatures.removeValue(forKey: id)
                case .failure(let error):
                    self.failures[id] = error.localizedDescription; self.failedSignatures[id] = signature
                    if let old = self.routes[id], !self.outputs.contains(where: { $0.uid == old.outputUID }) { self.retire(id) }
                }
                self.updateRows()
            }
        }
    }
    private func retire(_ id: String) {
        builds.removeValue(forKey: id)
        if let route = routes.removeValue(forKey: id) { builder.async(execute: DispatchWorkItem { route.stop() }) }
    }
    func stopAll() {
        stopped = true; builds = [:]
        for (var address, block) in listeners { AudioObjectRemovePropertyListenerBlock(system, &address, .main, block) }
        listeners = []
        let old = Array(routes.values); routes = [:]
        // Finish teardown before the process exits, restoring native playback.
        builder.sync { for route in old { route.stop() } }
    }
}
