import Foundation

public struct AwakeApp: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct AwakeOptions: Codable, Equatable {
    public var allowDisplaySleep = true
    public var startOnLaunch = false
    public var movePointer = false
    public var pointerInterval = 60
    public var pauseWhenLocked = true
    public var batteryCutoff = 15
    public var automationEnabled = false
    public var requireAll = false
    public var onPower = false
    public var externalDisplay = false
    public var runningApps = false
    public var apps: [AwakeApp] = []
    public init() {}
    public mutating func normalize() {
        pointerInterval = [15, 30, 60, 120, 300].contains(pointerInterval) ? pointerInterval : 60
        batteryCutoff = min(50, max(5, batteryCutoff))
        var seen = Set<String>()
        apps = Array(apps.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }.prefix(12))
    }

    public func matches(power: Bool, externalDisplay: Bool, running: Set<String>) -> Bool {
        guard automationEnabled else { return false }
        var results: [Bool] = []
        if onPower { results.append(power) }
        if self.externalDisplay { results.append(externalDisplay) }
        if runningApps { results.append(!apps.isEmpty && apps.contains { running.contains($0.id) }) }
        return !results.isEmpty && (requireAll ? results.allSatisfy { $0 } : results.contains(true))
    }
}

/// A user's Stop takes precedence until the matching conditions clear.
public struct AwakeAutomation: Equatable {
    public private(set) var suppressed = false
    public init() {}
    public mutating func userStopped(matching: Bool) { suppressed = matching }
    public mutating func shouldStart(matching: Bool, sessionActive: Bool, allowed: Bool) -> Bool {
        if !matching { suppressed = false }
        return matching && !sessionActive && allowed && !suppressed
    }
}

public enum AwakeTiming {
    public static func nextEndTime(_ picked: Date, now: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.hour, .minute], from: picked)
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
    }
    public static func leaseIsFresh(updated: Date, deadline: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(updated)
        return age >= -2 && age < 10 && now < deadline
    }
}
