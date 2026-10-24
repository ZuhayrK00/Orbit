import Foundation

public struct DownloadSample: Equatable {
    public var path: String
    public var target: String
    public var bytes: Int64
    public var total: Int64?
    public var identifier: String?
    public var temporary: Bool
    public init(path: String, target: String, bytes: Int64, total: Int64? = nil, temporary: Bool, identifier: String? = nil) { self.path = path; self.target = target; self.bytes = bytes; self.total = total; self.temporary = temporary; self.identifier = identifier }
}
public struct DownloadActivity: Identifiable, Equatable {
    public enum State: String { case downloading, complete, missing }
    public var id: String
    public var target: String
    public var bytes: Int64
    public var total: Int64?
    public var state: State
    public var updated: Date
    public var fraction: Double? { guard let total, total > 0 else { return nil }; return min(1, max(0, Double(bytes) / Double(total))) }
}
public struct DownloadTracker {
    public private(set) var activities: [DownloadActivity] = []
    private var identities: [String: String] = [:]
    private var baseline: Set<String> = []
    private var started = false
    private var stable: [String: (Int64, Int)] = [:]
    public init() {}
    public mutating func ingest(_ samples: [DownloadSample], now: Date) {
        let current = Dictionary(samples.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        if !started { baseline = Set(samples.filter { !$0.temporary }.map(\.path)); started = true }
        for sample in samples where sample.temporary {
            stable.removeValue(forKey: sample.target)
            if let id = sample.identifier { identities[sample.path] = id }
            if let index = activities.firstIndex(where: { $0.id == sample.path }) {
                activities[index].bytes = sample.bytes; activities[index].total = sample.total; activities[index].target = sample.target; activities[index].updated = now; activities[index].state = .downloading
            } else { activities.insert(.init(id: sample.path, target: sample.target, bytes: sample.bytes, total: sample.total, state: .downloading, updated: now), at: 0) }
        }
        for i in activities.indices where activities[i].state == .downloading && current[activities[i].id] == nil {
            let target = activities[i].target
            if let final = current[target], !final.temporary,
               final.bytes >= activities[i].bytes,
               identities[activities[i].id].map({ $0 == final.identifier }) ?? !baseline.contains(target) {
                let last = stable[target]; let count = last?.0 == final.bytes ? (last?.1 ?? 0) + 1 : 1
                stable[target] = (final.bytes, count)
                if count >= 2 { activities[i].state = .complete; activities[i].bytes = final.bytes; activities[i].updated = now }
            } else if now.timeIntervalSince(activities[i].updated) > 15 { activities[i].state = .missing; activities[i].updated = now }
        }
        activities = Array(activities.filter { $0.state == .downloading || now.timeIntervalSince($0.updated) < 3600 }.prefix(50))
        let ids = Set(activities.map(\.id)), targets = Set(activities.map(\.target))
        identities = identities.filter { ids.contains($0.key) }
        stable = stable.filter { targets.contains($0.key) }
    }
    public mutating func clearFinished() { activities.removeAll { $0.state != .downloading }; let ids = Set(activities.map(\.id)), targets = Set(activities.map(\.target)); identities = identities.filter { ids.contains($0.key) }; stable = stable.filter { targets.contains($0.key) } }
}
