import Foundation

public struct ProviderProcessError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Bounded stdout only, no stderr logging. The provider owns all credential storage.
@MainActor public final class LocalProviderProcess {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var generation = UUID()
    public var onData: ((Data) -> Void)?
    public var onExit: ((Int32) -> Void)?
    public var running: Bool { process?.isRunning == true }
    public init() {}
    public func start(executable: URL, arguments: [String], environment: [String: String]) throws {
        guard process == nil else { throw ProviderProcessError("A provider connection is already running.") }
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        let generation = UUID(); self.generation = generation
        child.executableURL = executable; child.arguments = arguments; child.environment = environment
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = FileHandle.nullDevice
        try child.run()
        process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        let reader = stdout.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                DispatchQueue.main.sync { [weak self] in
                    guard let self, self.generation == generation else { return }; self.onData?(data)
                }
            }
            child.waitUntilExit()
            let code = child.terminationStatus
            DispatchQueue.main.sync { [weak self] in
                guard let self, self.generation == generation else { return }
                self.process = nil; self.input = nil; self.output = nil; self.onExit?(code)
            }
        }
    }
    public func write(_ data: Data) throws {
        guard running, let input else { throw ProviderProcessError("The provider connection closed. Try reconnecting.") }
        try input.write(contentsOf: data)
    }
    public func stop() {
        generation = UUID()
        try? input?.close(); input = nil
        if let child = process, child.isRunning {
            child.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        process = nil; output = nil; onData = nil; onExit = nil
    }
}

@MainActor public final class ProviderCommand {
    private let process = LocalProviderProcess()
    private var continuation: CheckedContinuation<(Data, Int32), Error>?
    private var timeout: Task<Void, Never>?
    public init() {}
    public func run(executable: URL, arguments: [String], environment: [String: String], seconds: Double = 20, retainOutput: Bool = true) async throws -> (Data, Int32) {
        guard continuation == nil else { throw ProviderProcessError("A provider check is already running.") }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            var buffer = Data()
            process.onData = { [weak self] data in
                guard retainOutput else { return }
                guard buffer.count + data.count <= 1_048_576 else { self?.finish(.failure(ProviderProcessError("Provider response was too large."))); return }
                buffer.append(data)
            }
            process.onExit = { [weak self] code in self?.finish(.success((buffer, code))) }
            do { try process.start(executable: executable, arguments: arguments, environment: environment) }
            catch { finish(.failure(ProviderProcessError("Couldn’t open the provider tool. Check its installation."))); return }
            timeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
                self?.finish(.failure(ProviderProcessError("The provider didn’t respond in time. Try again.")))
            }
        }
    }
    public func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<(Data, Int32), Error>) {
        guard let continuation else { return }; self.continuation = nil
        timeout?.cancel(); timeout = nil; process.stop(); continuation.resume(with: result)
    }
}

@MainActor public final class CodexAccountRPC {
    private let process = LocalProviderProcess()
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    public var onNotification: ((String, [String: Any]) -> Void)?
    public var running: Bool { process.running }
    public init() {}
    public func start(executable: URL, environment: [String: String]) async throws {
        process.onData = { [weak self] in self?.receive($0) }
        process.onExit = { [weak self] _ in self?.stop() }
        try process.start(executable: executable, arguments: ["app-server", "--listen", "stdio://", "-c", "analytics.enabled=false"], environment: environment)
        _ = try await request("initialize", parameters: ["clientInfo": ["name": "orbit_local", "title": "Orbit", "version": "0.1.0"]])
        try send(["method": "initialized"])
    }
    public func request(_ method: String, parameters: [String: Any] = [:], seconds: Double = 20) async throws -> [String: Any] {
        nextID += 1; let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(["id": id, "method": method, "params": parameters]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
            timeouts[id] = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
                self?.timeouts.removeValue(forKey: id)
                self?.pending.removeValue(forKey: id)?.resume(throwing: ProviderProcessError("Codex didn’t respond in time. Try reconnecting."))
            }
        }
    }
    private func send(_ value: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: value); data.append(10); try process.write(data)
    }
    private func receive(_ data: Data) {
        guard buffer.count + data.count <= 1_048_576 else { stop(); return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = json["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                timeouts.removeValue(forKey: id)?.cancel()
                if json["error"] != nil { continuation.resume(throwing: ProviderProcessError("Codex couldn’t complete that account request. Check your sign-in or update Codex.")) }
                else if let result = json["result"] as? [String: Any] { continuation.resume(returning: result) }
                else { continuation.resume(throwing: ProviderProcessError("Codex returned an unsupported account response.")) }
            } else if let method = json["method"] as? String, json["id"] == nil {
                onNotification?(method, json["params"] as? [String: Any] ?? [:])
            }
        }
    }
    public func stop() {
        process.stop(); buffer = Data()
        let waiting = pending; pending = [:]
        timeouts.values.forEach { $0.cancel() }; timeouts = [:]
        waiting.values.forEach { $0.resume(throwing: ProviderProcessError("Codex connection closed. Reconnect to check your account.")) }
    }
}
