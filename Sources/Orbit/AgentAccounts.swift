import AppKit
import SwiftUI
import OrbitCore

enum ProviderRuntime {
    static func executable(_ provider: AIProvider) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let name = provider == .codex ? "codex" : "claude"
        let folders = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", home + "/.npm-global/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var paths = folders.map { $0 + "/" + name }
        if provider == .codex {
            paths += ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex", "/Applications/Codex.app/Contents/Resources/codex"]
        }
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
    static func environment(executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = ([executable.deletingLastPathComponent().path, home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", environment["PATH"] ?? ""]).joined(separator: ":")
        return environment
    }
    static func configurationDirectory(_ provider: AIProvider, account: ProviderAccount? = nil) -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let path = provider == .claude ? account?.configurationDirectory ?? environment["CLAUDE_CONFIG_DIR"] : environment["CODEX_HOME"], path.hasPrefix("/") { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(provider == .codex ? ".codex" : ".claude", isDirectory: true)
    }
}

@MainActor final class AgentAccountConnection: ObservableObject {
    enum State { case disconnected, checking, signingIn, connected, signedOut, missing, failed }
    let provider: AIProvider
    @Published private(set) var state = State.disconnected
    @Published private(set) var account: ProviderAccount?
    @Published private(set) var detail: String?
    @Published private(set) var activityInstalled = false
    @Published private(set) var activityNeedsRepair = false
    @Published private(set) var metricsInstalled = false
    @Published private(set) var localMonitoringEnabled = false
    @Published var lastLocalActivity: Date?
    @Published private(set) var limits: [AgentLimitWindow] = []
    @Published private(set) var limitsUpdatedAt: Date?
    @Published private(set) var limitsMessage: String?
    private var claudeUsage: ClaudeUsageReader?
    private var nextClaudeUsage = Date.distantPast
    private var usageVersion: (String, Date)?
    private var usageTask: Task<Void, Never>?
    private var rpc: CodexAccountRPC?
    private var command: ProviderCommand?
    private var operation: Task<Void, Never>?
    private var polling: Timer?
    private var loginTimeout: Task<Void, Never>?
    private var loginID: String?
    private var generation = UUID()
    private var refreshing = false
    private var localMonitoringKey: String { "Orbit.account.\(provider.rawValue).localActivity" }
    private var enabledKey: String { "Orbit.account.\(provider.rawValue).enabled" }
    var busy: Bool { state == .checking || state == .signingIn }
    var installationURL: URL { URL(string: provider == .codex ? "https://learn.chatgpt.com/docs/codex/cli" : "https://code.claude.com/docs/en/setup")! }
    init(_ provider: AIProvider) {
        self.provider = provider
        refreshActivity()
        localMonitoringEnabled = (UserDefaults.standard.object(forKey: localMonitoringKey) as? Bool) ?? activityInstalled
        if UserDefaults.standard.bool(forKey: enabledKey) { refresh() }
        polling = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, UserDefaults.standard.bool(forKey: self.enabledKey), !self.busy else { return }; self.refresh(silent: true)
            }
        }
    }
    func connect() {
        guard !busy else { return }
        detail = nil; state = .checking
        let generation = self.generation
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let found = try await self.readAccount()
                guard self.generation == generation else { return }
                if let found { self.didConnect(found) }
                else { try await self.signIn() }
            } catch { guard self.generation == generation else { return }; self.failed(error) }
        }
    }
    func refresh(silent: Bool = false) {
        guard !busy, !refreshing else { return }
        refreshing = true
        if !silent { state = .checking }
        let generation = self.generation
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == generation { self.refreshing = false } }
            do {
                let found = try await self.readAccount()
                guard self.generation == generation else { return }
                if let found { self.didConnect(found) }
                else { self.account = nil; self.limits = []; self.limitsUpdatedAt = nil; self.state = .signedOut; self.detail = "Sign in to connect your account." }
            } catch { guard self.generation == generation else { return }; self.failed(error) }
        }
    }
    private func readAccount() async throws -> ProviderAccount? {
        guard let executable = ProviderRuntime.executable(provider) else {
            state = .missing; throw ProviderProcessError("Install \(provider.title) on this Mac, then try again.")
        }
        let environment = ProviderRuntime.environment(executable: executable)
        if provider == .codex {
            if rpc?.running != true {
                rpc?.stop()
                let rpc = CodexAccountRPC(); self.rpc = rpc
                rpc.onNotification = { [weak self] method, params in self?.notification(method, params) }
                try await rpc.start(executable: executable, environment: environment)
            }
            let response = try await rpc!.request("account/read", parameters: ["refreshToken": false])
            let account = ProviderAccount.codex(response)
            if response["account"] is [String: Any], account == nil { throw ProviderProcessError("This Codex sign-in method isn’t supported by Orbit yet. Your existing sign-in was left unchanged.") }
            return account
        }
        let command = ProviderCommand(); self.command = command
        let (data, code) = try await command.run(executable: executable, arguments: ["auth", "status", "--json"], environment: environment)
        guard code == 0 || code == 1, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["loggedIn"] is Bool else {
            throw ProviderProcessError("Claude Code couldn’t report its account. Update Claude Code and try again.")
        }
        let account = ProviderAccount.claude(json)
        if json["loggedIn"] as? Bool == true, account == nil { throw ProviderProcessError("This Claude Code sign-in method isn’t supported by Orbit yet. Your existing sign-in was left unchanged.") }
        return account
    }
    private func signIn() async throws {
        let generation = self.generation
        state = .signingIn; detail = "Finish signing in in your browser. Orbit will confirm when you’re connected."
        if provider == .codex {
            guard let rpc else { throw ProviderProcessError("Reconnect Codex to start sign-in.") }
            let result = try await rpc.request("account/login/start", parameters: ["type": "chatgpt"])
            guard self.generation == generation else { throw CancellationError() }
            guard let id = result["loginId"] as? String, let text = result["authUrl"] as? String,
                  let url = ProviderLoginURL.allowed(text) else { throw ProviderProcessError("Codex returned an unsupported sign-in link. Update Codex and try again.") }
            loginID = id
            guard NSWorkspace.shared.open(url) else { throw ProviderProcessError("Your browser couldn’t open the Codex sign-in page. Try again.") }
            loginTimeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 300_000_000_000) } catch { return }
                self?.cancelSignIn(); self?.detail = "Sign-in timed out. You can try again."
            }
        } else {
            guard let executable = ProviderRuntime.executable(.claude) else { throw ProviderProcessError("Install Claude Code first.") }
            let command = ProviderCommand(); self.command = command
            let (_, code) = try await command.run(executable: executable, arguments: ["auth", "login", "--claudeai"], environment: ProviderRuntime.environment(executable: executable), seconds: 300, retainOutput: false)
            guard code == 0, let found = try await readAccount() else { throw ProviderProcessError("Claude Code sign-in wasn’t completed. Try again, or run claude auth login in Terminal.") }
            guard self.generation == generation else { throw CancellationError() }
            didConnect(found)
        }
    }
    private func notification(_ method: String, _ parameters: [String: Any]) {
        if method == "account/login/completed", let id = loginID, parameters["loginId"] as? String == id {
            loginID = nil; loginTimeout?.cancel(); loginTimeout = nil
            state = .signedOut
            if parameters["success"] as? Bool == true { refresh() }
            else { detail = "Sign-in wasn’t completed. You can try again." }
        } else if method == "account/updated", state == .connected { refresh(silent: true) }
        else if method == "account/rateLimits/updated", state == .connected {
            let incoming = AgentUsage.codexLimits(parameters)
            if parameters["rateLimitsByLimitId"] is [String: Any] { limits = incoming }
            else if let bucket = parameters["rateLimits"] as? [String: Any] {
                let prefix = String((bucket["limitId"] as? String ?? "codex").prefix(200)) + "."
                limits = limits.filter { !$0.id.hasPrefix(prefix) } + incoming
            } else { return }
            limitsUpdatedAt = Date(); limitsMessage = limits.isEmpty ? "No usage windows were reported by Codex." : nil
        }
    }
    private func didConnect(_ found: ProviderAccount) {
        account = found; state = .connected; detail = nil
        UserDefaults.standard.set(true, forKey: enabledKey); refreshActivity(); refreshUsage()
    }
    func refreshUsage(force: Bool = false) {
        if provider == .claude { if force { nextClaudeUsage = .distantPast }; refreshClaudeUsage(); return }
        guard provider == .codex, state == .connected, account?.usesSubscription == true, let rpc else { limits = []; return }
        usageTask?.cancel()
        let identity = generation
        usageTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await rpc.request("account/rateLimits/read", seconds: 12)
                guard !Task.isCancelled, identity == self.generation else { return }
                self.limits = AgentUsage.codexLimits(result); self.limitsUpdatedAt = Date()
                self.limitsMessage = self.limits.isEmpty ? "No usage windows were reported by Codex." : nil
            } catch {
                guard !Task.isCancelled, identity == self.generation else { return }
                self.limitsMessage = "Usage is temporarily unavailable. Refresh to try again."
            }
        }
    }
    private func refreshClaudeUsage() {
        guard state == .connected, account?.usesSubscription == true, usageTask == nil, Date() >= nextClaudeUsage,
              let executable = ProviderRuntime.executable(.claude) else { return }
        let identity = generation, accountIdentity = account
        usageTask = Task { [weak self] in
            guard let self else { return }
            defer { self.usageTask = nil; self.claudeUsage = nil }
            do {
                let environment = ProviderRuntime.environment(executable: executable)
                if usageVersion == nil || Date().timeIntervalSince(usageVersion!.1) > 3600 {
                    let version = ProviderCommand()
                    let (data, code) = try await version.run(executable: executable, arguments: ["--version"], environment: environment, seconds: 8)
                    guard code == 0, let text = String(data: data, encoding: .utf8) else { throw ProviderProcessError("Could not check Claude Code’s version") }
                    usageVersion = (text, Date())
                }
                guard ClaudeUsageProtocol.supported(version: usageVersion!.0) else { throw ProviderProcessError("Account usage needs Claude Code 2.1.286 or newer. Local samples remain available.") }
                try Task.checkCancellation()
                let reader = ClaudeUsageReader(); claudeUsage = reader
                let windows = try await reader.read(executable: executable, environment: environment)
                guard !Task.isCancelled, identity == generation, accountIdentity == account else { return }
                limits = windows; limitsUpdatedAt = Date(); limitsMessage = nil; nextClaudeUsage = Date().addingTimeInterval(60)
            } catch {
                guard !Task.isCancelled, identity == generation else { return }
                limitsMessage = error.localizedDescription; nextClaudeUsage = Date().addingTimeInterval(300)
            }
        }
    }
    private func failed(_ error: Error) {
        loginTimeout?.cancel(); loginTimeout = nil; loginID = nil
        account = nil; limits = []; limitsUpdatedAt = nil; claudeUsage?.cancel(); usageTask?.cancel()
        if state != .missing { state = .failed }
        detail = error is CancellationError ? "Sign-in cancelled." : error.localizedDescription
        rpc?.stop(); rpc = nil; command?.cancel(); command = nil
    }
    func cancelSignIn() {
        generation = UUID(); claudeUsage?.cancel(); nextClaudeUsage = .distantPast; usageTask?.cancel(); limits = []; limitsUpdatedAt = nil; operation?.cancel(); operation = nil; loginTimeout?.cancel(); loginTimeout = nil
        let id = loginID; loginID = nil
        if let rpc, let id { Task { _ = try? await rpc.request("account/login/cancel", parameters: ["loginId": id], seconds: 3); rpc.stop() } }
        else { rpc?.stop() }
        rpc = nil; command?.cancel(); command = nil; refreshing = false
        state = .disconnected; detail = nil
    }
    func disconnect() {
        cancelSignIn(); account = nil; UserDefaults.standard.set(false, forKey: enabledKey)
        detail = "Unlinked from Orbit. Your provider stays signed in."
    }
    func refreshActivity() {
        let directory = ProviderRuntime.configurationDirectory(provider, account: account)
        let count = AgentInstaller.installedHookCount(provider, directory: directory)
        activityInstalled = count > 0
        activityNeedsRepair = activityInstalled && (count != AgentHooks.events(provider).count || !AgentInstaller.bridgeIsCurrent)
        metricsInstalled = provider == .claude && AgentInstaller.hasClaudeMetrics(directory: directory)
    }
    func setLocalMonitoring(_ enabled: Bool) {
        localMonitoringEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: localMonitoringKey)
        if !enabled { lastLocalActivity = nil }
    }
    func setActivity(_ enabled: Bool) {
        do {
            let directory = ProviderRuntime.configurationDirectory(provider, account: account)
            try AgentInstaller.setGlobalHooks(provider, directory: directory, enabled: enabled)
            setLocalMonitoring(enabled)
            refreshActivity()
            detail = enabled ? (provider == .codex ? "Local session monitoring is on. Optional hooks also report approval requests; restart Codex and review Orbit in /hooks to enable those callbacks." : "Local session monitoring is on. Restart Claude Code sessions to load the additional approval and lifecycle hooks.") : "Orbit’s global activity hooks have been removed."
        } catch { detail = error.localizedDescription }
    }
    func setMetrics(_ enabled: Bool) {
        do {
            try AgentInstaller.setClaudeMetrics(directory: ProviderRuntime.configurationDirectory(.claude, account: account), enabled: enabled)
            refreshActivity()
            detail = enabled ? "Metrics connected. Your existing status-line output is preserved. Model, context and limits appear when Claude sends its next status update." : "Metrics disconnected and your original status line restored."
        } catch { detail = error.localizedDescription }
    }
    func shutdown() { polling?.invalidate(); cancelSignIn() }
}
