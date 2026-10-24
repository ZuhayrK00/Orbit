import XCTest
@testable import OrbitCore

final class ProviderAccountTests: XCTestCase {
    func testAccountIdentityDistinguishesSubscriptionKeysAndSignedOut() throws {
        let codex = try XCTUnwrap(ProviderAccount.codex(["account": ["type": "chatgpt", "email": " person@example.com\n", "planType": "prolite", "accessToken": "DO-NOT-USE"]]))
        XCTAssertEqual(codex.email, "person@example.com"); XCTAssertEqual(codex.planLabel, "Pro Lite"); XCTAssertTrue(codex.usesSubscription)
        XCTAssertNil(ProviderAccount.codex(["account": NSNull()]))
        XCTAssertNil(ProviderAccount.codex(["account": ["type": "unknown-future-type", "accessToken": "secret"]]))
        XCTAssertFalse(try XCTUnwrap(ProviderAccount.codex(["account": ["type": "apiKey"]])).usesSubscription)
        let claude = try XCTUnwrap(ProviderAccount.claude(["loggedIn": true, "authMethod": "claude.ai", "email": "person@example.com", "subscriptionType": "max", "configDirectory": "/tmp/custom-claude", "accessToken": "DO-NOT-USE"]))
        XCTAssertEqual(claude.planLabel, "Max"); XCTAssertEqual(claude.configurationDirectory, "/tmp/custom-claude"); XCTAssertTrue(claude.usesSubscription)
        XCTAssertNil(ProviderAccount.claude(["loggedIn": false, "email": "stale@example.com", "authMethod": "claude.ai"]))
        XCTAssertNil(ProviderAccount.claude(["loggedIn": true, "authMethod": "none"]))
    }
    func testBrowserLoginRejectsUntrustedDestinations() {
        XCTAssertNotNil(ProviderLoginURL.allowed("https://auth.openai.com/oauth/authorize?state=test"))
        XCTAssertNotNil(ProviderLoginURL.allowed("https://chatgpt.com/auth/login"))
        for url in ["http://auth.openai.com/login", "https://auth.openai.com.evil.test", "https://auth.openai.com@evil.test", "https://name:secret@auth.openai.com", "file:///tmp/login", "https://auth.openai.com:9999", "https://evil.test/?next=https://auth.openai.com"] { XCTAssertNil(ProviderLoginURL.allowed(url)) }
    }
    func testGlobalHookInstallAndRemovalPreserveOtherCommands() throws {
        for provider in AIProvider.allCases {
            let command = "'/tmp/orbit-agent' " + provider.hookFlag
            let original: [String: Any] = ["theme": "dark", "hooks": ["Stop": [["matcher": "special", "hooks": [["type": "command", "command": "notify-me"], ["type": "command", "command": "echo " + command]]]], "Unrelated": ["retain"]]]
            let once = try AgentHooks.setting(in: original, provider: provider, command: command, enabled: true)
            let twice = try AgentHooks.setting(in: once, provider: provider, command: command, enabled: true)
            XCTAssertTrue(AgentHooks.contains(in: twice, provider: provider, command: command))
            let stops = try XCTUnwrap((twice["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
            XCTAssertEqual(stops.count, 2)
            let removed = try AgentHooks.setting(in: twice, provider: provider, command: command, enabled: false)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: removed, options: .sortedKeys), try JSONSerialization.data(withJSONObject: original, options: .sortedKeys))
            XCTAssertFalse(AgentHooks.contains(in: removed, provider: provider, command: command))
            XCTAssertThrowsError(try AgentHooks.setting(in: ["hooks": ["Stop": "invalid"]], provider: provider, command: command, enabled: true))
        }
    }
    func testCodexHookLifecycleWithoutTranscriptOrApprovalOutput() {
        let expected: [(String, AgentPhase)] = [("SessionStart", .idle), ("UserPromptSubmit", .running), ("PermissionRequest", .waiting), ("PostToolUse", .running), ("Stop", .completed), ("Interrupt", .idle), ("SessionEnd", .offline)]
        for (event, phase) in expected {
            let status = AgentBridge.codexHook(["hook_event_name": event, "session_id": "123", "cwd": "/tmp/Project", "prompt": "PRIVATE", "tool_input": ["command": "PRIVATE"], "last_assistant_message": "PRIVATE"])
            XCTAssertEqual(status?.id, "codex-123"); XCTAssertEqual(status?.phase, phase); XCTAssertEqual(status?.title, "Project"); XCTAssertFalse(status?.detail.contains("PRIVATE") ?? true)
        }
        XCTAssertNil(AgentBridge.codexHook(["hook_event_name": "SubagentStop", "session_id": "parent"]))
    }
    @MainActor func testProviderCommandReportsExitAndIgnoresStderr() async throws {
        let command = ProviderCommand()
        let (data, code) = try await command.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf '{\"loggedIn\":false}'; printf 'not-a-display-message' >&2; exit 1"], environment: [:], seconds: 2)
        XCTAssertEqual(code, 1); XCTAssertEqual(String(data: data, encoding: .utf8), "{\"loggedIn\":false}")
    }
    @MainActor func testRPCHandlesFragmentedResponsesNotificationsAndTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-rpc-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture")
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
            case "$line" in
                *'"initialize"'*) printf 'not json\\n'; printf '{"id":1,"res'; printf 'ult":{}}\\n' ;;
                *'account'* ) printf '{"method":"account/updated","params":{"authMode":"chatgpt"}}\\n{"id":2,"result":{"account":{"type":"chatgpt","planType":"plus"}}}\\n' ;;
            esac
        done
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let rpc = CodexAccountRPC(); var notifications: [String] = []
        rpc.onNotification = { name, _ in notifications.append(name) }
        defer { rpc.stop() }
        try await rpc.start(executable: executable, environment: [:])
        let result = try await rpc.request("account/read", seconds: 2)
        XCTAssertEqual(ProviderAccount.codex(result)?.plan, "plus")
        XCTAssertEqual(notifications, ["account/updated"])
        do { _ = try await rpc.request("unanswered", seconds: 0.1); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("respond in time")) }
    }
}
