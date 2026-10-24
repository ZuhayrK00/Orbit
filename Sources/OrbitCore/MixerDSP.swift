import Foundation
import AudioToolbox

/// Maps the known tap buffer onto Float32 output buffers. No physical input
/// buffer is ever selected by its contents; the route supplies its exact index.
public struct MixerDSP {
    private var smoothedGain: Float
    private var ceiling: Float = 1
    public init(gain: Float) { smoothedGain = gain }
    public mutating func render(input: UnsafeMutableAudioBufferListPointer, tapIndex: Int, tapChannels: Int,
                               output: UnsafeMutableAudioBufferListPointer, targetGain: Float, sampleRate: Double) {
        for buffer in output { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
        guard input.indices.contains(tapIndex), tapChannels > 0,
              Int(input[tapIndex].mNumberChannels) == tapChannels,
              let source = input[tapIndex].mData?.assumingMemoryBound(to: Float.self) else { return }
        let sourceFrames = Int(input[tapIndex].mDataByteSize) / (4 * tapChannels)
        let totalChannels = output.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard totalChannels > 0 else { return }
        let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48000
        let smoothing = Float(1 - exp(-1 / (rate * 0.005)))
        let release = Float(1 - exp(-1 / (rate * 0.08)))
        let target = targetGain.isFinite ? max(0, min(8, targetGain)) : 0
        for frame in 0..<sourceFrames {
            smoothedGain += (target - smoothedGain) * smoothing
            var peak: Float = 0
            for channel in 0..<tapChannels {
                let sample = source[frame * tapChannels + channel]
                if sample.isFinite { peak = max(peak, abs(sample * smoothedGain)) }
            }
            // Linked stereo limiter: instant protection, smooth recovery. The
            // same attenuation on both channels preserves the stereo image.
            let required: Float = peak > 0.98 ? 0.98 / peak : 1
            ceiling = required < ceiling ? required : ceiling + (required - ceiling) * release
            var channelOffset = 0
            for buffer in output {
                let channels = Int(buffer.mNumberChannels)
                defer { channelOffset += channels }
                guard channels > 0, frame < Int(buffer.mDataByteSize) / (4 * channels),
                      let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for channel in 0..<channels {
                    var sample: Float = 0
                    if totalChannels == 1 && tapChannels > 1 {
                        for sourceChannel in 0..<tapChannels {
                            let value = source[frame * tapChannels + sourceChannel]
                            if value.isFinite { sample += value / Float(tapChannels) }
                        }
                    } else {
                        let index = tapChannels == 1 && channelOffset + channel < 2 ? 0 : channelOffset + channel
                        if index < tapChannels { sample = source[frame * tapChannels + index] }
                    }
                    destination[frame * channels + channel] = sample.isFinite ? sample * smoothedGain * ceiling : 0
                }
            }
        }
    }
}
