import AppKit
import Combine
import IOKit.pwr_mgt
import OrbitCore

@MainActor final class AgentAwakeSession: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var detail = "Keep this Mac awake while the current agents work."
    private var lease = AgentAwakeLease()
    private var assertion: IOPMAssertionID?
    private var started: Date?
    func start(_ agents: [AgentStatus]) {
        let running = agents.filter { [.running, .waiting].contains($0.displayedPhase()) }
        guard !running.isEmpty else { detail = "Start an agent task first"; return }
        var id: IOPMAssertionID = 0
        guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Orbit · waiting for agent completion" as CFString, &id) == kIOReturnSuccess else { detail = "macOS could not start this awake session"; return }
        stop(); assertion = id; started = Date(); lease.start(ids: running.map(\.id)); active = true
        detail = "Waiting for explicit completion · \(lease.pending.count) agents"
    }
    func update(_ agents: [AgentStatus], batteryCutoff: Int) {
        guard active, let started else { return }
        if let battery = AwakePower.snapshot(), battery.onBattery, battery.percent <= batteryCutoff { stop(); detail = "Stopped at the battery limit"; return }
        if Date().timeIntervalSince(started) > 43_200 { stop(); detail = "Stopped after the 12-hour safety limit"; return }
        let completed = Set(agents.filter { [.completed, .failed].contains($0.phase) && $0.updatedAt >= started }.map(\.id))
        let running = Set(agents.filter { [.running, .waiting].contains($0.phase) && $0.updatedAt >= started }.map(\.id))
        lease.observe(completed: completed, running: running)
        if lease.finished { stop(); detail = "All tracked agents finished" }
        else { detail = "Waiting for explicit completion · \(lease.pending.count) agents" }
    }
    func stop() { if let assertion { IOPMAssertionRelease(assertion) }; assertion = nil; active = false; started = nil }
}
