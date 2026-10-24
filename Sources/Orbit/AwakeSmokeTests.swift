import AppKit
import IOKit.pwr_mgt
import OrbitCore

enum AwakeSmokeTests {
    @MainActor static func run() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw NSError(domain: "Orbit.AwakeCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func ownAssertions() -> Set<String> {
            var result: Unmanaged<CFDictionary>?
            guard IOPMCopyAssertionsByProcess(&result) == kIOReturnSuccess,
                  let all = result?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
            return Set((all[NSNumber(value: getpid())] ?? []).compactMap { $0["AssertType"] as? String })
        }
        let session = AwakeSession(); defer { session.shutdown() }
        var options = AwakeOptions()
        session.configure(options); session.start(minutes: 1)
        try check(session.active && session.until != nil, "Timed session did not start")
        try check(ownAssertions().contains(kIOPMAssertionTypePreventUserIdleSystemSleep), "System assertion missing")
        try check(!ownAssertions().contains(kIOPMAssertionTypePreventUserIdleDisplaySleep), "Display should be allowed to sleep")
        options.allowDisplaySleep = false; session.configure(options)
        try check(ownAssertions().contains(kIOPMAssertionTypePreventUserIdleDisplaySleep), "Display assertion missing")
        options.allowDisplaySleep = true; session.configure(options)
        try check(!ownAssertions().contains(kIOPMAssertionTypePreventUserIdleDisplaySleep), "Display assertion was not released")
        session.tick(now: Date().addingTimeInterval(65), permitted: false)
        try check(!session.active && ownAssertions().isEmpty, "Timed session did not release its assertions")
        session.start(minutes: nil)
        try check(session.active && session.until == nil, "Indefinite session did not start")
        session.stop(); try check(ownAssertions().isEmpty, "Stop left an assertion behind")
        options.startOnLaunch = true; session.configure(options, launching: true)
        try check(session.active, "Launch option did not start a session")
        session.stop()
        var compilationError: NSDictionary?
        let script = AwakeLidSession.authorizationScript(executable: "/tmp/Orbit's \"test\" $(literal)/Orbit", ticket: UUID(), parent: getpid(), lease: "/tmp/literal\\lease.json")
        let source = NSAppleScript(source: script)
        try check(source?.compileAndReturnError(&compilationError) == true, "Authorization script does not compile: \(String(describing: compilationError))")
        print("Keep Awake checks passed: real system/display assertions, live setting changes, expiry, indefinite/launch sessions and cleanup. Authorization script compiled only; no administrator prompt, lid override or pointer movement was triggered.")
    }
}
