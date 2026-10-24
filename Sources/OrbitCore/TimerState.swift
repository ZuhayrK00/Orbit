import Foundation

public struct OrbitTimer: Codable, Equatable {
    public var end: Date?
    public var pausedRemaining: TimeInterval?
    public var duration: TimeInterval = 0
    public var name = "Focus timer"
    public init() {}
    public var isActive: Bool { end != nil || pausedRemaining != nil }
    public func remaining(at now: Date = Date()) -> TimeInterval {
        // A display may still have the preceding clock sample when a timer starts.
        // Never show more time than was requested, including after restoration.
        min(max(0, duration), max(0, end?.timeIntervalSince(now) ?? pausedRemaining ?? 0))
    }
    public mutating func start(seconds: TimeInterval, now: Date = Date()) {
        duration = min(86_400, max(1, seconds)); end = now.addingTimeInterval(duration); pausedRemaining = nil
    }
    public mutating func pause(now: Date = Date()) { guard end != nil else { return }; pausedRemaining = remaining(at: now); end = nil }
    public mutating func resume(now: Date = Date()) { guard let remaining = pausedRemaining else { return }; end = now.addingTimeInterval(remaining); pausedRemaining = nil }
    public mutating func cancel() { end = nil; pausedRemaining = nil; duration = 0 }
    public static func label(_ remaining: TimeInterval) -> String {
        let seconds = Int(ceil(max(0, remaining)))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
