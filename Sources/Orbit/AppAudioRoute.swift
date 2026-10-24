import AppKit
import CoreAudio
import AudioToolbox
import OrbitCore

/// An app-only tap feeding a private playback device. Its physical input
/// streams are excluded from rendering; nothing is recorded or uploaded.
final class AppAudioRoute {
    let processes: [AudioObjectID]
    let outputUID: String
    let signature: String
    var renderedCycles: Int { queue.sync { state.validCycles } }
    private var lastCycles = 0
    private var lastProgress = Date()
    private var wasPlaying = false
    func failedToRender(playing: Bool) -> Bool {
        let cycles = queue.sync { state.validCycles }
        if !playing || !wasPlaying || cycles != lastCycles { lastProgress = Date() }
        wasPlaying = playing; lastCycles = cycles
        return playing && Date().timeIntervalSince(lastProgress) > 3
    }
    static func signature(processes: [AudioObjectID], output: AudioOutput) -> String {
        let streams = AudioProperties.list(output.id, selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        let formats = streams.compactMap { AudioProperties.scalar($0, selector: kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription()) }
        return processes.sorted().map(String.init).joined(separator: ",") + ":" + output.uid + ":" + formats.map {
            "\($0.mSampleRate)/\($0.mChannelsPerFrame)/\($0.mFormatFlags)"
        }.joined(separator: ",")
    }
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "Orbit.audio.render", qos: .userInteractive)
    private final class RenderState {
        var gain: Float
        var compensation: Float
        var validCycles = 0
        var dsp: MixerDSP
        init(gain: Float, compensation: Float) {
            self.gain = gain; self.compensation = compensation
            dsp = MixerDSP(gain: gain * compensation)
        }
    }
    private let state: RenderState
    var gain: Float {
        didSet {
            let state = state, next = gain
            queue.async { state.gain = next }
        }
    }
    @available(macOS 14.4, *) init(processes: [AudioObjectID], output: AudioOutput, gain: Float) throws {
        self.processes = processes; outputUID = output.uid; self.gain = gain
        signature = Self.signature(processes: processes, output: output)
        state = RenderState(gain: gain, compensation: Self.compensation(processes, fallback: output.id))
        do {
            let description = CATapDescription(stereoMixdownOfProcesses: processes)
            description.name = "Orbit app volume"; description.isPrivate = true; description.muteBehavior = .mutedWhenTapped
            try check(AudioHardwareCreateProcessTap(description, &tap), "Allow Orbit in System Settings → Privacy & Security → Screen & System Audio Recording, then retry")
            guard tap != 0, let uid = AudioProperties.string(tap, selector: kAudioTapPropertyUID),
                  let format: AudioStreamBasicDescription = AudioProperties.scalar(tap, selector: kAudioTapPropertyFormat, initial: AudioStreamBasicDescription()),
                  Self.supported(format), format.mChannelsPerFrame > 0,
                  format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 else {
                throw FileTools.failure("This app’s audio format is not supported. Native playback has been restored.")
            }
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Orbit private mixer", kAudioAggregateDeviceUIDKey: "orbit-mix-" + UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: output.uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: uid, kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "Create the app’s output route")
            let inputShape = Self.bufferChannels(aggregate, scope: kAudioObjectPropertyScopeInput)
            let outputStreams = AudioProperties.list(aggregate, selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            let inputStreams = AudioProperties.list(aggregate, selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            let outFormats: [AudioStreamBasicDescription] = outputStreams.compactMap { AudioProperties.scalar($0, selector: kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription()) }
            let inFormats: [AudioStreamBasicDescription] = inputStreams.compactMap { AudioProperties.scalar($0, selector: kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription()) }
            let tapChannels = Int(format.mChannelsPerFrame)
            // The aggregate appends its tap after the sub-device inputs. Check
            // that contract once, then use exactly that index on every cycle.
            guard !inputShape.isEmpty, inputShape.last == tapChannels,
                  !outFormats.isEmpty, outFormats.count == outputStreams.count, outFormats.allSatisfy(Self.supported),
                  let tapFormat = inFormats.last, Self.supported(tapFormat),
                  outFormats.allSatisfy({ abs($0.mSampleRate - tapFormat.mSampleRate) < 1 }) else {
                throw FileTools.failure("This device’s stream layout cannot be mixed safely. Choose another output or reset this app to 100%.")
            }
            let tapIndex = inputShape.count - 1, state = state, rate = tapFormat.mSampleRate
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { _, input, _, output, _ in
                let incoming = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                let outgoing = UnsafeMutableAudioBufferListPointer(output)
                if incoming.count == inputShape.count, incoming.indices.contains(tapIndex),
                   incoming[tapIndex].mData != nil, incoming[tapIndex].mNumberChannels == tapChannels,
                   incoming[tapIndex].mDataByteSize > 0,
                   outgoing.contains(where: { $0.mData != nil && $0.mDataByteSize > 0 }) { state.validCycles += 1 }
                state.dsp.render(input: incoming, tapIndex: incoming.count == inputShape.count ? tapIndex : -1,
                    tapChannels: tapChannels, output: outgoing, targetGain: state.gain * state.compensation, sampleRate: rate)
            }, "Prepare app playback")
            try check(AudioDeviceStart(aggregate, ioProc), "Start app playback; check system-audio access and retry")
        } catch { stop(); throw error }
    }
    @available(macOS 14.2, *) func refreshCompensation(fallback: AudioObjectID) {
        let next = Self.compensation(processes, fallback: fallback), state = state
        queue.async { state.compensation = next }
    }
    @available(macOS 14.2, *) private static func compensation(_ processes: [AudioObjectID], fallback: AudioObjectID) -> Float {
        let devices = Set(processes.flatMap { AudioProperties.list($0, selector: kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput) })
        // HAL stereo mixdowns divide by the source stream's channel count.
        // Only compensate the front stereo pair, never multiply by surround size.
        let source = devices.isEmpty ? [fallback] : Array(devices)
        let counts = source.flatMap { AudioProperties.list($0, selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput) }
            .compactMap { AudioProperties.scalar($0, selector: kAudioStreamPropertyVirtualFormat, initial: AudioStreamBasicDescription())?.mChannelsPerFrame }
        return counts.contains(where: { $0 >= 2 }) ? 2 : 1
    }
    private static func supported(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM && format.mBitsPerChannel == 32 && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
    }
    private static func bufferChannels(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> [Int] {
        var address = AudioProperties.address(kAudioDevicePropertyStreamConfiguration, scope: scope), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= MemoryLayout<AudioBufferList>.size else { return [] }
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bytes.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, bytes) == noErr else { return [] }
        return UnsafeMutableAudioBufferListPointer(bytes.assumingMemoryBound(to: AudioBufferList.self)).map { Int($0.mNumberChannels) }
    }
    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw FileTools.failure("\(operation). Core Audio \(status).") }
    }
    func stop() {
        if let ioProc, aggregate != 0 { AudioDeviceStop(aggregate, ioProc); AudioDeviceDestroyIOProcID(aggregate, ioProc); self.ioProc = nil }
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tap) }; tap = 0 }
    }
    deinit { stop() }
}
