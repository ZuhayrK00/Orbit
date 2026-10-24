import XCTest
@testable import OrbitCore

final class LocalAgentActivityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_791_360_000)
    private func line(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func meta(_ id: String) throws -> Data { try line(["type": "session_meta", "payload": ["id": id, "cwd": "/dev/Example", "base_instructions": "PRIVATE"]]) }
    private func event(_ kind: String, at date: Date, turn: String = "t1") throws -> Data {
        try line(["type": "event_msg", "timestamp": iso(date), "payload": ["type": kind, "turn_id": turn]])
    }
    func testCodexNumericTimesCompletionAndNextTurn() throws {
        var session = LocalAgentSession(provider: .codex)
        session.consume(try meta("one"))
        session.consume(try line(["type": "event_msg", "timestamp": iso(start), "payload": ["type": "task_started", "turn_id": "t1", "started_at": start.timeIntervalSince1970 * 1000]]))
        session.consume(try line(["type": "response_item", "timestamp": iso(start.addingTimeInterval(20)), "payload": ["type": "custom_tool_call", "input": "PRIVATE"]]))
        XCTAssertEqual(session.status?.elapsed(at: start.addingTimeInterval(25)), 25)
        XCTAssertEqual(session.status?.id, "codex-one")
        session.consume(try line(["type": "event_msg", "timestamp": iso(start.addingTimeInterval(41)), "payload": ["type": "task_complete", "turn_id": "t1", "started_at": start.timeIntervalSince1970 * 1000, "completed_at": start.addingTimeInterval(40).timeIntervalSince1970 * 1000, "last_agent_message": "PRIVATE"]]))
        XCTAssertEqual(session.status?.phase, .completed)
        XCTAssertEqual(session.status?.elapsed(at: start.addingTimeInterval(100)), 40)
        session.consume(try event("task_started", at: start.addingTimeInterval(120), turn: "t2"))
        session.consume(try event("task_complete", at: start.addingTimeInterval(121), turn: "t1"))
        XCTAssertEqual(session.status?.phase, .running)
        XCTAssertEqual(session.status?.elapsed(at: start.addingTimeInterval(130)), 10)
        let encoded = try JSONEncoder().encode(XCTUnwrap(session.status))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("PRIVATE"))
        XCTAssertNil(session.status?.progress)
    }
    func testMidTurnRecoveryShowsActivityWithoutInventingItsStart() throws {
        var session = LocalAgentSession(provider: .codex)
        session.consume(try meta("long-running"))
        session.consume(try line(["type": "response_item", "timestamp": iso(start), "payload": ["type": "custom_tool_call"]]))
        XCTAssertEqual(session.status?.phase, .running)
        XCTAssertNil(session.status?.elapsed(at: start.addingTimeInterval(30)))
        session.consume(try event("task_complete", at: start.addingTimeInterval(40)))
        session.consume(try event("token_count", at: start.addingTimeInterval(41)))
        XCTAssertEqual(session.status?.phase, .completed)
    }
    func testClaudeToolResultsDoNotRestartClockAndChildrenStaySeparate() throws {
        var parent = LocalAgentSession(provider: .claude)
        func row(_ type: String, at seconds: Double, message: [String: Any], child: String? = nil) throws -> Data {
            var result: [String: Any] = ["type": type, "timestamp": iso(start.addingTimeInterval(seconds)), "sessionId": "one", "cwd": "/dev/Example", "message": message]
            if let child { result["agentId"] = child; result["isSidechain"] = true }
            return try line(result)
        }
        parent.consume(try row("user", at: 0, message: ["content": "PRIVATE PROMPT"]))
        parent.consume(try row("assistant", at: 10, message: ["stop_reason": "tool_use", "content": [["type": "tool_use", "input": "PRIVATE"]]]))
        parent.consume(try row("user", at: 20, message: ["content": [["type": "tool_result", "content": "PRIVATE"]]]))
        XCTAssertEqual(parent.status?.elapsed(at: start.addingTimeInterval(25)), 25)
        var child = LocalAgentSession(provider: .claude)
        child.consume(try row("user", at: 10, message: ["content": "PRIVATE"], child: "two"))
        child.consume(try row("assistant", at: 30, message: ["stop_reason": "end_turn"], child: "two"))
        XCTAssertEqual(child.status?.id, "claude-one/child/two")
        XCTAssertEqual(child.status?.parentID, parent.status?.id)
        XCTAssertEqual(parent.status?.phase, .running)
        parent.consume(try row("assistant", at: 40, message: ["stop_reason": "end_turn", "content": [["type": "text", "text": "PRIVATE REPLY"]]]))
        XCTAssertEqual(parent.status?.phase, .completed)
        XCTAssertEqual(parent.status?.elapsed(at: start.addingTimeInterval(100)), 40)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(XCTUnwrap(parent.status)), as: UTF8.self).contains("PRIVATE"))
    }
    func testMergeRotationCompletionExpiryAndStaleActivity() {
        let now = start.addingTimeInterval(60)
        let one = AgentStatus(id: "codex-one", provider: "Codex", title: "One", detail: "", phase: .running, updatedAt: now, startedAt: start, source: .localSession)
        let two = AgentStatus(id: "claude-two", provider: "Claude", title: "Two", detail: "", phase: .running, updatedAt: now, startedAt: start.addingTimeInterval(10), source: .localSession)
        var hook = one; hook.phase = .waiting; hook.updatedAt = now.addingTimeInterval(1)
        var merged = AgentActivity.merge(hooks: [hook], local: [one, two], now: now.addingTimeInterval(2))
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(AgentActivity.compact(merged, now: now.addingTimeInterval(2))?.id, one.id)
        merged = AgentActivity.merge(hooks: [], local: [one, two], now: now)
        XCTAssertNotEqual(AgentActivity.compact(merged, now: now)?.id, AgentActivity.compact(merged, now: now.addingTimeInterval(6))?.id)
        XCTAssertNotEqual(AgentActivity.compact(merged, now: now, rotationInterval: 12)?.id, AgentActivity.compact(merged, now: now.addingTimeInterval(12), rotationInterval: 12)?.id)
        var complete = one; complete.phase = .completed; complete.endedAt = now
        XCTAssertEqual(AgentActivity.recentCompletion([complete, two], now: now)?.id, one.id)
        XCTAssertNil(AgentActivity.recentCompletion([complete], now: now.addingTimeInterval(12)))
        XCTAssertEqual(AgentActivity.live([complete, two], now: now).count, 1)
        XCTAssertEqual(one.displayedPhase(now: now.addingTimeInterval(301)), .running)
        XCTAssertEqual(one.displayedPhase(now: now.addingTimeInterval(901)), .offline)
        XCTAssertEqual(NotchActivity.choose(waitingAgent: false, activeAgent: true, timer: false, timerFinished: false, music: false, copiedAt: nil, now: now, agentFinished: true), .agentFinished)
    }
    func testIncrementalReaderHandlesPartialWritesTruncationAndOptOut() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appendingPathComponent("one.jsonl"), b = folder.appendingPathComponent("two.jsonl")
        var first = try meta("one"); first.append(10); first.append(try event("task_started", at: start)); first.append(10)
        try first.write(to: a)
        var second = try meta("two"); second.append(10); second.append(try event("task_started", at: start.addingTimeInterval(10))); second.append(10)
        try second.write(to: b)
        let reader = LocalAgentReader(), roots = [LocalAgentRoot(provider: .codex, directory: folder)]
        let initial = await reader.scan(roots: roots, now: start.addingTimeInterval(30))
        XCTAssertEqual(initial.count, 2)
        let finish = try event("task_complete", at: start.addingTimeInterval(40))
        let handle = try FileHandle(forWritingTo: a); try handle.seekToEnd(); try handle.write(contentsOf: finish.prefix(finish.count / 2)); try handle.close()
        let partial = await reader.scan(roots: roots, now: start.addingTimeInterval(41))
        XCTAssertEqual(partial.first { $0.id == "codex-one" }?.phase, .running)
        let rest = try FileHandle(forWritingTo: a); try rest.seekToEnd(); try rest.write(contentsOf: finish.suffix(finish.count - finish.count / 2) + Data([10])); try rest.close()
        let finished = await reader.scan(roots: roots, now: start.addingTimeInterval(42))
        XCTAssertEqual(finished.first { $0.id == "codex-one" }?.phase, .completed)
        XCTAssertEqual(finished.first { $0.id == "codex-two" }?.phase, .running)
        try Data().write(to: a)
        let truncated = await reader.scan(roots: roots, now: start.addingTimeInterval(43))
        XCTAssertEqual(truncated.count, 1)
        let disabled = await reader.scan(roots: [], now: start.addingTimeInterval(44))
        XCTAssertTrue(disabled.isEmpty)
    }
    func testReaderRejectsSymlinksAndMalformedOrOversizedLines() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("one.jsonl")
        var data = try meta("one"); data.append(10)
        data.append(Data(repeating: 65, count: 2_100_000)); data.append(10)
        data.append(Data("{bad JSON}\n".utf8)); data.append(try event("task_started", at: start)); data.append(10)
        try data.write(to: file)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.jsonl"), withDestinationURL: file)
        let reader = LocalAgentReader(), roots = [LocalAgentRoot(provider: .codex, directory: folder)]
        var found: [AgentStatus] = []
        for _ in 0..<4 { found = await reader.scan(roots: roots, now: start.addingTimeInterval(30)) }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.phase, .running)
    }
}
