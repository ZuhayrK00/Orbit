import Foundation

public struct MixerLevel: Codable, Equatable {
    public var volume: Double = 1
    public var lastAudible: Double = 1
    public var outputUID: String?
    public init() {}
    public var needsRoute: Bool { abs(volume - 1) > 0.001 || outputUID != nil }
    public mutating func setVolume(_ value: Double) {
        volume = value.isFinite ? min(2, max(0, value)) : 1
        if volume > 0.001 { lastAudible = volume }
    }
    public mutating func toggleMute() { setVolume(volume > 0.001 ? 0 : max(0.01, lastAudible)) }
    public mutating func normalize() {
        volume = volume.isFinite ? min(2, max(0, volume)) : 1
        lastAudible = lastAudible.isFinite ? min(2, max(0.01, lastAudible)) : 1
        if outputUID?.isEmpty == true { outputUID = nil }
    }
}

public struct MixerOptions: Codable, Equatable {
    public var levels: [String: MixerLevel] = [:]
    public var pinned: [String] = []
    public var order: [String] = []
    public var hideInactive = false
    public var showMicrophone = true
    public var enabled = true
    public init() {}
    public mutating func normalize() {
        for key in levels.keys { levels[key]?.normalize() }
        var seen = Set<String>(); pinned = pinned.filter { !$0.isEmpty && seen.insert($0).inserted }
        seen = []; order = order.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    public func ordered(_ ids: [String]) -> [String] {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return ids.enumerated().sorted { a, b in
            let ap = pinned.contains(a.element), bp = pinned.contains(b.element)
            if ap != bp { return ap }
            let ar = rank[a.element] ?? Int.max, br = rank[b.element] ?? Int.max
            return ar == br ? a.offset < b.offset : ar < br
        }.map(\.element)
    }
    public mutating func move(_ id: String, by offset: Int, visible: [String]) {
        var arranged = ordered(visible)
        guard let index = arranged.firstIndex(of: id), arranged.indices.contains(index + offset),
              pinned.contains(id) == pinned.contains(arranged[index + offset]) else { return }
        arranged.swapAt(index, index + offset)
        order = arranged + order.filter { !arranged.contains($0) }
    }
    public func isVisible(_ id: String, playing: Bool) -> Bool {
        !hideInactive || playing || pinned.contains(id) || (levels[id]?.needsRoute ?? false)
    }
    private enum CodingKeys: String, CodingKey { case levels, pinned, order, hideInactive, showMicrophone, enabled }
    public init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        levels = try c.decodeIfPresent([String: MixerLevel].self, forKey: .levels) ?? [:]
        pinned = try c.decodeIfPresent([String].self, forKey: .pinned) ?? []
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        hideInactive = try c.decodeIfPresent(Bool.self, forKey: .hideInactive) ?? false
        showMicrophone = try c.decodeIfPresent(Bool.self, forKey: .showMicrophone) ?? true
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        normalize()
    }
}
