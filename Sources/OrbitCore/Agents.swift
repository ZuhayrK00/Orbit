import Foundation
import CryptoKit

public enum AgentPhase: String, Codable, CaseIterable { case running, waiting, completed, failed, idle, offline }
public struct AgentStatus: Codable, Identifiable, Equatable {
    public var id: String
    public var provider: String
    public var title: String
    public var detail: String
    public var phase: AgentPhase
    public var updatedAt: Date
    public var progress: Double?
    public var parentID: String?
    public var model: String?
    public var startedAt: Date?
    public var endedAt: Date?
    public var source: AgentActivitySource?
    public init(id: String, provider: String, title: String, detail: String, phase: AgentPhase, updatedAt: Date = Date(), progress: Double? = nil, parentID: String? = nil, model: String? = nil, startedAt: Date? = nil, endedAt: Date? = nil, source: AgentActivitySource? = nil) {
        self.id = id; self.provider = provider; self.title = title; self.detail = detail
        self.phase = phase; self.updatedAt = updatedAt; self.progress = progress.map { min(1, max(0, $0)) }; self.parentID = parentID; self.model = model; self.startedAt = startedAt; self.endedAt = endedAt; self.source = source
    }
    public func elapsed(at now: Date) -> TimeInterval? {
        guard let startedAt else { return nil }
        let active = [.running, .waiting].contains(displayedPhase(now: now))
        return max(0, (active ? now : endedAt ?? updatedAt).timeIntervalSince(startedAt))
    }
    public func displayedPhase(now: Date = Date()) -> AgentPhase {
        if (phase == .running || phase == .waiting), now.timeIntervalSince(updatedAt) > (source == .localSession ? 900 : 300) { return .offline }
        return phase
    }
}
public enum AgentBridge {
    public static func fileName(for id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined() + ".json"
    }
    public static func write(_ status: AgentStatus, directory: URL = OrbitPaths.agents) throws {
        var status = status
        status.id = String(status.id.prefix(4096)); status.provider = String(status.provider.prefix(64))
        status.title = String(status.title.prefix(128)); status.detail = String(status.detail.prefix(512))
        status.parentID = status.parentID.map { String($0.prefix(4096)) }; status.model = AgentUsage.clean(status.model)
        status.progress = status.progress.map { min(1, max(0, $0)) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let target = directory.appendingPathComponent(fileName(for: status.id))
        // Keep one elapsed clock across tool callbacks, waits and completion.
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let metadata = try? target.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]),
           metadata.isSymbolicLink != true, (metadata.fileSize ?? 0) <= 65_536,
           let data = try? Data(contentsOf: target), let previous = try? decoder.decode(AgentStatus.self, from: data), previous.id == status.id {
            guard status.updatedAt >= previous.updatedAt else { return }
            if status.startedAt == nil {
                if [.running, .waiting].contains(previous.phase) || ![.running, .waiting].contains(status.phase) {
                    status.startedAt = previous.startedAt
                }
            }
            if ![.running, .waiting].contains(status.phase) { status.endedAt = previous.endedAt }
            status.model = status.model ?? previous.model
        }
        if status.startedAt == nil, [.running, .waiting].contains(status.phase) { status.startedAt = status.updatedAt }
        if let start = status.startedAt { status.startedAt = min(start, status.updatedAt) }
        if [.running, .waiting].contains(status.phase) { status.endedAt = nil }
        else if status.startedAt != nil { status.endedAt = status.endedAt ?? status.updatedAt }
        try encoder.encode(status).write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    public static func read(directory: URL = OrbitPaths.agents) -> [AgentStatus] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey])) ?? []
        return files.filter { $0.pathExtension == "json" }.prefix(100).compactMap { url in
            guard let metadata = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]), metadata.isSymbolicLink != true,
                  (metadata.fileSize ?? 0) <= 65_536, let data = try? Data(contentsOf: url),
                  let status = try? decoder.decode(AgentStatus.self, from: data) else { return nil }
            guard status.progress.map({ $0.isFinite && (0...1).contains($0) }) ?? true else { return nil }
            return status
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    public static func claudeEvent(_ json: [String: Any]) -> AgentStatus? {
        guard let event = json["hook_event_name"] as? String, let session = json["session_id"] as? String, !session.isEmpty else { return nil }
        let cwd = json["cwd"] as? String ?? "Claude Code"
        let phase: AgentPhase
        let detail: String
        switch event {
        case "UserPromptSubmit": phase = .running; detail = "Working on your request"
        case "PreToolUse": phase = .running; detail = "Using \(json["tool_name"] as? String ?? "a tool")"
        case "PostToolUse": phase = .running; detail = "Tool finished; continuing"
        case "PostToolUseFailure": phase = .running; detail = "Tool returned an error; checking next step"
        case "PermissionRequest": phase = .waiting; detail = "Needs your approval in Claude"
        case "Notification":
            let kind = json["notification_type"] as? String ?? ""
            phase = kind == "permission_prompt" ? .waiting : .idle; detail = kind == "permission_prompt" ? "Needs your approval in Claude" : "Claude has a notification"
        case "Stop": phase = .completed; detail = "Response finished"
        case "StopFailure": phase = .failed; detail = "Response failed"
        case "SubagentStart": phase = .running; detail = "Subagent started"
        case "SubagentStop": phase = .completed; detail = "Subagent finished"
        case "SessionEnd": phase = .offline; detail = "Session closed"
        case "SessionStart": phase = .idle; detail = "Session connected"
        default: return nil
        }
        return hookStatus(json, session: session, provider: "Claude", prefix: "claude-", cwd: cwd, detail: detail, phase: phase)
    }
    public static func codexEvent(_ json: [String: Any], session: String, title: String) -> AgentStatus? {
        guard let type = json["type"] as? String else { return nil }
        let phase: AgentPhase; let detail: String
        switch type {
        case "thread.started": phase = .idle; detail = "Session connected"
        case "turn.started": phase = .running; detail = "Working on your request"
        case "turn.completed": phase = .completed; detail = "Turn completed"
        case "turn.failed", "error": phase = .failed; detail = "Codex reported an error"
        case "item.started", "item.updated", "item.completed":
            let item = json["item"] as? [String: Any] ?? [:]
            let itemType = item["type"] as? String ?? "task"
            phase = .running
            detail = itemType == "command_execution" ? "\(type == "item.completed" ? "Finished" : "Running") a command" : "Updating \(itemType.replacingOccurrences(of: "_", with: " "))"
        default: return nil
        }
        return AgentStatus(id: "codex-" + session, provider: "Codex", title: title, detail: detail, phase: phase, startedAt: type == "turn.started" ? Date() : nil)
    }
    public static func codexHook(_ json: [String: Any]) -> AgentStatus? {
        guard let event = json["hook_event_name"] as? String, let session = json["session_id"] as? String, !session.isEmpty else { return nil }
        let phase: AgentPhase; let detail: String
        switch event {
        case "SessionStart": phase = .idle; detail = "Session connected"
        case "UserPromptSubmit": phase = .running; detail = "Working on your request"
        case "PreToolUse": phase = .running; detail = "Using a tool"
        case "PostToolUse": phase = .running; detail = "Tool finished; continuing"
        case "PermissionRequest": phase = .waiting; detail = "Needs your approval in Codex"
        case "PreCompact", "PostCompact": phase = .running; detail = "Updating session context"
        case "Stop": phase = .completed; detail = "Response finished"
        case "Interrupt": phase = .idle; detail = "Turn interrupted"
        case "SubagentStart": phase = .running; detail = "Subagent started"
        case "SubagentStop": phase = .completed; detail = "Subagent finished"
        case "SessionEnd": phase = .offline; detail = "Session closed"
        default: return nil
        }
        return hookStatus(json, session: session, provider: "Codex", prefix: "codex-", cwd: json["cwd"] as? String ?? "Codex", detail: detail, phase: phase)
    }
    private static func hookStatus(_ json: [String: Any], session: String, provider: String, prefix: String, cwd: String, detail: String, phase: AgentPhase) -> AgentStatus? {
        let childEvent = ["SubagentStart", "SubagentStop"].contains(json["hook_event_name"] as? String ?? "")
        let child = AgentUsage.clean(json["agent_id"], limit: 256)
        guard !childEvent || child != nil else { return nil }
        let parent = prefix + session
        let title = URL(fileURLWithPath: cwd).lastPathComponent
        let type = AgentUsage.clean(json["agent_type"], limit: 64)
        return AgentStatus(id: childEvent ? parent + "/child/" + child! : parent, provider: provider,
            title: childEvent ? title + " · " + (type ?? "Subagent") : title, detail: detail, phase: phase,
            parentID: childEvent ? parent : nil, model: AgentUsage.clean(json["model"]),
            startedAt: ["UserPromptSubmit", "SubagentStart"].contains(json["hook_event_name"] as? String ?? "") ? Date() : nil)
    }

}
