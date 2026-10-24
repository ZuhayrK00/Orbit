import Foundation

public struct TimerPreset: Codable, Equatable, Identifiable {
    public var id: UUID
    public var minutes: Int
    public init(minutes: Int, id: UUID = UUID()) { self.id = id; self.minutes = minutes }
}

public enum TimerPresets {
    public static let defaults = [5, 15, 25, 45].map { TimerPreset(minutes: $0) }
    public static let maximumCount = 8
    public static let durationRange = 1...1440

    public static func normalize(_ values: [TimerPreset]) -> [TimerPreset] {
        guard !values.isEmpty else { return defaults }
        var seen = Set<UUID>()
        return values.prefix(maximumCount).map { value in
            var next = value
            next.minutes = min(durationRange.upperBound, max(durationRange.lowerBound, next.minutes))
            if !seen.insert(next.id).inserted { next.id = UUID(); seen.insert(next.id) }
            return next
        }
    }
}
