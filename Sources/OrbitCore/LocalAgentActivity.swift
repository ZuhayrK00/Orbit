import Foundation

/// A read-only projection of lifecycle metadata. Message text, prompts, tool
/// arguments/output, credentials and usage payloads are not decoded or retained.
public enum AgentActivitySource: String, Codable { case localSession }

public struct LocalAgentSession {
    public let provider: AIProvider
    public private(set) var status: AgentStatus?
    private var session = ""
    private var project = ""
    private var model: String?
    private var child: String?
    private var turn: String?
    private var decoder = JSONDecoder()
    public init(provider: AIProvider) { self.provider = provider }

    public mutating func consume(_ line: Data) {
        guard line.count <= 2_097_152, let row = try? decoder.decode(ActivityEnvelope.self, from: line) else { return }
        if provider == .codex { consumeCodex(row) } else { consumeClaude(row) }
    }
    private mutating func consumeCodex(_ row: ActivityEnvelope) {
        if row.type == "session_meta", let payload = row.payload {
            session = clean(payload.id) ?? session
            project = folder(payload.cwd) ?? project
            return
        }
        if row.type == "turn_context" { model = clean(row.payload?.model); return }
        guard !session.isEmpty, let date = ActivityDate.parse(row.timestamp) else { return }
        let event = row.payload?.type ?? ""
        if row.type == "event_msg" {
            switch event {
            case "task_started", "turn_started":
                let nextTurn = clean(row.payload?.turn_id)
                let sameTurn = nextTurn != nil && nextTurn == turn && status?.phase == .running
                turn = nextTurn
                update(.running, "Working on your request", at: date,
                       start: sameTurn ? status?.startedAt : row.payload?.started_at?.date ?? date)
            case "task_complete", "turn_completed":
                if let next = row.payload?.turn_id, let turn, next != turn { return }
                update(.completed, "Finished", at: row.payload?.completed_at?.date ?? date,
                       start: row.payload?.started_at?.date)
            case "turn_aborted", "task_cancelled": update(.idle, "Interrupted", at: date)
            case "turn_failed", "task_failed": update(.failed, "Task failed", at: date)
            case "item_started", "item_completed", "token_count", "agent_message", "agent_reasoning": heartbeat(at: date)
            default: break
            }
        } else if row.type == "response_item" {
            if ["function_call", "custom_tool_call"].contains(event) { heartbeat(at: date, detail: "Using a tool") }
            else if ["function_call_output", "custom_tool_call_output"].contains(event) { heartbeat(at: date, detail: "Working on your request") }
            else if ["reasoning", "message"].contains(event) { heartbeat(at: date) }
        }
    }
    private mutating func consumeClaude(_ row: ActivityEnvelope) {
        guard ["user", "assistant", "system"].contains(row.type), let date = ActivityDate.parse(row.timestamp) else { return }
        session = clean(row.sessionId) ?? session
        project = folder(row.cwd) ?? project
        child = clean(row.agentId) ?? child
        guard !session.isEmpty else { return }
        if row.type == "user" {
            guard row.isMeta != true else { return }
            if row.toolEndsTurn == true { update(.completed, "Finished", at: date) }
            else if row.message?.contentTypes.contains("tool_result") == true || row.hasToolResult {
                heartbeat(at: date, detail: "Working on your request")
            } else { update(.running, "Working on your request", at: date, start: date) }
        } else if row.type == "assistant" {
            model = clean(row.message?.model) ?? model
            switch row.message?.stop_reason {
            case "end_turn", "stop_sequence": update(.completed, "Finished", at: date)
            case "max_tokens", "refusal": update(.idle, "Response stopped", at: date)
            case "tool_use":
                update(.running, "Using a tool", at: date)
            default: update(.running, "Working on your request", at: date)
            }
        }
    }
    private mutating func heartbeat(at date: Date, detail: String? = nil) {
        if let status {
            guard [.running, .waiting].contains(status.phase) else { return }
            update(status.phase, detail ?? status.detail, at: date)
        } else {
            // A long turn may have started before the bounded recovery tail.
            // Fresh work is still visible, but its unknown start is not invented.
            update(.running, "Working · start time unavailable", at: date)
        }
    }
    private mutating func update(_ phase: AgentPhase, _ detail: String, at date: Date, start: Date? = nil) {
        guard date >= (status?.updatedAt ?? .distantPast) else { return }
        let prefix = provider == .codex ? "codex-" : "claude-"
        let parent = prefix + session
        let active = [.running, .waiting].contains(phase)
        let continuing = status.map { [.running, .waiting].contains($0.phase) } ?? false
        let beginning = start ?? (continuing || !active ? status?.startedAt : nil)
        status = AgentStatus(id: child.map { parent + "/child/" + $0 } ?? parent,
            provider: provider == .codex ? "Codex" : "Claude", title: project.isEmpty ? provider.title : project,
            detail: detail, phase: phase, updatedAt: date, parentID: child == nil ? nil : parent, model: model,
            startedAt: beginning, endedAt: active ? nil : date, source: .localSession)
    }
    private func clean(_ value: String?) -> String? { AgentUsage.clean(value, limit: 256) }
    private func folder(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return clean(URL(fileURLWithPath: value).lastPathComponent)
    }
}

