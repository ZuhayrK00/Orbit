import AppKit
import Combine
import OrbitCore

actor DownloadScanner {
    func scan(_ folder: URL) throws -> [DownloadSample] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileResourceIdentifierKey]
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        return urls.prefix(3000).compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else { return nil }
            let temporary = ["crdownload", "download", "part", "partial"].contains(url.pathExtension.lowercased())
            guard temporary || values.isRegularFile == true else { return nil }
            var size = Int64(values.fileSize ?? 0)
            var identifier = values.fileResourceIdentifier.map { String(describing: $0) }
            if values.isDirectory == true {
                let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .fileResourceIdentifierKey], options: [.skipsHiddenFiles])) ?? []
                size = 0; identifier = nil
                for child in children.prefix(100) where child.lastPathComponent != "Info.plist" {
                    guard let value = try? child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .fileResourceIdentifierKey]), value.isRegularFile == true else { continue }
                    size += Int64(value.fileSize ?? 0)
                    if child.lastPathComponent == url.deletingPathExtension().lastPathComponent { identifier = value.fileResourceIdentifier.map { String(describing: $0) } }
                }
            }
            return DownloadSample(path: url.path, target: temporary ? url.deletingPathExtension().path : url.path, bytes: max(0, size), temporary: temporary, identifier: identifier)
        }
    }
}
@MainActor final class DownloadService: ObservableObject {
    @Published private(set) var activities: [DownloadActivity] = []
    @Published var error: String?
    private let scanner = DownloadScanner()
    private var tracker = DownloadTracker()
    private var folder: URL?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var scanned = Date.distantPast
    // Browser-published Foundation progress supplies real byte totals where available.
    private var subscriptions: [String: Any] = [:]
    private var progress: [String: Progress] = [:]
    func configure(_ options: ProductivityOptions) {
        let next = options.downloadsEnabled == true ? URL(fileURLWithPath: options.downloadFolder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.path) : nil
        guard next != folder else { return }
        generation += 1; task?.cancel(); task = nil; folder = next; tracker = .init(); activities = []; error = nil; scanned = .distantPast
        for value in subscriptions.values { Progress.removeSubscriber(value) }; subscriptions = [:]; progress = [:]
    }
    func tick() {
        guard let folder, task == nil, Date().timeIntervalSince(scanned) >= 1 else { return }
        scanned = Date(); let token = generation
        task = Task { [self] in
            defer { if token == generation { task = nil } }
            do {
                var samples = try await scanner.scan(folder)
                guard token == generation else { return }
                for i in samples.indices where samples[i].temporary {
                    let path = samples[i].path
                    if subscriptions[path] == nil {
                        subscriptions[path] = Progress.addSubscriber(forFileURL: URL(fileURLWithPath: samples[i].target)) { [weak self] p in
                            Task { @MainActor in if self?.generation == token { self?.progress[path] = p } }
                            return { [weak self] in Task { @MainActor in if self?.generation == token { self?.progress.removeValue(forKey: path) } } }
                        }
                    }
                    if let p = progress[path], p.kind == .file, !p.isIndeterminate, p.totalUnitCount > 0 {
                        samples[i].total = p.totalUnitCount
                    }
                }
                tracker.ingest(samples, now: Date()); activities = tracker.activities; error = nil
                let active = Set(activities.filter { $0.state == .downloading }.map(\.id))
                for key in Array(subscriptions.keys) where !active.contains(key) { if let value = subscriptions.removeValue(forKey: key) { Progress.removeSubscriber(value) }; progress.removeValue(forKey: key) }
            } catch { if token == generation { self.error = "Cannot read this download folder. Choose it again in Settings → Productivity." } }
        }
    }
    var live: DownloadActivity? { activities.first { $0.state == .downloading } ?? activities.first { $0.state == .complete && Date().timeIntervalSince($0.updated) < 8 } }
    func clearFinished() { tracker.clearFinished(); activities = tracker.activities }
    func reveal(_ item: DownloadActivity) { if FileManager.default.fileExists(atPath: item.target) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.target)]) } }
    func open(_ item: DownloadActivity) { guard item.state == .complete, FileManager.default.fileExists(atPath: item.target) else { return }; NSWorkspace.shared.open(URL(fileURLWithPath: item.target)) }
}
