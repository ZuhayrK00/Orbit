import XCTest
import AudioToolbox
@testable import OrbitCore

final class MixerTests: XCTestCase {
    func testLegacySettingsAndPartialMixerMigration() throws {
        let original = OrbitConfiguration()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(OrbitConfiguration.self, from: data)
        XCTAssertNil(restored.mixerSettings); XCTAssertEqual(restored.mixer, MixerOptions())
        let partial = try JSONDecoder().decode(MixerOptions.self, from: Data("{\"hideInactive\":true}".utf8))
        XCTAssertTrue(partial.hideInactive); XCTAssertTrue(partial.enabled); XCTAssertTrue(partial.showMicrophone)
    }
    func testMuteRestoresBoostAndOutputSurvivesLevelChanges() throws {
        var level = MixerLevel(); level.outputUID = "headset"; level.setVolume(1.65)
        level.toggleMute(); XCTAssertEqual(level.volume, 0); XCTAssertEqual(level.lastAudible, 1.65)
        level.toggleMute(); XCTAssertEqual(level.volume, 1.65); XCTAssertEqual(level.outputUID, "headset")
        level.setVolume(99); XCTAssertEqual(level.volume, 2)
        level.setVolume(.nan); XCTAssertEqual(level.volume, 1)
        XCTAssertTrue(level.needsRoute)
        level.outputUID = nil; XCTAssertFalse(level.needsRoute)
        let roundTrip = try JSONDecoder().decode(MixerLevel.self, from: JSONEncoder().encode(level))
        XCTAssertEqual(roundTrip, level)
    }
    func testPinnedOrderAndInactiveVisibilityRetainAdjustedApps() {
        var options = MixerOptions(); options.pinned = ["b", "b", ""]; options.order = ["c", "c", "a", "b"]; options.normalize()
        XCTAssertEqual(options.ordered(["a", "b", "c"]), ["b", "c", "a"])
        options.move("a", by: -1, visible: ["a", "b", "c"])
        XCTAssertEqual(options.ordered(["a", "b", "c"]), ["b", "a", "c"])
        options.move("b", by: 1, visible: ["a", "b", "c"])
        XCTAssertEqual(options.ordered(["a", "b", "c"]), ["b", "a", "c"])
        options.hideInactive = true
        XCTAssertTrue(options.isVisible("b", playing: false)); XCTAssertFalse(options.isVisible("a", playing: false))
        var level = MixerLevel(); level.setVolume(0.3); options.levels["a"] = level
        XCTAssertTrue(options.isVisible("a", playing: false)); XCTAssertTrue(options.isVisible("c", playing: true))
    }
    private func render(_ inputs: [[Float]], channels: [Int], tapIndex: Int, tapChannels: Int,
                        outputChannels: [Int], outputFrames: Int, gain: Float) -> [[Float]] {
        let input = AudioBufferList.allocate(maximumBuffers: inputs.count)
        let output = AudioBufferList.allocate(maximumBuffers: outputChannels.count)
        defer {
            for buffer in input { buffer.mData?.deallocate() }; input.unsafeMutablePointer.deallocate()
            for buffer in output { buffer.mData?.deallocate() }; output.unsafeMutablePointer.deallocate()
        }
        for i in inputs.indices {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: inputs[i].count)
            data.initialize(from: inputs[i], count: inputs[i].count)
            input[i] = AudioBuffer(mNumberChannels: UInt32(channels[i]), mDataByteSize: UInt32(inputs[i].count * 4), mData: data)
        }
        for i in outputChannels.indices {
            let count = outputChannels[i] * outputFrames
            let data = UnsafeMutablePointer<Float>.allocate(capacity: count); data.initialize(repeating: 99, count: count)
            output[i] = AudioBuffer(mNumberChannels: UInt32(outputChannels[i]), mDataByteSize: UInt32(count * 4), mData: data)
        }
        var dsp = MixerDSP(gain: gain)
        dsp.render(input: input, tapIndex: tapIndex, tapChannels: tapChannels, output: output, targetGain: gain, sampleRate: 48000)
        return output.map { Array(UnsafeBufferPointer(start: $0.mData!.assumingMemoryBound(to: Float.self), count: Int($0.mDataByteSize) / 4)) }
    }
    func testRendererSkipsPhysicalInputAndClearsTheTail() {
        let result = render([[0.9, 0.9], [0.2, -0.4, 0.6, -0.2]], channels: [1, 2], tapIndex: 1, tapChannels: 2,
                            outputChannels: [2], outputFrames: 3, gain: 0.5)
        XCTAssertEqual(result[0], [0.1, -0.2, 0.3, -0.1, 0, 0])
        let missing = render([[0.9, 0.9]], channels: [1], tapIndex: 1, tapChannels: 2, outputChannels: [2], outputFrames: 2, gain: 1)
        XCTAssertEqual(missing[0], [0, 0, 0, 0])
    }
    func testStereoMapsToMonoAndNonInterleavedWithoutPitchChange() {
        let source: [Float] = [0.2, 0.4, 0.4, 0.6]
        let mono = render([source], channels: [2], tapIndex: 0, tapChannels: 2, outputChannels: [1], outputFrames: 2, gain: 1)
        XCTAssertEqual(mono[0][0], 0.3, accuracy: 0.0001); XCTAssertEqual(mono[0][1], 0.5, accuracy: 0.0001)
        let planar = render([source], channels: [2], tapIndex: 0, tapChannels: 2, outputChannels: [1, 1, 1], outputFrames: 2, gain: 1)
        XCTAssertEqual(planar, [[0.2, 0.4], [0.4, 0.6], [0, 0]])
    }
    func testBoostLimitsPeaksAndRejectsInvalidSamples() {
        let output = render([[0.1, -0.1, 0.9, -0.9, .nan, .infinity]], channels: [2], tapIndex: 0, tapChannels: 2, outputChannels: [2], outputFrames: 3, gain: 2)[0]
        XCTAssertEqual(output[0], 0.2, accuracy: 0.0001)
        XCTAssertTrue(output.allSatisfy { $0.isFinite && abs($0) <= 0.98001 })
        XCTAssertEqual(output[2], -output[3], accuracy: 0.0001)
        XCTAssertEqual(Array(output.suffix(2)), [0, 0])
    }
}
