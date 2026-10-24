import XCTest
@testable import OrbitCore

final class AgentUsageTests: XCTestCase {
    func testCodexPrefersMultipleBucketsAndKeepsUnknownValuesUnknown() {
        let parsed = AgentUsage.codexLimits([
            "rateLimits": ["primary": ["usedPercent": 99]],
            "rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1800000000], "secondary": ["usedPercent": NSNull()]],
                                    "review": ["primary": ["usedPercent": 0, "windowDurationMins": 10080]]]
        ])
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].remainingPercent, 75)
        XCTAssertEqual(parsed[0].label, "Codex · 5h")
        XCTAssertEqual(parsed[0].resetsAt, Date(timeIntervalSince1970: 1800000000))
        XCTAssertEqual(parsed[1].remainingPercent, 100)
        XCTAssertNil(parsed[1].resetsAt)
        XCTAssertTrue(AgentUsage.codexLimits(["rateLimits": ["primary": ["usedPercent": true]]]).isEmpty)
        XCTAssertTrue(AgentUsage.codexLimits(["rateLimitsByLimitId": [:], "rateLimits": ["primary": ["usedPercent": 42]]]).isEmpty)
    }
    func testClaudeMetricsRetainOnlyDisplayMetadata() throws {
        let secret = "PRIVATE_CONTENT"
        let parsed = try XCTUnwrap(AgentSessionMetrics.claude([
            "session_id": "session/one", "workspace": ["project_dir": "/private/project/Orbit"], "model": ["display_name": "Model\nOne"],
            "context_window": ["used_percentage": 42, "total_input_tokens": 1200, "total_output_tokens": 75],
            "rate_limits": ["five_hour": ["used_percentage": 18, "resets_at": 1800000000]], "cost": ["total_cost_usd": 0.25],
            "prompt": secret, "transcript_path": secret, "last_assistant_message": secret
        ]))
        XCTAssertEqual(parsed.project, "Orbit"); XCTAssertEqual(parsed.model, "ModelOne")
        XCTAssertEqual(parsed.inputTokens, 1200); XCTAssertEqual(parsed.outputTokens, 75)
        XCTAssertEqual(parsed.contextUsedPercent, 42); XCTAssertEqual(parsed.limits.first?.remainingPercent, 82)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(parsed), as: UTF8.self).contains(secret))
        let missing = try XCTUnwrap(AgentSessionMetrics.claude(["session_id": "x", "context_window": ["used_percentage": -1, "total_input_tokens": true]]))
        XCTAssertNil(missing.inputTokens); XCTAssertNil(missing.contextUsedPercent); XCTAssertTrue(missing.limits.isEmpty)
    }
    func testMetricsStorageRejectsLinksAndCorruptFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let metrics = try XCTUnwrap(AgentSessionMetrics.claude(["session_id": "../../outside", "model": ["display_name": "Test model"]]))
        try AgentSessionMetrics.write(metrics, directory: folder)
        let target = folder.appendingPathComponent(AgentBridge.fileName(for: metrics.id))
        XCTAssertEqual(AgentSessionMetrics.read(directory: folder).count, 1)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.json"), withDestinationURL: target)
        try Data("broken".utf8).write(to: folder.appendingPathComponent("broken.json"))
        XCTAssertEqual(AgentSessionMetrics.read(directory: folder).count, 1)
    }
    func testStatusLineInstallRestoreAndEditsArePreserved() throws {
        let original: [String: Any] = ["statusLine": ["type": "command", "command": "printf '%s' existing", "padding": 2], "permissions": ["allow": ["Read"]]]
        let installed = try AgentStatusLine.installing(in: original, bridge: "/a path/agent", record: nil)
        XCTAssertTrue(AgentStatusLine.owns(installed.settings, record: installed.record))
        let repeated = try AgentStatusLine.installing(in: installed.settings, bridge: "/a path/agent", record: installed.record)
        XCTAssertTrue(NSDictionary(dictionary: repeated.settings).isEqual(to: installed.settings))
        XCTAssertTrue(NSDictionary(dictionary: try AgentStatusLine.removing(from: installed.settings, record: installed.record)).isEqual(to: original))
        var edited = installed.settings
        var line = try XCTUnwrap(edited["statusLine"] as? [String: Any]); line["padding"] = 9; edited["statusLine"] = line
        XCTAssertThrowsError(try AgentStatusLine.removing(from: edited, record: installed.record))
        let empty = try AgentStatusLine.installing(in: [:], bridge: "/agent", record: nil)
        XCTAssertTrue(try AgentStatusLine.removing(from: empty.settings, record: empty.record).isEmpty)
    }
    func testStatusLineForwardsInputAndOriginalOutputWithoutEvaluatingInput() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Orbit's metrics " + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bridge = folder.appendingPathComponent("bridge"), capture = folder.appendingPathComponent("captured"), forbidden = folder.appendingPathComponent("must-not-exist")
        try Data(("#!/bin/sh\ncat > " + AgentStatusLine.quote(capture.path) + "\nprintf 'hidden-metrics-output'\n").utf8).write(to: bridge)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bridge.path)
        let change = try AgentStatusLine.installing(in: ["statusLine": ["type": "command", "command": "cat"]], bridge: bridge.path, record: nil)
        let command = try XCTUnwrap((change.settings["statusLine"] as? [String: Any])?["command"] as? String)
        let payload = try JSONSerialization.data(withJSONObject: ["session_id": "test", "text": "$(touch \(forbidden.path)) `echo bad` ' \" "])
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh"); process.arguments = ["-c", command]
        process.standardInput = input; process.standardOutput = output
        try process.run(); input.fileHandleForWriting.write(payload); try input.fileHandleForWriting.close()
        let result = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0); XCTAssertEqual(result, payload)
        XCTAssertEqual(try Data(contentsOf: capture), payload); XCTAssertFalse(FileManager.default.fileExists(atPath: forbidden.path))
    }
    func testChildAgentLifecycleDoesNotCompleteItsParent() throws {
        for provider in AIProvider.allCases {
            let command = "/agent " + provider.hookFlag
            let all = try AgentHooks.setting(in: [:], provider: provider, command: command, enabled: true)
            XCTAssertTrue(AgentHooks.contains(in: all, provider: provider, command: command))
            var partial = all; var hooks = try XCTUnwrap(partial["hooks"] as? [String: Any]); hooks.removeValue(forKey: "SubagentStart"); partial["hooks"] = hooks
            XCTAssertFalse(AgentHooks.contains(in: partial, provider: provider, command: command))
            XCTAssertEqual(AgentHooks.installedEvents(in: partial, provider: provider, command: command).count, AgentHooks.events(provider).count - 1)
            let event: [String: Any] = ["hook_event_name": "SubagentStop", "session_id": "parent", "agent_id": "child", "agent_type": "Reviewer", "cwd": "/Orbit"]
            let child = try XCTUnwrap(provider == .claude ? AgentBridge.claudeEvent(event) : AgentBridge.codexHook(event))
            XCTAssertEqual(child.phase, .completed); XCTAssertNotNil(child.parentID)
            XCTAssertNotEqual(child.id, child.parentID); XCTAssertTrue(child.title.contains("Reviewer"))
        }
    }
}
