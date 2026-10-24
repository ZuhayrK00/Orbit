import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import OrbitCore

enum OrbitCLI {
    static func run(_ arguments: [String]) -> Bool {
        guard let command = arguments.first else { return false }
        switch command {
        case "--awake-lid-guard":
            exit(AwakeLidGuard.run(Array(arguments.dropFirst())))
        case "--awake-lid-recover":
            exit(AwakeLidGuard.recover())
        case "--smoke-mixer":
            Task { @MainActor in
                do { try await MixerSmokeTests.run(); exit(0) }
                catch { print(error.localizedDescription); exit(1) }
            }
            RunLoop.main.run(); return true
        case "--smoke-awake":
            Task { @MainActor in
                do { try AwakeSmokeTests.run(); exit(0) }
                catch { print(error.localizedDescription); exit(1) }
            }
            RunLoop.main.run(); return true
        case "--claude-hook", "--codex-hook":
            do {
                let data = try boundedInput(maximum: command == "--agent-event" ? 65_536 : 1_048_576)
                guard data.count <= 1_048_576, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let status = command == "--codex-hook" ? AgentBridge.codexHook(json) : AgentBridge.claudeEvent(json) else { return true }
                try AgentBridge.write(status)
            } catch { /* Hooks must never block or fail the agent. */ }
            return true
        case "--claude-metrics":
            do {
                let data = try boundedInput(maximum: 1_048_576)
                guard data.count <= 1_048_576, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let metrics = AgentSessionMetrics.claude(json) else { return true }
                try AgentSessionMetrics.write(metrics)
                let context = metrics.contextUsedPercent.map { " · \(Int($0))% context" } ?? ""
                print((metrics.model ?? "Claude") + context)
            } catch { /* A metrics failure must not interrupt the existing status line. */ }
            return true
        case "--codex-stream":
            var session = UUID().uuidString
            let title = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).lastPathComponent
            var terminal = false
            while let line = readLine() {
                FileHandle.standardOutput.write(Data((line + "\n").utf8))
                guard line.utf8.count < 1_048_576, let data = line.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if let id = json["thread_id"] as? String { session = id }
                if let status = AgentBridge.codexEvent(json, session: session, title: title) { try? AgentBridge.write(status); terminal = status.phase == .completed || status.phase == .failed }
            }
            if !terminal { try? AgentBridge.write(AgentStatus(id: "codex-" + session, provider: "Codex", title: title, detail: "Event stream ended before a completion event", phase: .offline)) }
            return true
        case "--agent-event":
            do {
                let data = try boundedInput(maximum: command == "--agent-event" ? 65_536 : 1_048_576)
                guard data.count <= 65_536 else { throw FileTools.failure("Agent event is too large.") }
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let status = try decoder.decode(AgentStatus.self, from: data); try AgentBridge.write(status)
            } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
            return true
        case "--render-icon":
            guard arguments.count == 2 else { exit(1) }; renderIcon(URL(fileURLWithPath: arguments[1])); return true
        case "--smoke-files":
            // Real file processing validation, with generated fixtures only.
            Task { do { try await FileSmokeTests.run(); exit(0) } catch { print(error.localizedDescription); exit(1) } }
            RunLoop.main.run(); return true
        case "--smoke-accounts":
            Task { @MainActor in
                do {
                    guard let codex = ProviderRuntime.executable(.codex), let claude = ProviderRuntime.executable(.claude) else { throw FileTools.failure("Install Codex and Claude Code before this device check.") }
                    let rpc = CodexAccountRPC(); defer { rpc.stop() }
                    try await rpc.start(executable: codex, environment: ProviderRuntime.environment(executable: codex))
                    let result = try await rpc.request("account/read", parameters: ["refreshToken": false])
                    print("Codex account protocol: OK; signed in: \(ProviderAccount.codex(result) != nil)")
                    let limits = try await rpc.request("account/rateLimits/read")
                    print("Codex usage protocol: OK; windows: \(AgentUsage.codexLimits(limits).count)")
                    let command = ProviderCommand()
                    let (data, code) = try await command.run(executable: claude, arguments: ["auth", "status", "--json"], environment: ProviderRuntime.environment(executable: claude))
                    guard code == 0 || code == 1, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["loggedIn"] is Bool else { throw FileTools.failure("Claude account response unsupported.") }
                    print("Claude account protocol: OK; signed in: \(ProviderAccount.claude(json) != nil)")
                    print("Read-only account checks complete; no sign-in, hook installation or model calls.")
                    rpc.stop(); exit(0)
                } catch { print(error.localizedDescription); exit(1) }
            }
            RunLoop.main.run(); return true
        case "--inspect-local-activity":
            Task {
                let reader = LocalAgentReader()
                let roots = [LocalAgentRoot(provider: .codex, directory: ProviderRuntime.configurationDirectory(.codex).appendingPathComponent("sessions")), LocalAgentRoot(provider: .claude, directory: ProviderRuntime.configurationDirectory(.claude).appendingPathComponent("projects"))]
                var found: [AgentStatus] = []
                for _ in 0..<12 { found = await reader.scan(roots: roots) }
                let now = Date()
                for provider in ["Codex", "Claude"] {
                    let rows = found.filter { $0.provider == provider }
                    print("\(provider): \(rows.count) recent local sessions; \(AgentActivity.live(rows, now: now).count) active")
                    for row in AgentActivity.live(rows, now: now) {
                        print("  \(row.displayedPhase(now: now).rawValue) · elapsed \(row.elapsed(at: now).map(OrbitTimer.label) ?? "unknown") · local metadata")
                    }
                }
                print("Read-only check complete. No prompts, replies, hooks, permissions or provider tasks were changed.")
                exit(0)
            }
            RunLoop.main.run(); return true
        case "--version": print("Orbit 0.1.0"); return true
        case "--help":
            print("Orbit — free local Mac utility\nOpen normally for the app.\n--claude-hook: Claude Code event JSON on stdin\n--codex-hook: Codex lifecycle event JSON on stdin\n--codex-stream: forward Codex JSONL and publish status\n--claude-metrics: Claude status-line JSON on stdin\n--agent-event: publish a generic AgentStatus JSON on stdin\n--smoke-accounts: read-only checks against installed provider tools\n--inspect-local-activity: inspect local lifecycle metadata without saving it\n--version"); return true
        default: return false
        }
    }
    private static func boundedInput(maximum: Int) throws -> Data {
        var data = Data()
        while let part = try FileHandle.standardInput.read(upToCount: min(16384, maximum + 1 - data.count)), !part.isEmpty {
            data.append(part)
            guard data.count <= maximum else { throw FileTools.failure("Agent input is too large.") }
        }
        return data
    }
    private static func renderIcon(_ url: URL) {
        let size = 1024
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        let rect = CGRect(x: 40, y: 40, width: 944, height: 944)
        context.setFillColor(CGColor(red: 0.07, green: 0.065, blue: 0.10, alpha: 1)); context.addPath(CGPath(roundedRect: rect, cornerWidth: 220, cornerHeight: 220, transform: nil)); context.fillPath()
        let violet = CGColor(red: 0.65, green: 0.52, blue: 1, alpha: 1)
        context.setStrokeColor(violet.copy(alpha: 0.45)!); context.setLineWidth(26); context.strokeEllipse(in: CGRect(x: 260, y: 260, width: 504, height: 504))
        context.saveGState(); context.translateBy(x: 512, y: 512); context.rotate(by: .pi / 5); context.setStrokeColor(violet); context.setLineWidth(28); context.strokeEllipse(in: CGRect(x: -350, y: -135, width: 700, height: 270)); context.restoreGState()
        context.setFillColor(violet); context.fillEllipse(in: CGRect(x: 715, y: 655, width: 108, height: 108))
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
        CGImageDestinationAddImage(destination, image, nil); if !CGImageDestinationFinalize(destination) { exit(1) }
    }
}
