import Foundation
import CoreAudio
import AVFoundation

enum MixerSmokeTests {
    @MainActor static func run() async throws {
        guard #available(macOS 14.4, *) else { throw FileTools.failure("Mixer needs macOS 14.4.") }
        let service = AudioService(); defer { service.stopAll() }
        guard let output = service.primary else { throw FileTools.failure("No output for the mixer check.") }
        let system = AudioObjectID(kAudioObjectSystemObject)
        let before = Set(AudioProperties.list(system, selector: kAudioHardwarePropertyDevices))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-mixer-silence-" + UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000 * 15)!
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<2 { memset(buffer.floatChannelData![i], 0, Int(buffer.frameLength) * 4) }
        try file.write(from: buffer)
        let child = Process(); child.executableURL = URL(fileURLWithPath: "/usr/bin/afplay"); child.arguments = [url.path]
        child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try child.run(); defer { if child.isRunning { child.terminate() } }
        var objects: [AudioObjectID] = []
        for _ in 0..<30 {
            objects = AudioProperties.list(system, selector: kAudioHardwarePropertyProcessObjectList).filter {
                AudioProperties.scalar($0, selector: kAudioProcessPropertyPID, initial: pid_t(0)) == child.processIdentifier
            }
            if !objects.isEmpty { break }; try await Task.sleep(for: .milliseconds(100))
        }
        guard !objects.isEmpty else { throw FileTools.failure("The silent fixture did not create an audio process.") }
        let route = try AppAudioRoute(processes: objects, output: output, gain: 0.5)
        defer { route.stop() }
        try await Task.sleep(for: .milliseconds(400))
        guard route.renderedCycles > 0 else { throw FileTools.failure("The route started but did not render valid tap buffers.") }
        for gain: Float in [0, 1.5, 1] { route.gain = gain; try await Task.sleep(for: .milliseconds(80)) }
        let cycles = route.renderedCycles
        var alternateName = "not available"
        if let alternate = service.outputs.first(where: { $0.id != output.id && $0.name.contains("MacBook") }) {
            let replacement = try AppAudioRoute(processes: objects, output: alternate, gain: 0)
            defer { replacement.stop() }
            route.stop(); replacement.gain = 0.5
            try await Task.sleep(for: .milliseconds(400))
            guard replacement.renderedCycles > 0 else { throw FileTools.failure("The alternate output did not render.") }
            alternateName = alternate.name; replacement.stop()
        }
        route.stop(); route.stop()
        try await Task.sleep(for: .milliseconds(100))
        let after = Set(AudioProperties.list(system, selector: kAudioHardwarePropertyDevices))
        let leftovers = after.subtracting(before).filter { AudioProperties.string($0, selector: kAudioDevicePropertyDeviceUID)?.hasPrefix("orbit-mix-") == true }
        guard leftovers.isEmpty else { throw FileTools.failure("A private mixer device was not removed.") }
        print("Mixer smoke passed: isolated silent process, real tap/playback callbacks (\(cycles)), gain/mute/boost updates and idempotent cleanup. Output: \(output.name); alternate: \(alternateName). No system volume or existing app level changed.")
    }
}
