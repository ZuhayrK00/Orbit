import AppKit
import Combine

@MainActor final class MediaService: ObservableObject {
    @Published var title = "Nothing playing"
    @Published var artist = "Connect Music or Spotify"
    @Published var isPlaying = false
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var provider: String?
    @Published var connectionError: String?
    @Published var appVolume = 100.0
    @Published private(set) var artwork: NSImage?
    private var artworkKey = ""
    private var artworkTask: Task<Void, Never>?
    private var loading = false
    func refresh() {
        guard !loading else { return }
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let available = [("Spotify", "com.spotify.client"), ("Music", "com.apple.Music")].filter { running.contains($0.1) }
        guard !available.isEmpty else { clearTrack(); artist = "Open Music or Spotify"; return }
        loading = true
        Task {
            defer { loading = false }
            var fallback: (String, [String])?
            for (name, _) in available {
                let durationField = name == "Spotify" ? "duration of current track / 1000" : "duration of current track"
                let script = "tell application \"\(name)\"\nif player state is stopped then return \"stopped\"\nreturn name of current track & ASCII character 31 & artist of current track & ASCII character 31 & (player state as text) & ASCII character 31 & (player position as text) & ASCII character 31 & ((\(durationField)) as text) & ASCII character 31 & (sound volume as text)\nend tell"
                do {
                    let result = try await ScriptRunner.run(script)
                    if result == "stopped" { continue }
                    let fields = result.components(separatedBy: "\u{1f}")
                    guard fields.count == 6 else { continue }
                    if fields[2] == "playing" { apply(name, fields); return }
                    fallback = (name, fields)
                } catch { connectionError = "Allow Orbit to control \(name) in System Settings → Privacy & Security → Automation." }
            }
            if let fallback { apply(fallback.0, fallback.1) }
            else { clearTrack(); artist = connectionError == nil ? "Start a track in Music or Spotify" : "Automation permission needed" }
        }
    }
    private func apply(_ name: String, _ fields: [String]) {
        provider = name; title = fields[0]; artist = fields[1]; isPlaying = fields[2] == "playing"
        position = Double(fields[3]) ?? 0; duration = Double(fields[4]) ?? 0; appVolume = Double(fields[5]) ?? 100; connectionError = nil
        let key = "\(name)-\(title)-\(artist)-\(duration)"
        guard key != artworkKey else { return }
        artworkKey = key; artwork = nil; artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            let data = await MediaArtwork.load(player: name)
            guard !Task.isCancelled, let self, self.artworkKey == key else { return }
            self.artwork = data.flatMap(NSImage.init(data:))
        }
    }
    private func clearTrack() {
        title = "Nothing playing"; provider = nil; isPlaying = false; position = 0; duration = 0
        artworkTask?.cancel(); artwork = nil; artworkKey = ""
    }
    func command(_ command: String) {
        guard let provider, ["playpause", "next track", "previous track"].contains(command) else { return }
        Task { do { _ = try await ScriptRunner.run("tell application \"\(provider)\" to \(command)"); refresh() } catch { connectionError = error.localizedDescription } }
    }
    func setAppVolume(_ value: Double) {
        guard let provider else { return }; appVolume = value
        Task { do { _ = try await ScriptRunner.run("tell application \"\(provider)\" to set sound volume to \(Int(value))") } catch { connectionError = error.localizedDescription } }
    }
}
