import Foundation
import CoreGraphics

/// Independent springs let the bottom lead the sides. Sizes and velocities are
/// expressed in points, so interrupted openings and content resizes can retarget
/// the shape already on screen instead of restarting from a collapsed endpoint.
public struct NotchMotion {
    public struct Sample {
        public let size: CGSize
        public let velocity: CGSize
    }

    public let target: CGSize
    public let duration: Double
    public let envelope: CGSize
    private let horizontal: Axis
    private let vertical: Axis

    public init(from size: CGSize, velocity: CGSize = .zero, to target: CGSize, steadyWidth: Bool = false) {
        self.target = target
        horizontal = Axis(start: size.width, velocity: velocity.width, target: target.width, horizontal: true, steady: steadyWidth)
        vertical = Axis(start: size.height, velocity: velocity.height, target: target.height, horizontal: false, steady: false)
        // Include the full settling tail, not just the first crossing of the target.
        // Also reserve the sampled excursion during a reversal, when momentum can
        // briefly carry the silhouette away from its new destination.
        var end = 0.0
        var maximum = CGSize(width: max(size.width, target.width), height: max(size.height, target.height))
        for frame in 0...480 {
            let time = Double(frame) / 240
            let x = horizontal.sample(time), y = vertical.sample(time)
            maximum.width = max(maximum.width, x.position)
            maximum.height = max(maximum.height, y.position)
            if abs(x.position - target.width) > 0.1 || abs(y.position - target.height) > 0.1
                || abs(x.velocity) > 1 || abs(y.velocity) > 1 {
                end = time + 1.0 / 240
            }
        }
        duration = max(1.0 / 120, end)
        envelope = CGSize(width: ceil(maximum.width + 1), height: ceil(maximum.height + 1))
    }

    public func sample(at elapsed: Double) -> Sample {
        guard elapsed < duration else { return Sample(size: target, velocity: .zero) }
        let x = horizontal.sample(max(0, elapsed)), y = vertical.sample(max(0, elapsed))
        return Sample(size: CGSize(width: x.position, height: y.position), velocity: CGSize(width: x.velocity, height: y.velocity))
    }

    private struct Axis {
        let start: Double
        let velocity: Double
        let target: Double
        let omega: Double
        let damping: Double

        init(start: Double, velocity: Double, target: Double, horizontal: Bool, steady: Bool) {
            self.start = start; self.velocity = velocity; self.target = target
            let growing = target > start
            let period = steady ? 0.50 : growing ? (horizontal ? 0.44 : 0.38) : (horizontal ? 0.30 : 0.26)
            var ratio = steady || !growing ? 1.0 : horizontal ? 0.75 : 0.78
            // Limit the opening's elastic finish to 12 points, including tall pages.
            let travel = abs(target - start)
            if ratio < 1, travel > 12 {
                let logarithm = log(12 / travel)
                ratio = max(ratio, -logarithm / sqrt(Double.pi * Double.pi + logarithm * logarithm))
            }
            damping = ratio
            var frequency = 2 * Double.pi / period
            // A fast interrupted close must never dip below its compact target.
            if ratio == 1, start > target, velocity < 0 {
                frequency = max(frequency, -velocity / (start - target))
            }
            omega = frequency
        }

        func sample(_ time: Double) -> (position: Double, velocity: Double) {
            let displacement = start - target
            if damping == 1 {
                let coefficient = velocity + omega * displacement
                let decay = exp(-omega * time)
                return (target + (displacement + coefficient * time) * decay,
                        (velocity - omega * coefficient * time) * decay)
            }
            let decayRate = damping * omega
            let oscillation = omega * sqrt(1 - damping * damping)
            let sineWeight = (velocity + decayRate * displacement) / oscillation
            let cosine = cos(oscillation * time), sine = sin(oscillation * time)
            let wave = displacement * cosine + sineWeight * sine
            let decay = exp(-decayRate * time)
            return (target + decay * wave,
                    decay * (oscillation * (sineWeight * cosine - displacement * sine) - decayRate * wave))
        }
    }
}
