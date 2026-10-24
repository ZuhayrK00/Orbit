import Foundation

public struct ProductivityOptions: Codable, Equatable {
    public var downloadsEnabled: Bool? = false
    public var downloadFolder: String?
    public var calendarEnabled: Bool? = false
    public var calendarIDs: [String]?
    public var homeOnOpen: Bool? = false
    public var selectionActionsEnabled: Bool? = false
    public var selectionExcludedApps: [String]?
    public var gestureChordEnabled: Bool? = false
    public var gestureKeyCode: UInt32? = 48
    public var gestureModifiers: UInt32? = 6144
    public var gestureLabel: String?
    public var clipboardPersistence: Bool? = false
    public var clipboardExcludedApps: [String]?
    public var focusMinutes: Int? = 25
    public var breakMinutes: Int? = 5
    public var longBreakMinutes: Int? = 15
    public var focusRounds: Int? = 4
    public init() {}
    public mutating func normalize() {
        focusMinutes = min(180, max(1, focusMinutes ?? 25))
        breakMinutes = min(60, max(1, breakMinutes ?? 5))
        longBreakMinutes = min(120, max(1, longBreakMinutes ?? 15))
        focusRounds = min(12, max(2, focusRounds ?? 4))
        gestureModifiers = (gestureModifiers ?? 6144) & 6912
        if (gestureKeyCode ?? 48) > 127 { gestureKeyCode = 48 }
    }
}

public struct WheelProfile: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var slots: [WheelSlot]
    public var keyCode: UInt32?
    public var modifiers: UInt32?
    public var shortcutLabel: String?
    public init(name: String, actions: [OrbitAction]) { self.name = name; slots = actions.map { WheelSlot(action: $0) } }
    public mutating func normalize() {
        name = String(name.prefix(36)); slots = Array(slots.prefix(12))
        if slots.count < 4 { slots = [.init(action: .home), .init(action: .files), .init(action: .timer), .init(action: .settings)] }
        if let keyCode, keyCode > 127 { self.keyCode = nil }
        modifiers = modifiers.map { $0 & 6912 }
    }
    public static var starters: [WheelProfile] { [
        .init(name: "Work", actions: [.agents, .calendar, .timer, .scratchpad, .screenText, .clipboard]),
        .init(name: "Media", actions: [.music, .sound, .timer, .keepAwake]),
        .init(name: "Files", actions: [.shelf, .downloads, .files, .clipboard])
    ] }
}

public enum StoredItemKind: String, Codable { case text, image, files, link }
public struct StoredItem: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var kind: StoredItemKind
    public var text: String
    public var paths: [String]
    public var asset: String?
    public var bookmarks: [String: Data]?
    public var pinned = false
    public var date = Date()
    public init(kind: StoredItemKind, text: String, paths: [String] = [], asset: String? = nil) {
        self.kind = kind; self.text = text; self.paths = paths; self.asset = asset
    }
    public var signature: String { kind.rawValue + "|" + text + "|" + paths.joined(separator: "\u{1f}") + "|" + (asset ?? "") }
}

public struct NoteDocument: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var title: String
    public var text: String
    public init(title: String = "New note", text: String = "") { self.title = title; self.text = text }
    public mutating func toggleChecklist(line index: Int) {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(index) else { return }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- [ ] ") { lines[index] = lines[index].replacingOccurrences(of: "- [ ] ", with: "- [x] ", options: .anchored, range: lines[index].range(of: "- [ ] ")) }
        else if trimmed.lowercased().hasPrefix("- [x] "), let range = lines[index].range(of: "- [x] ", options: .caseInsensitive) { lines[index].replaceSubrange(range, with: "- [ ] ") }
        text = lines.joined(separator: "\n")
    }
}

public struct FocusCycle: Codable, Equatable {
    public enum Phase: String, Codable { case focus, shortBreak, longBreak }
    public var phase: Phase = .focus
    public var round = 1
    public var running = false
    public init() {}
    public mutating func advance(rounds: Int) {
        if phase == .focus { phase = round >= rounds ? .longBreak : .shortBreak }
        else { round = phase == .longBreak ? 1 : round + 1; phase = .focus }
    }
    public func seconds(_ options: ProductivityOptions) -> Double {
        Double(phase == .focus ? options.focusMinutes ?? 25 : phase == .shortBreak ? options.breakMinutes ?? 5 : options.longBreakMinutes ?? 15) * 60
    }
    public var title: String { phase == .focus ? "Focus · round \(round)" : phase == .shortBreak ? "Short break" : "Long break" }
}
public struct StopwatchState: Codable, Equatable {
    public var started: Date?
    public var accumulated: TimeInterval = 0
    public var laps: [TimeInterval] = []
    public init() {}
    public func elapsed(at now: Date) -> TimeInterval { max(0, accumulated + (started.map { now.timeIntervalSince($0) } ?? 0)) }
    public mutating func toggle(at now: Date) { if started != nil { accumulated = elapsed(at: now); started = nil } else { started = now } }
    public mutating func lap(at now: Date) { laps.insert(elapsed(at: now), at: 0); laps = Array(laps.prefix(100)) }
}

public enum MeetingLink {
    public static func allowed(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        func belongs(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if belongs("zoom.us") || belongs("zoom.com") { return ["/j/", "/s/", "/w/", "/wc/"].contains(where: path.hasPrefix) }
        if host == "meet.google.com" { return path.range(of: #"^/[a-z]{3}-[a-z]{4}-[a-z]{3}$"#, options: .regularExpression) != nil || path.hasPrefix("/lookup/") }
        if ["teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft"].contains(host) { return path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/") }
        if belongs("webex.com") { return path.hasPrefix("/meet/") || path.hasPrefix("/join/") || path.hasSuffix("/j.php") || path.contains("/meeting/") }
        return belongs("whereby.com") && path.count > 1 && !path.hasPrefix("/blog")
    }
    public static func find(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first(where: allowed)
    }
}

/// Saved mixer values remain physical linear gain. Only the control's travel
/// changes, so upgrading never changes existing playback or mute restoration.
public enum MixerCurve {
    public static func gain(position: Double) -> Double { guard position.isFinite else { return 1 }; let p = min(2, max(0, position)); return p <= 1 ? p * p : p }
    public static func position(gain: Double) -> Double { guard gain.isFinite else { return 1 }; let g = min(2, max(0, gain)); return g <= 1 ? sqrt(g) : g }
}

public struct AgentAwakeLease {
    public private(set) var pending: Set<String> = []
    public init() {}
    public mutating func start(ids: [String]) { pending = Set(ids) }
    /// Silence, missing sessions and stale heartbeats never mean completed.
    public mutating func observe(completed: Set<String>, running: Set<String>) { pending.formUnion(running); pending.subtract(completed) }
    public var finished: Bool { pending.isEmpty }
}
