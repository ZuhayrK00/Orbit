import Foundation
import CoreGraphics

public enum WheelPlacement: String, Codable, CaseIterable { case pointer, screenCenter }

public struct WheelOptions: Codable, Equatable {
    public var placement: WheelPlacement = .pointer
    public var showLabels = true
    public var animate = true
    public var dismissOnOutsideClick = true
    public var escapeReturnsToWheel = true
    public var toolWidth = 460.0
    public init() {}
    public mutating func normalize() {
        toolWidth = toolWidth.isFinite ? min(600, max(400, toolWidth)) : 460
    }
    private enum CodingKeys: String, CodingKey { case placement, showLabels, animate, dismissOnOutsideClick, escapeReturnsToWheel, toolWidth }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        placement = try values.decodeIfPresent(WheelPlacement.self, forKey: .placement) ?? placement
        showLabels = try values.decodeIfPresent(Bool.self, forKey: .showLabels) ?? showLabels
        animate = try values.decodeIfPresent(Bool.self, forKey: .animate) ?? animate
        dismissOnOutsideClick = try values.decodeIfPresent(Bool.self, forKey: .dismissOnOutsideClick) ?? dismissOnOutsideClick
        escapeReturnsToWheel = try values.decodeIfPresent(Bool.self, forKey: .escapeReturnsToWheel) ?? escapeReturnsToWheel
        toolWidth = try values.decodeIfPresent(Double.self, forKey: .toolWidth) ?? toolWidth
        normalize()
    }
}

public enum WheelDismissal {
    /// A file drop starts outside Orbit. Keep that destination alive from the
    /// first Finder click, not just after the drag reaches its bounds.
    public static func outsideClickCloses(section: OrbitAction?, pinned: Bool, processing: Bool, enabled: Bool, modal: Bool) -> Bool {
        enabled && !modal && !pinned && !processing && section != .files && section != .shelf
    }
}

public struct WheelLayout {
    public static let margin = 28.0
    public let diameter: Double
    public let toolWidth: Double
    public let toolHeightLimit: Double
    public let frame: CGRect
    public init(screen: CGRect, pointer: CGPoint, diameter: Double, toolWidth: Double, placement: WheelPlacement) {
        let maxWidth = max(1, screen.width - Self.margin * 2)
        let maxHeight = max(1, screen.height - Self.margin * 2)
        self.diameter = min(diameter, maxWidth, maxHeight)
        self.toolWidth = min(toolWidth, maxWidth)
        toolHeightLimit = min(760, maxHeight)
        // The surface owns one stable animation canvas. Only its mask and
        // content layers change size, keeping AppKit out of the animation loop.
        let size = CGSize(width: min(screen.width, max(self.diameter, self.toolWidth) + Self.margin * 2),
                          height: min(screen.height, max(self.diameter, toolHeightLimit) + Self.margin * 2))
        let anchor = placement == .pointer ? pointer : CGPoint(x: screen.midX, y: screen.midY)
        frame = CGRect(x: min(max(screen.minX, anchor.x - size.width / 2), screen.maxX - size.width),
                       y: min(max(screen.minY, anchor.y - size.height / 2), screen.maxY - size.height), width: size.width, height: size.height)
    }
}

/// A circle and a rounded panel share one path topology. Size and corner motion
/// retain their velocity when Back interrupts a transition, as the notch does.
public struct WheelMotion {
    public struct Pose: Equatable {
        public let size: CGSize
        public let radius: Double
        public init(size: CGSize, radius: Double) { self.size = size; self.radius = radius }
    }
    public struct Sample {
        public let pose: Pose
        public let velocity: CGSize
        public let radiusVelocity: Double
    }
    public let target: Pose
    public var duration: Double { max(sizeMotion.duration, cornerMotion.duration) }
    private let sizeMotion: NotchMotion
    private let cornerMotion: NotchMotion
    public init(from pose: Pose, velocity: CGSize = .zero, radiusVelocity: Double = 0, to target: Pose) {
        self.target = target
        sizeMotion = NotchMotion(from: pose.size, velocity: velocity, to: target.size)
        cornerMotion = NotchMotion(from: CGSize(width: pose.radius, height: pose.radius),
            velocity: CGSize(width: radiusVelocity, height: radiusVelocity), to: CGSize(width: target.radius, height: target.radius))
    }
    public func sample(at time: Double) -> Sample {
        let size = sizeMotion.sample(at: time), corner = cornerMotion.sample(at: time)
        return Sample(pose: Pose(size: size.size, radius: corner.size.width), velocity: size.velocity, radiusVelocity: corner.velocity.width)
    }
}
