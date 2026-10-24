import AppKit
import Combine
import Darwin
import OrbitCore

private struct AwakeLidLease: Codable {
    let updated: Date
    let deadline: Date
    let batteryCutoff: Int
}

/// A root process exists only for the opted-in session. No sudoers rule,
/// login daemon or password is installed or retained by Orbit.
@MainActor final class AwakeLidSession: ObservableObject {
    enum State { case off, authorizing, active, restoring }
    @Published private(set) var state: State = .off
    @Published private(set) var error: String?
    @Published private(set) var needsRecovery = false
    private var leaseURL: URL?
    private var ticket: UUID?
    private var maximumEnd = Date.distantPast
    private var lastHeartbeat = Date.distantPast
    var enabled: Bool { state == .authorizing || state == .active }
    var status: String {
        switch state {
        case .off: return "Administrator approval for each session · up to 12 hours"
        case .authorizing: return "Waiting for macOS approval…"
        case .active: return "Active · normal sleep returns when this session ends"
        case .restoring: return "Restoring normal sleep…"
        }
    }
    func start(until: Date?, batteryCutoff: Int) {
        guard state == .off, !needsRecovery, let executable = Bundle.main.executableURL else { return }
        let id = UUID(), lease = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-lid-\(UUID().uuidString).json")
        ticket = id; leaseURL = lease; maximumEnd = Date().addingTimeInterval(12 * 3600); error = nil
        guard writeLease(until: until, batteryCutoff: batteryCutoff) else { ticket = nil; leaseURL = nil; return }
        state = .authorizing
        let script = Self.authorizationScript(executable: executable.path, ticket: id, parent: getpid(), lease: lease.path)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var details: NSDictionary?
            let source = NSAppleScript(source: script)
            source?.executeAndReturnError(&details)
            let failure = source == nil ? "Couldn’t prepare the macOS approval request." : details?[NSAppleScript.errorMessage] as? String
            Task { @MainActor in
                guard let self, self.ticket == id else { return }
                if let failure, self.state != .restoring { self.error = failure }
                if let leaseURL = self.leaseURL { try? FileManager.default.removeItem(at: leaseURL) }
                self.leaseURL = nil; self.ticket = nil; self.state = .off
            }
        }
    }
    static func authorizationScript(executable: String, ticket: UUID, parent: Int32, lease: String) -> String {
        approvalScript(arguments: [executable, "--awake-lid-guard", ticket.uuidString, String(parent), lease],
            prompt: "Orbit needs permission to keep this Mac awake with its lid closed for this session.")
    }
    private static func approvalScript(arguments: [String], prompt: String) -> String {
        // Paths remain literal through both interpreters, including quotes and $().
        func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = arguments.map(shellQuote).joined(separator: " ")
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges with prompt \"\(prompt)\""
    }
    func tick(active: Bool, until: Date?, batteryCutoff: Int) {
        if state == .off {
            let recovery = AwakeLidGuard.recoveryNeeded()
            if needsRecovery != recovery { needsRecovery = recovery }
        }
        guard enabled else { return }
        guard active, Date() < maximumEnd else { stop(); return }
        if Date().timeIntervalSince(lastHeartbeat) >= 1 {
            guard writeLease(until: until, batteryCutoff: batteryCutoff) else { stop(); return }
        }
        if let ticket,
           (try? String(contentsOfFile: AwakeLidGuard.statusPath(ticket), encoding: .utf8)) == "active",
           state != .active { state = .active }
    }
    func recover() {
        guard state == .off, needsRecovery, let executable = Bundle.main.executableURL else { return }
        state = .restoring; error = nil
        let script = Self.approvalScript(arguments: [executable.path, "--awake-lid-recover"], prompt: "Orbit needs permission to restore normal sleep after an interrupted closed-lid session.")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var details: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&details)
            let failure = details?[NSAppleScript.errorMessage] as? String
            Task { @MainActor in
                self?.error = failure; self?.state = .off; self?.needsRecovery = AwakeLidGuard.recoveryNeeded()
            }
        }
    }
    func stop() {
        guard enabled else { return }
        if let leaseURL { try? FileManager.default.removeItem(at: leaseURL) }
        leaseURL = nil; state = .restoring
    }
    private func writeLease(until: Date?, batteryCutoff: Int) -> Bool {
        guard let leaseURL else { return false }
        do {
            let value = AwakeLidLease(updated: Date(), deadline: min(until ?? maximumEnd, maximumEnd), batteryCutoff: batteryCutoff)
            try JSONEncoder().encode(value).write(to: leaseURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: leaseURL.path)
            lastHeartbeat = Date(); return true
        } catch { self.error = "Couldn’t prepare the closed-lid session."; return false }
    }
}

