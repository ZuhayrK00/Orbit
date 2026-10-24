import Foundation

enum MediaArtwork {
    static func load(player: String) async -> Data? {
        do {
            if player == "Spotify" {
                let location = try await ScriptRunner.run("tell application \"Spotify\" to get artwork url of current track")
                guard let url = URL(string: location), url.scheme == "https", let host = url.host,
                      host == "i.scdn.co" || host.hasSuffix(".spotifycdn.com") || host.hasSuffix(".scdn.co") else { return nil }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 8; configuration.httpCookieStorage = nil; configuration.urlCache = nil
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (bytes, response) = try await session.bytes(from: url)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.mimeType?.hasPrefix("image/") == true, response.expectedContentLength < 6_000_000 else { return nil }
                var data = Data()
                for try await byte in bytes {
                    guard !Task.isCancelled, data.count < 6_000_000 else { return nil }; data.append(byte)
                }
                return data
            }
            guard player == "Music" else { return nil }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-cover-\(UUID().uuidString).data")
            defer { try? FileManager.default.removeItem(at: file) }
            let path = file.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            // Write the binary Apple-event result directly, rather than sending a
            // large hex string through osascript's text pipe.
            _ = try await ScriptRunner.run("""
            tell application "Music" to set coverData to raw data of artwork 1 of current track
            set coverFile to open for access POSIX file "\(path)" with write permission
            try
                set eof coverFile to 0
                write coverData to coverFile
                close access coverFile
            on error
                try
                    close access coverFile
                end try
            end try
            """)
            let size = (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard size > 0, size < 6_000_000, !Task.isCancelled else { return nil }
            return try Data(contentsOf: file)
        } catch { return nil }
    }
}
