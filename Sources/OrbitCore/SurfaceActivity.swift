import Foundation

public extension OrbitAction {
    /// Tools stay in the surface that opened them. Only explicit launch actions leave it.
    var utilitySection: OrbitAction? {
        switch self {
        case .compressImage, .convertImage, .zipFiles: return .files
        case .home, .shelf, .downloads, .calendar, .screenText, .files, .clipboard, .sound, .music, .timer, .agents, .textTools, .scratchpad, .keepAwake, .notifications: return self
        case .settings, .wheelProfile, .openURL, .openApp, .shortcut: return nil
        }
    }
    static var surfaceTools: [OrbitAction] { [.home, .shelf, .downloads, .calendar, .screenText, .agents, .music, .timer, .clipboard, .sound, .files, .textTools, .scratchpad, .keepAwake, .notifications] }
}

public enum NotchActivityKind: String, Equatable, Hashable, Identifiable {
    case download, meeting, stopwatch, agent, agentFinished, timer, timerFinished, music, copied, notification, keepAwake
    public var id: String { rawValue }
    public var title: String { section.title }
    public var section: OrbitAction {
        switch self {
        case .download: return .downloads
        case .meeting: return .calendar
        case .stopwatch: return .timer
        case .notification: return .notifications
        case .agent, .agentFinished: return .agents
        case .timer, .timerFinished: return .timer
        case .music: return .music
        case .copied: return .clipboard
        case .keepAwake: return .keepAwake
        }
    }
}

public enum NotchActivity {
    public static func available(timer: Bool, agent: Bool, music: Bool, keepAwake: Bool = false, download: Bool = false, meeting: Bool = false, stopwatch: Bool = false) -> [NotchActivityKind] {
        [(timer, NotchActivityKind.timer), (agent, .agent), (music, .music), (keepAwake, .keepAwake), (download, .download), (meeting, .meeting), (stopwatch, .stopwatch)].compactMap { $0.0 ? $0.1 : nil }
    }
    public static func isRecent(_ date: Date?, now: Date, duration: TimeInterval) -> Bool {
        guard let date else { return false }
        return (0..<duration).contains(now.timeIntervalSince(date))
    }
    /// Notices interrupt briefly; the ongoing activity stays selected instead of rotating.
    public static func choose(waitingAgent: Bool, activeAgent: Bool, timer: Bool, timerFinished: Bool,
                              music: Bool, copiedAt: Date?, now: Date, agentFinished: Bool = false, notification: Bool = false,
                              keepAwake: Bool = false, download: Bool = false, meeting: Bool = false, stopwatch: Bool = false, selection: NotchActivitySelection = .init()) -> NotchActivityKind? {
        if notification { return .notification }
        if waitingAgent { return .agent }
        if timerFinished { return .timerFinished }
        if agentFinished { return .agentFinished }
        if isRecent(copiedAt, now: now, duration: 6) { return .copied }
        return selection.current(in: available(timer: timer, agent: activeAgent, music: music, keepAwake: keepAwake, download: download, meeting: meeting, stopwatch: stopwatch))
    }
}

public struct NotchActivitySelection: Equatable {
    public private(set) var preferred: NotchActivityKind?
    public private(set) var companion: NotchActivityKind?
    public init() {}
    public func current(in available: [NotchActivityKind]) -> NotchActivityKind? {
        preferred.flatMap { available.contains($0) ? $0 : nil } ?? available.first
    }
    public static func companions(for primary: NotchActivityKind?, available: [NotchActivityKind], timerRunning: Bool) -> [NotchActivityKind] {
        guard primary == .timer, timerRunning, available.contains(.timer) else { return [] }
        return available.filter { $0 == .agent || $0 == .music }
    }
    public mutating func select(_ primary: NotchActivityKind, companion: NotchActivityKind? = nil, available: [NotchActivityKind], timerRunning: Bool) {
        guard available.contains(primary) else { return }
        if let companion, !Self.companions(for: primary, available: available, timerRunning: timerRunning).contains(companion) { return }
        preferred = primary; self.companion = companion
    }
    public func visibleCompanion(available: [NotchActivityKind], timerRunning: Bool) -> NotchActivityKind? {
        guard current(in: available) == preferred, let companion else { return nil }
        return Self.companions(for: preferred, available: available, timerRunning: timerRunning).contains(companion) ? companion : nil
    }
    public mutating func reconcile(available: [NotchActivityKind]) {
        if available.isEmpty { preferred = nil; companion = nil }
    }
}