private enum ActivityDate {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
private struct ActivityEnvelope: Decodable {
    let type: String
    let timestamp: String?
    let payload: ActivityPayload?
    let sessionId: String?
    let cwd: String?
    let agentId: String?
    let isMeta: Bool?
    let toolEndsTurn: Bool?
    let message: ActivityMessage?
    let hasToolResult: Bool
    enum CodingKeys: String, CodingKey { case type, timestamp, payload, sessionId, cwd, agentId, isMeta, toolEndsTurn, message, toolUseResult }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        timestamp = try? c.decode(String.self, forKey: .timestamp)
        payload = try? c.decode(ActivityPayload.self, forKey: .payload)
        sessionId = try? c.decode(String.self, forKey: .sessionId)
        cwd = try? c.decode(String.self, forKey: .cwd)
        agentId = try? c.decode(String.self, forKey: .agentId)
        isMeta = try? c.decode(Bool.self, forKey: .isMeta)
        toolEndsTurn = try? c.decode(Bool.self, forKey: .toolEndsTurn)
        message = try? c.decode(ActivityMessage.self, forKey: .message)
        hasToolResult = c.contains(.toolUseResult)
    }
}
private struct ActivityTimestamp: Decodable {
    let date: Date?
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let number = try? value.decode(Double.self), number.isFinite {
            date = Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
        } else { date = ActivityDate.parse(try? value.decode(String.self)) }
    }
}
private struct ActivityPayload: Decodable {
    let type: String?
    let id: String?
    let cwd: String?
    let model: String?
    let turn_id: String?
    let started_at: ActivityTimestamp?
    let completed_at: ActivityTimestamp?
}
private struct ActivityMessage: Decodable {
    let model: String?
    let stop_reason: String?
    let contentTypes: [String]
    enum CodingKeys: String, CodingKey { case model, stop_reason, content }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try? c.decode(String.self, forKey: .model)
        stop_reason = try? c.decode(String.self, forKey: .stop_reason)
        // Claude represents plain prompts as either a string or content blocks.
        // Decode only the block tag; never the text or a tool result's content.
        contentTypes = (try? c.decode([ContentTag].self, forKey: .content))?.map(\.type) ?? []
    }
    private struct ContentTag: Decodable { let type: String }
}

public enum AgentActivity {
    public static func merge(hooks: [AgentStatus], local: [AgentStatus], now: Date) -> [AgentStatus] {
        var sessions: [String: AgentStatus] = [:]
        for status in local + hooks {
            guard status.updatedAt <= now.addingTimeInterval(60) else { continue }
            if let old = sessions[status.id], old.updatedAt > status.updatedAt { continue }
            sessions[status.id] = status
        }
        return sessions.values.sorted {
            let a = rank($0.displayedPhase(now: now)), b = rank($1.displayedPhase(now: now))
            if a != b { return a < b }
            if a < 2 {
                let first = $0.startedAt ?? $0.updatedAt, second = $1.startedAt ?? $1.updatedAt
                return first == second ? $0.id < $1.id : first < second
            }
            return $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }
    }
    private static func rank(_ phase: AgentPhase) -> Int {
        switch phase { case .waiting: return 0; case .running: return 1; case .failed, .completed, .idle, .offline: return 2 }
    }
    public static func live(_ agents: [AgentStatus], now: Date) -> [AgentStatus] {
        agents.filter { [.running, .waiting].contains($0.displayedPhase(now: now)) }
    }
    public static func compact(_ agents: [AgentStatus], now: Date, rotationInterval: TimeInterval = 6) -> AgentStatus? {
        let active = live(agents, now: now)
        let waiting = active.filter { $0.displayedPhase(now: now) == .waiting }
        let pool = (waiting.isEmpty ? active : waiting).sorted { $0.id < $1.id }
        guard !pool.isEmpty else { return nil }
        return pool[Int(max(0, now.timeIntervalSince1970) / max(1, rotationInterval)) % pool.count]
    }
    public static func focused(_ agents: [AgentStatus], selectedID: String?, now: Date) -> AgentStatus? {
        let active = live(agents, now: now)
        let waiting = active.filter { $0.displayedPhase(now: now) == .waiting }
        let pool = waiting.isEmpty ? active : waiting
        if let selected = pool.first(where: { $0.id == selectedID }) { return selected }
        return pool.sorted {
            let lhs = $0.startedAt ?? $0.updatedAt, rhs = $1.startedAt ?? $1.updatedAt
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }.first
    }
    public static func recentCompletion(_ agents: [AgentStatus], now: Date) -> AgentStatus? {
        agents.filter { [.completed, .failed].contains($0.phase) && (0..<12).contains(now.timeIntervalSince($0.endedAt ?? $0.updatedAt)) }
            .max { $0.updatedAt < $1.updatedAt }
    }
}
