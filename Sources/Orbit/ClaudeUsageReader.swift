import Foundation
import OrbitCore

/// A control-only conversation. Never sends a prompt or grants tools/MCP/hooks.
@MainActor final class ClaudeUsageReader {
    private let process = LocalProviderProcess()
    private var buffer = Data()
    private var bytes = 0
    private var continuation: CheckedContinuation<[AgentLimitWindow], Error>?
    private var timeout: Task<Void, Never>?
    private var expected = "orbit.initialize"
    func read(executable: URL, environment: [String: String]) async throws -> [AgentLimitWindow] {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { next in
                continuation = next; buffer = Data(); bytes = 0; expected = "orbit.initialize"
                process.onData = { [weak self] in self?.receive($0) }
                process.onExit = { [weak self] _ in self?.finish(.failure(ProviderProcessError("Claude usage is unavailable; local samples remain available."))) }
                var env = environment; env.removeValue(forKey: "CLAUDECODE")
                do {
                    try process.start(executable: executable, arguments: ["--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}", "--setting-sources", "", "--settings", "{\"disableAllHooks\":true}"], environment: env)
                    try send(id: expected, request: ["subtype": "initialize"])
                } catch { finish(.failure(error)); return }
                timeout = Task { do { try await Task.sleep(nanoseconds: 25_000_000_000) } catch { return }; finish(.failure(ProviderProcessError("Claude usage timed out. Local samples remain available."))) }
            }
        } onCancel: { Task { @MainActor in self.cancel() } }
    }
    private func send(id: String, request: [String: Any]) throws { var data = try JSONSerialization.data(withJSONObject: ["type": "control_request", "request_id": id, "request": request]); data.append(10); try process.write(data) }
    private func receive(_ data: Data) {
        bytes += data.count; guard bytes <= 1_048_576 else { finish(.failure(ProviderProcessError("Claude usage response was too large"))); return }
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any], json["type"] as? String == "control_response",
                  let response = json["response"] as? [String: Any], response["request_id"] as? String == expected else { continue }
            guard response["subtype"] as? String == "success" else { finish(.failure(ProviderProcessError("This Claude Code version cannot provide account usage. Update it or use local samples."))); return }
            if expected == "orbit.initialize" { expected = "orbit.usage"; do { try send(id: expected, request: ["subtype": "get_usage", "skip_behaviors": true]) } catch { finish(.failure(error)) } }
            else {
                let windows = ClaudeUsageProtocol.windows(response["response"] as? [String: Any] ?? [:])
                finish(windows.isEmpty ? .failure(ProviderProcessError("Claude did not report current usage windows. Local samples remain available.")) : .success(windows)); return
            }
        }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<[AgentLimitWindow], Error>) { guard let next = continuation else { return }; continuation = nil; timeout?.cancel(); timeout = nil; process.stop(); next.resume(with: result) }
}