private var awakeGuardInterrupted: Int32 = 0

enum AwakeLidGuard {
    private static let lockPath = "/var/run/dev.orbit.lid.lock"
    private static let recoveryPath = "/var/db/dev.orbit.lid-recovery"
    static func recoveryNeeded() -> Bool {
        guard FileManager.default.fileExists(atPath: recoveryPath) else { return false }
        let descriptor = open(lockPath, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return true }
        defer { close(descriptor) }
        // An active guard holds the exclusive lock and owns restoration.
        return flock(descriptor, LOCK_SH | LOCK_NB) == 0
    }
    static func recover() -> Int32 {
        guard geteuid() == 0 else { return fail("Restoring normal sleep requires macOS administrator approval.") }
        let descriptor = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, 0o644)
        guard descriptor >= 0 else { return fail("Couldn’t lock the sleep setting.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return fail("A closed-lid session is still running.") }
        guard FileManager.default.fileExists(atPath: recoveryPath) else { return 0 }
        guard setDisabled(false) else { return fail("macOS couldn’t restore normal sleep. Try again.") }
        unlink(recoveryPath); return 0
    }
    static func statusPath(_ id: UUID) -> String { "/var/run/dev.orbit.lid.\(id.uuidString)" }
    static func run(_ arguments: [String]) -> Int32 {
        guard arguments.count == 3, geteuid() == 0, let id = UUID(uuidString: arguments[0]),
              let parent = Int32(arguments[1]), parent > 1 else { return fail("Closed-lid mode requires macOS administrator approval.") }
        let path = arguments[2]
        let limit = Date().addingTimeInterval(12 * 3600)
        guard let initial = readLease(path), AwakeTiming.leaseIsFresh(updated: initial.updated, deadline: initial.deadline, now: Date()),
              kill(parent, 0) == 0 else { return fail("The keep-awake session has already ended.") }
        // A root-owned lock serializes Orbit sessions. Never follow symlinks.
        let lock = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, 0o644)
        guard lock >= 0 else { return fail("Couldn’t lock the sleep setting.") }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { return fail("Another Orbit closed-lid session is still finishing.") }
        guard sleepDisabled() == false else { return fail("Closed-lid sleep is already controlled by another app or system setting.") }
        let status = open(statusPath(id), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard status >= 0 else { return fail("Couldn’t report the closed-lid session status.") }
        defer { close(status); unlink(statusPath(id)) }
        signal(SIGTERM) { _ in awakeGuardInterrupted = 1 }
        signal(SIGINT) { _ in awakeGuardInterrupted = 1 }
        signal(SIGHUP, SIG_IGN)
        // The marker survives a power loss or a force-killed guard. On the next
        // launch Orbit offers an explicit administrator-approved restoration.
        let marker = open(recoveryPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard marker >= 0 else { return fail("Restore the previous closed-lid session before starting another.") }
        _ = id.uuidString.withCString { write(marker, $0, strlen($0)) }; fsync(marker); close(marker)
        // Stay alive until restoration succeeds, even if Orbit exits or stops responding.
        defer { while !setDisabled(false) { Thread.sleep(forTimeInterval: 2) }; unlink(recoveryPath) }
        guard setDisabled(true) else { return fail("macOS couldn’t enable closed-lid mode.") }
        _ = "active".withCString { write(status, $0, 6) }
        while awakeGuardInterrupted == 0, kill(parent, 0) == 0, Date() < limit {
            guard let lease = readLease(path), AwakeTiming.leaseIsFresh(updated: lease.updated, deadline: lease.deadline, now: Date()) else { break }
            if let battery = AwakePower.snapshot(), battery.onBattery, battery.percent <= min(50, max(5, lease.batteryCutoff)) { break }
            Thread.sleep(forTimeInterval: 1)
        }
        return 0
    }
    private static func readLease(_ path: String) -> AwakeLidLease? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid != 0, info.st_size > 0, info.st_size <= 1024,
              let data = try? handle.read(upToCount: 1025), data.count <= 1024 else { return nil }
        return try? JSONDecoder().decode(AwakeLidLease.self, from: data)
    }
    private static func command(_ arguments: [String]) -> (Int32, String) {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch { return (1, "") }
    }
    private static func sleepDisabled() -> Bool? {
        let result = command(["-g"])
        guard result.0 == 0 else { return nil }
        for line in result.1.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.first == "SleepDisabled", fields.count > 1 { return fields[1] == "1" }
        }
        return nil
    }
    private static func setDisabled(_ disabled: Bool) -> Bool { command(["disablesleep", disabled ? "1" : "0"]).0 == 0 }
    private static func fail(_ text: String) -> Int32 { FileHandle.standardError.write(Data((text + "\n").utf8)); return 1 }
}
