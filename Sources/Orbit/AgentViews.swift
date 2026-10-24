import SwiftUI
import AppKit
import OrbitCore

struct AgentsView: View {
    @Environment(\.orbitSurface) private var surface
    @ObservedObject var store: OrbitStore
    var compact: Bool
    @State private var connectionMessage: String?
    @State private var usageExpanded = false
    @State private var recentExpanded = false
    private var live: [AgentStatus] { store.activeAgents }
    private var recent: [AgentStatus] { store.agents.filter { ![.running, .waiting].contains($0.displayedPhase(now: store.now)) } }
    var body: some View {
        if surface == .notch { NotchAgentsView(store: store) }
        else { standardContent }
    }
    private var standardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact { SectionTitle(title: "Keep your agents in sight.", subtitle: "Connect your accounts. Keep your agents close.") }
            if !compact {
                ProviderAccountCard(connection: store.codexAccount, lastEvent: store.agents.first { $0.provider == "Codex" }?.updatedAt)
                ProviderAccountCard(connection: store.claudeAccount, lastEvent: store.agents.first { $0.provider == "Claude" }?.updatedAt)
                HStack { Text("Activity on this Mac").font(.system(size: 15, weight: .semibold)); Spacer(); Text("Live status").font(.system(size: 11)).foregroundStyle(.secondary) }.padding(.top, 8)
            }
            if compact {
                HStack(spacing: 8) {
                    CompactConnectionRow(connection: store.codexAccount) { store.showConnections() }
                    CompactConnectionRow(connection: store.claudeAccount) { store.showConnections() }
                }
            }
            if store.agents.isEmpty {
                if compact {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ready for your next task").font(.system(size: 12, weight: .medium))
                        Text(store.codexAccount.localMonitoringEnabled || store.claudeAccount.localMonitoringEnabled ? "Watching local sessions. Start a prompt in Codex or Claude Code and its status will appear here." : "Enable local session activity in Connections to see running agents here.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.horizontal, 4).padding(.top, 8)
                } else { OrbitCard { EmptyState(symbol: "sparkles", title: "A quiet orbit", detail: "Your agents appear after their next local update. Restart a newly connected session and review any hook permissions.") } }
            }
            ForEach(Array(live.prefix(12))) { agent in
                AgentSessionCard(agent: agent, now: store.now, reduceMotion: store.reduceMotion) { store.dismissAgent(agent) }
            }
            if live.isEmpty, let latest = recent.first {
                AgentSessionCard(agent: latest, now: store.now, reduceMotion: store.reduceMotion) { store.dismissAgent(latest) }
            }
            if recent.count > (live.isEmpty ? 1 : 0) {
                DisclosureGroup("Recent sessions (\(recent.count))", isExpanded: $recentExpanded) {
                    VStack(spacing: 8) {
                        ForEach(Array((live.isEmpty ? Array(recent.dropFirst()) : recent).prefix(12))) { agent in
                            AgentSessionCard(agent: agent, now: store.now, reduceMotion: store.reduceMotion) { store.dismissAgent(agent) }
                        }
                    }.padding(.top, 8)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if compact {
                DisclosureGroup("Plan usage", isExpanded: $usageExpanded) { CodexUsageView(connection: store.codexAccount).padding(.top, 10) }.font(.system(size: 11))
            }
            ForEach(Array(store.agentMetrics.prefix(compact ? 1 : 3))) { metrics in
                AgentMetricsCard(metrics: metrics, compact: compact)
            }
            if !compact {
                Text("Orbit links the provider account used on this Mac. Activity comes from supported local Codex and Claude Code sessions; signing in alone doesn’t import web chats or cloud jobs.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Other ways to connect activity") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Connect just one Claude project, or use the Codex command wrapper with older versions. These use the provider’s existing sign-in.").font(.system(size: 12)).foregroundStyle(.secondary)
                        HStack { Button("Choose Claude project") { installClaude() }.buttonStyle(OrbitButtonStyle()); Button("Create Codex wrapper") { installCodex() }.buttonStyle(OrbitButtonStyle()) }
                        Button("Open status folder") { NSWorkspace.shared.open(OrbitPaths.agents) }.buttonStyle(OrbitButtonStyle())
                        if let connectionMessage { Text(connectionMessage).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    }.padding(.top, 12)
                }.font(.system(size: 12))
                Label("Account checks and activity monitoring make no model calls.", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private func installClaude() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Connect project"; panel.message = "Add Orbit status hooks to this project’s .claude/settings.local.json. Existing settings are preserved."
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do { try AgentInstaller.installClaude(directory: directory); connectionMessage = "Connected \(directory.lastPathComponent). Restart Claude Code in that project to load its hooks." }
        catch { store.error = error.localizedDescription }
    }
    private func installCodex() {
        do { let wrapper = try AgentInstaller.installCodex(); store.copy(AgentInstaller.shellQuote(wrapper.path) + " 'Your task here'"); connectionMessage = "Wrapper created at \(wrapper.path). An example command is copied. Running it starts a Codex task using your existing account; normal Codex usage limits still apply." }
        catch { store.error = error.localizedDescription }
    }
}

private struct NotchAgentsView: View {
    @ObservedObject var store: OrbitStore
    @Environment(\.notchToolBudget) private var budget
    @State private var section = 0
    private var recent: [AgentStatus] { store.agents.filter { ![.running, .waiting].contains($0.displayedPhase(now: store.now)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CompactConnectionRow(connection: store.codexAccount) { store.showConnections() }
                CompactConnectionRow(connection: store.claudeAccount) { store.showConnections() }
            }
            OrbitSegmentedPicker(selection: $section, options: [("Activity", 0), ("Recent · \(recent.count)", 1), ("Plan usage", 2)])
            if section == 2 {
                CodexUsageView(connection: store.codexAccount)
                CodexUsageView(connection: store.claudeAccount)
                NotchPagedList(items: store.agentMetrics, heightBudget: max(160, budget - 350), maximumRows: 1) { metrics in
                    AgentMetricsCard(metrics: metrics, compact: true)
                }
            } else {
                let sessions = section == 1 ? recent : store.activeAgents.isEmpty ? Array(recent.prefix(1)) : store.activeAgents
                if sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section == 1 ? "No recent sessions" : "Ready for your next task").font(.system(size: 12, weight: .medium))
                        Text(section == 1 ? "Completed tasks will appear here." : store.codexAccount.localMonitoringEnabled || store.claudeAccount.localMonitoringEnabled ? "Start a prompt in Codex or Claude Code. Orbit is watching local sessions." : "Enable local session activity in Connections to see running agents here.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 8)
                } else {
                    NotchPagedList(items: sessions, heightBudget: max(140, budget - 130)) { agent in
                        AgentSessionCard(agent: agent, now: store.now, reduceMotion: store.reduceMotion) { store.dismissAgent(agent) }
                    }.id(section)
                }
            }
        }
    }
}

struct AgentSessionCard: View {
    let agent: AgentStatus
    let now: Date
    let reduceMotion: Bool
    let dismiss: () -> Void
    private var phase: AgentPhase { agent.displayedPhase(now: now) }
    private var active: Bool { [.running, .waiting].contains(phase) }
    var body: some View {
        OrbitCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    AgentProviderIcon(provider: AIProvider(activityName: agent.provider))
                    Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(phase.color)
                        .symbolEffect(.pulse, options: .repeating, isActive: phase == .running && !reduceMotion)
                    Text(agent.provider).font(.system(size: 12, weight: .semibold))
                    if agent.parentID != nil { Image(systemName: "arrow.triangle.branch").font(.system(size: 9)).foregroundStyle(.secondary).help("Subagent") }
                    Spacer()
                    if let elapsed = agent.elapsed(at: now) { Text(OrbitTimer.label(elapsed)).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(phase.color) }
                    Text(phase.label).font(.system(size: 10, weight: .medium)).foregroundStyle(phase.color)
                }
                HStack(spacing: 12) {
                    Text(agent.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if let model = agent.model { Text(model).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                }
                Text(agent.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if let progress = agent.progress, phase == .running { ProgressView(value: progress).tint(phase.color) }
                if !active {
                    HStack {
                        Text(agent.updatedAt, style: .relative).font(.system(size: 9)).foregroundStyle(.secondary)
                        Spacer(); Button("Dismiss", action: dismiss).font(.system(size: 9)).foregroundStyle(.secondary).buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct CompactConnectionRow: View {
    @ObservedObject var connection: AgentAccountConnection
    var manage: () -> Void
    var body: some View {
        Button(action: manage) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    AgentProviderIcon(provider: connection.provider)
                    Text(connection.provider == .codex ? "Codex" : "Claude").font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Circle().fill(connection.state == .connected ? Color.mint : .secondary.opacity(0.5)).frame(width: 5, height: 5)
                }
                Text(connection.localMonitoringEnabled ? connection.lastLocalActivity == nil ? "Watching local sessions" : "Local activity detected" : connection.state == .connected ? "Connected · activity off" : connection.busy ? "Checking…" : "Connect account")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(connection.provider.title), \(connection.state == .connected ? "Connected" : "Set up connection")")
    }
}
struct ConnectionSettingsView: View {
    @ObservedObject var store: OrbitStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProviderAccountCard(connection: store.codexAccount, lastEvent: store.agents.first { $0.provider == "Codex" }?.updatedAt)
            ProviderAccountCard(connection: store.claudeAccount, lastEvent: store.agents.first { $0.provider == "Claude" }?.updatedAt)
            AdvancedAgentConnectionsView(store: store)
            Text("Live sessions, timers and usage appear in the notch, wheel and menu bar. These connections use your existing provider accounts; Orbit makes no model calls. Activity is available from supported local sessions, after any provider hook review.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}


struct AdvancedAgentConnectionsView: View {
    @ObservedObject var store: OrbitStore
    @State private var connectionMessage: String?
    var body: some View {
        DisclosureGroup("Other ways to connect activity") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect one Claude project, or use a Codex command wrapper with older clients.").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Button("Choose Claude project") { installClaude() }.buttonStyle(OrbitButtonStyle())
                    Button("Create Codex wrapper") { installCodex() }.buttonStyle(OrbitButtonStyle())
                }
                Button("Open status folder") { NSWorkspace.shared.open(OrbitPaths.agents) }.buttonStyle(OrbitButtonStyle())
                if let connectionMessage { Text(connectionMessage).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            }.padding(.top, 12)
        }.font(.system(size: 12))
    }
    private func installClaude() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Connect project"; panel.message = "Add Orbit status hooks to this project’s .claude/settings.local.json. Existing settings are preserved."
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do { try AgentInstaller.installClaude(directory: directory); connectionMessage = "Connected \(directory.lastPathComponent). Restart Claude Code in that project to load its hooks." }
        catch { store.error = error.localizedDescription }
    }
    private func installCodex() {
        do { let wrapper = try AgentInstaller.installCodex(); store.copy(AgentInstaller.shellQuote(wrapper.path) + " 'Your task here'"); connectionMessage = "Wrapper created at \(wrapper.path). An example command is copied. Running it starts a Codex task using your existing account; normal Codex usage limits still apply." }
        catch { store.error = error.localizedDescription }
    }
}

enum AgentInstaller {
    /// Upgrade only the executable for an already-installed Orbit connection.
    /// Provider hook definitions, approvals and the original status line stay intact.
    static func refreshInstalledBridge() throws {
        let installed = [AIProvider.codex, .claude].contains {
            installedHookCount($0, directory: ProviderRuntime.configurationDirectory($0)) > 0
        } || hasClaudeMetrics(directory: ProviderRuntime.configurationDirectory(.claude))
        if installed && !bridgeIsCurrent { _ = try bridgeBinary() }
    }
    static var bridgeURL: URL { OrbitPaths.support.appendingPathComponent("bin/orbit-agent") }
    static func hookCommand(_ provider: AIProvider) -> String { shellQuote(bridgeURL.path) + " " + provider.hookFlag }
    static func hooksURL(_ provider: AIProvider, directory: URL) -> URL { directory.appendingPathComponent(provider == .codex ? "hooks.json" : "settings.json") }
    static func hasGlobalHooks(_ provider: AIProvider, directory: URL) -> Bool {
        guard let data = try? Data(contentsOf: hooksURL(provider, directory: directory)), data.count <= 2_097_152,
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return AgentHooks.contains(in: settings, provider: provider, command: hookCommand(provider))
    }
    static var bridgeIsCurrent: Bool {
        guard let executable = Bundle.main.executableURL, FileManager.default.isExecutableFile(atPath: bridgeURL.path) else { return false }
        return FileManager.default.contentsEqual(atPath: executable.path, andPath: bridgeURL.path)
    }
    static func installedHookCount(_ provider: AIProvider, directory: URL) -> Int {
        guard let data = try? Data(contentsOf: hooksURL(provider, directory: directory)), data.count <= 2_097_152,
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        return AgentHooks.installedEvents(in: settings, provider: provider, command: hookCommand(provider)).count
    }
    private static func metricsRecordURL(directory: URL) -> URL {
        OrbitPaths.support.appendingPathComponent("connections", isDirectory: true).appendingPathComponent("claude-statusline-" + AgentBridge.fileName(for: directory.path))
    }
    static func hasClaudeMetrics(directory: URL) -> Bool {
        guard let data = try? Data(contentsOf: hooksURL(.claude, directory: directory)), data.count <= 2_097_152,
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recordData = try? Data(contentsOf: metricsRecordURL(directory: directory)), recordData.count <= 2_097_152,
              let record = try? JSONSerialization.jsonObject(with: recordData) as? [String: Any] else { return false }
        return AgentStatusLine.owns(settings, record: record)
    }
    static func setClaudeMetrics(directory: URL, enabled: Bool) throws {
        let url = hooksURL(.claude, directory: directory)
        let original = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        guard (original?.count ?? 0) <= 2_097_152 else { throw FileTools.failure("Claude settings are too large to update safely.") }
        let settings = try original.map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        guard let settings else { throw FileTools.failure("Claude settings are unreadable; they were left unchanged.") }
        let recordURL = metricsRecordURL(directory: directory)
        let record = (try? Data(contentsOf: recordURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let result: [String: Any]
        if enabled {
            let change = try AgentStatusLine.installing(in: settings, bridge: bridgeURL.path, record: record)
            _ = try bridgeBinary()
            try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: change.record, options: [.sortedKeys]).write(to: recordURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)
            result = change.settings
        } else {
            guard let record else { throw FileTools.failure("The original status-line record is unavailable. Your settings were left unchanged.") }
            result = try AgentStatusLine.removing(from: settings, record: record)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let original {
            let backup = directory.appendingPathComponent("settings.json.orbit-backup-" + UUID().uuidString)
            try original.write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        let current = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        guard original == current else { throw FileTools.failure("Claude settings changed while connecting. Try again; your edits were preserved.") }
        try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func setGlobalHooks(_ provider: AIProvider, directory: URL, enabled: Bool) throws {
        let url = hooksURL(provider, directory: directory)
        let existing = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        var settings: [String: Any] = [:]
        if let existing {
            guard existing.count <= 2_097_152, let parsed = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else { throw FileTools.failure("Existing provider settings could not be read safely. They were left unchanged.") }
            settings = parsed
        }
        let updated = try AgentHooks.setting(in: settings, provider: provider, command: hookCommand(provider), enabled: enabled)
        let result = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys])
        if enabled { _ = try bridgeBinary() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let existing {
            let backup = directory.appendingPathComponent(url.lastPathComponent + ".orbit-backup-" + UUID().uuidString)
            try existing.write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        // Refuse to overwrite a provider/settings edit made while preparing this update.
        let current = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        guard current == existing else { throw FileTools.failure("Provider settings changed while Orbit was connecting. Try again; those changes were preserved.") }
        try result.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func bridgeBinary() throws -> URL {
        let directory = OrbitPaths.support.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let executable = Bundle.main.executableURL else { throw FileTools.failure("Orbit’s executable was not found.") }
        let target = directory.appendingPathComponent("orbit-agent")
        let staging = directory.appendingPathComponent("orbit-agent-" + UUID().uuidString)
        try FileManager.default.copyItem(at: executable, to: staging)
        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: staging) } else { try FileManager.default.moveItem(at: staging, to: target) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        return target
    }
    static func installClaude(directory: URL) throws {
        let folder = directory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("settings.local.json")
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FileTools.failure("Existing Claude settings are not a JSON object. They were left untouched.") }
            settings = parsed
            try data.write(to: folder.appendingPathComponent("settings.local.orbit-backup-" + UUID().uuidString + ".json"), options: .atomic)
        }
        let binary = try bridgeBinary()
        let command = shellQuote(binary.path) + " --claude-hook"
        settings = try AgentHooks.addingClaude(to: settings, command: command)
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
    static func installCodex() throws -> URL {
        let binary = try bridgeBinary(), wrapper = binary.deletingLastPathComponent().appendingPathComponent("orbit-codex")
        let script = "#!/bin/bash\nset -o pipefail\nORBIT_CODEX_BIN=\"${ORBIT_CODEX_BIN:-codex}\"\n\"$ORBIT_CODEX_BIN\" exec --json \"$@\" | " + shellQuote(binary.path) + " --codex-stream\n"
        try Data(script.utf8).write(to: wrapper, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        return wrapper
    }
}

struct ProviderAccountCard: View {
    @ObservedObject var connection: AgentAccountConnection
    var lastEvent: Date?
    var body: some View {
        OrbitCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 13) {
                    AgentProviderIcon(provider: connection.provider, size: 22)
                        .frame(width: 34, height: 34).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(connection.provider.title).font(.system(size: 16, weight: .semibold))
                        Text(connection.account?.displayName ?? (connection.provider == .codex ? "Your ChatGPT account" : "Your Claude account, through Claude Code")).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    if connection.busy { ProgressView().controlSize(.small) }
                    else if connection.state == .connected { StatusPill(title: "Connected", color: .green) }
                }
                if let account = connection.account {
                    HStack(spacing: 8) {
                        Text(account.planLabel).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 5).background(Color.primary.opacity(0.05), in: Capsule())
                        Text(account.usesSubscription ? "Uses your existing provider sign-in" : "Existing API/provider credentials; provider usage may be billed").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    if connection.busy {
                        Button("Cancel") { connection.cancelSignIn() }.buttonStyle(OrbitButtonStyle())
                    } else if connection.state == .connected {
                        Button(connection.activityNeedsRepair ? "Repair activity" : connection.activityInstalled ? "Stop activity" : "Enable activity") { connection.setActivity(connection.activityNeedsRepair || !connection.activityInstalled) }.buttonStyle(OrbitButtonStyle(prominent: !connection.activityInstalled || connection.activityNeedsRepair))
                        if connection.activityNeedsRepair { Button("Stop") { connection.setActivity(false) }.buttonStyle(OrbitButtonStyle()) }
                        Button { connection.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(OrbitIconButtonStyle()).help("Refresh account").accessibilityLabel("Refresh account")
                        Spacer()
                        Button("Unlink account") { connection.disconnect() }.font(.system(size: 11)).foregroundStyle(.secondary).buttonStyle(.plain).help("Stops Orbit’s account checks. Your provider remains signed in; activity can be stopped separately.")
                    } else {
                        Button(connection.state == .missing ? "Check installation" : "Connect account") { connection.connect() }.buttonStyle(OrbitButtonStyle(prominent: true))
                        if connection.state == .missing { Button("Install \(connection.provider.title)") { NSWorkspace.shared.open(connection.installationURL) }.buttonStyle(OrbitButtonStyle()) }
                        if connection.activityInstalled { Button("Stop activity") { connection.setActivity(false) }.buttonStyle(OrbitButtonStyle()) }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Local session activity").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Toggle("Local session activity", isOn: Binding(get: { connection.localMonitoringEnabled }, set: { connection.setLocalMonitoring($0) })).labelsHidden()
                    }
                    Text("Detect running tasks directly on this Mac, including sessions already open. Reads lifecycle metadata only; no prompt text or replies are saved or sent.").font(.system(size: 11)).foregroundStyle(.secondary)
                    if let date = connection.lastLocalActivity {
                        HStack(spacing: 4) { Image(systemName: "checkmark.circle"); Text("Local activity seen"); Text(date, style: .relative); Text("ago") }.font(.system(size: 10)).foregroundStyle(.mint)
                    }
                }
                if connection.activityInstalled {
                    Label(connection.activityNeedsRepair ? "Activity hooks need an update" : "Optional lifecycle hooks installed", systemImage: connection.activityNeedsRepair ? "wrench.and.screwdriver" : "waveform.path").font(.system(size: 11, weight: .medium)).foregroundStyle(connection.activityNeedsRepair ? Color.orange : OrbitDesign.accent(.mint))
                    if let lastEvent { HStack(spacing: 4) { Text("Last event"); Text(lastEvent, style: .relative); Text("ago") }.font(.system(size: 10)).foregroundStyle(.secondary) }
                    Text(connection.provider == .codex ? "Hooks add approval-request status after review in Codex /hooks. Local task detection works independently." : "Hooks add approval-request status after Claude Code reloads them. Local task detection works independently.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if connection.state == .connected { CodexUsageView(connection: connection) }
                if connection.provider == .claude, connection.state == .connected || connection.metricsInstalled {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Session metrics").font(.system(size: 12, weight: .medium))
                            Text("Model, context, token counts and plan limits when available. Keeps your existing status line.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(connection.metricsInstalled ? "Disconnect metrics" : "Connect metrics") { connection.setMetrics(!connection.metricsInstalled) }.buttonStyle(OrbitButtonStyle())
                    }
                }
                if let detail = connection.detail { Text(detail).font(.system(size: 12)).foregroundStyle(connection.state == .failed ? Color.orange : Color.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
                else if connection.state == .disconnected { Text("Continue with the account already signed in, or sign in securely in your browser. No API key needed.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3) }
            }
        }
    }
}

struct CodexUsageView: View {
    @ObservedObject var connection: AgentAccountConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if connection.state == .connected && connection.account?.usesSubscription == true {
                HStack { AgentProviderIcon(provider: connection.provider); Text(connection.provider == .codex ? "Codex plan usage" : "Claude plan usage").font(.system(size: 12, weight: .semibold)); Spacer(); Button { connection.refreshUsage(force: true) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(OrbitIconButtonStyle()).accessibilityLabel("Refresh usage") }
                AgentLimitRows(windows: connection.limits.filter { $0.resetsAt.map { $0 > Date() } ?? true })
                if let message = connection.limitsMessage { Text(message).font(.system(size: 10)).foregroundStyle(.secondary) }
                if let date = connection.limitsUpdatedAt { HStack(spacing: 4) { Text("Checked"); Text(date, style: .relative); Text("ago") }.font(.system(size: 10)).foregroundStyle(.secondary) }
            } else { Text("Connect \(connection.provider.title) to see its plan limits here.").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}
struct AgentLimitRows: View {
    let windows: [AgentLimitWindow]
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(windows) { window in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(window.label); Spacer(); Text("\(Int(window.remainingPercent.rounded()))% remaining").monospacedDigit() }.font(.system(size: 11, weight: .medium))
                    ProgressView(value: window.remainingPercent, total: 100).tint(window.remainingPercent < 15 ? Color.orange : OrbitDesign.accent(.mint))
                    if let reset = window.resetsAt {
                        if reset > Date() { HStack(spacing: 4) { Text("Resets in"); Text(reset, style: .relative) }.font(.system(size: 10)).foregroundStyle(.secondary) }
                        else { Text("Reset time passed · awaiting a new reading").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}
struct AgentMetricsCard: View {
    let metrics: AgentSessionMetrics
    let compact: Bool
    var body: some View {
        OrbitCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack { AgentProviderIcon(provider: AIProvider(activityName: metrics.provider)); Text(metrics.model ?? "\(metrics.provider) session").font(.system(size: 12, weight: .semibold)); Spacer(); Text(metrics.project).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                if let used = metrics.contextUsedPercent { HStack { Text("Context used"); Spacer(); Text("\(Int(used.rounded()))%").monospacedDigit() }.font(.system(size: 11)); ProgressView(value: used, total: 100) }
                HStack(spacing: 14) {
                    if let input = metrics.inputTokens { Text("\(input.formatted()) input") }
                    if let output = metrics.outputTokens { Text("\(output.formatted()) output") }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                AgentLimitRows(windows: metrics.limits)
                if let cost = metrics.estimatedAPIValueUSD {
                    Text("Reported API value: \(cost.formatted(.currency(code: "USD"))) · estimate, not your subscription bill").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) { Text("Session reading"); Text(metrics.updatedAt, style: .relative); Text("ago") }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}
