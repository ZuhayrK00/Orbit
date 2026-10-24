import Foundation

enum ScriptRunner {
    static func run(_ script: String) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); process.arguments = ["-e", script]
            let output = Pipe(), errors = Pipe(); process.standardOutput = output; process.standardError = errors
            try process.run()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline { try await Task.sleep(nanoseconds: 30_000_000) }
            if process.isRunning { process.terminate(); throw NSError(domain: "Orbit.Script", code: 1, userInfo: [NSLocalizedDescriptionKey: "The application did not respond in time."]) }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else { throw NSError(domain: "Orbit.Script", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Automation permission was denied or the application is unavailable."]) }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
        }.value
    }
}
