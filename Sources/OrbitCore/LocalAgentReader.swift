import Foundation
import Darwin

public struct LocalAgentRoot: Equatable {
    public let provider: AIProvider
    public let directory: URL
    public init(provider: AIProvider, directory: URL) { self.provider = provider; self.directory = directory }
}

/// Incremental, bounded reads on an actor, never on the UI thread. No transcripts
/// or snapshots are written. A changed/truncated file gets a fresh parser.
public actor LocalAgentReader {
    private var roots: [LocalAgentRoot] = []
    private var files: [URL: Cursor] = [:]
    private var lastDiscovery = Date.distantPast
    private let maximumLine = 2_097_152
    private let initialTail = 8_388_608
    public init() {}

    public func scan(roots: [LocalAgentRoot], now: Date = Date()) -> [AgentStatus] {
        if self.roots != roots { self.roots = roots; files = [:]; lastDiscovery = .distantPast }
        if now.timeIntervalSince(lastDiscovery) >= 5 {
            lastDiscovery = now
            var candidates: [(URL, AIProvider, Date)] = []
            let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey]
            for root in roots {
                guard let iterator = FileManager.default.enumerator(at: root.directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
                var visited = 0
                for case let url as URL in iterator {
                    visited += 1; if visited > 20_000 { break }
                    guard let info = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                    if info.isSymbolicLink == true { iterator.skipDescendants(); continue }
                    if url.pathComponents.count - root.directory.pathComponents.count > 6 { iterator.skipDescendants(); continue }
                    guard info.isRegularFile == true, url.pathExtension == "jsonl", let date = info.contentModificationDate,
                          date >= now.addingTimeInterval(-172_800) else { continue }
                    candidates.append((url, root.provider, date))
                }
            }
            candidates.sort { $0.2 > $1.2 }
            let selected = Array(candidates.prefix(64))
            let retained = Set(selected.map { $0.0 })
            files = files.filter { retained.contains($0.key) }
            for (url, provider, date) in selected {
                if files[url] == nil { files[url] = Cursor(provider: provider, modified: date) }
                else { files[url]?.modified = date }
            }
        }
        var budget = 8_388_608
        // Each pass advances every file before spending the rest of its budget.
        // A large session cannot block a small second session from appearing.
        let ordered = files.keys.sorted { (files[$0]?.modified ?? .distantPast) > (files[$1]?.modified ?? .distantPast) }
        for url in ordered {
            guard budget > 0, var cursor = files[url] else { continue }
            read(url, cursor: &cursor, budget: &budget)
            files[url] = cursor
        }
        return files.values.filter(\.caughtUp).compactMap(\.session.status).filter {
            now.timeIntervalSince($0.updatedAt) < 86_400
        }
    }
    private struct Cursor {
        let provider: AIProvider
        var session: LocalAgentSession
        var modified: Date
        var identity: UInt64 = 0
        var offset: UInt64 = 0
        var pending = Data()
        var droppingLine = false
        var caughtUp = false
        init(provider: AIProvider, modified: Date) { self.provider = provider; self.modified = modified; session = LocalAgentSession(provider: provider) }
    }
    private func read(_ url: URL, cursor: inout Cursor, budget: inout Int) {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { cursor.caughtUp = false; return }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { cursor.caughtUp = false; return }
        let length = UInt64(max(0, attributes.st_size)), identity = UInt64(attributes.st_ino)
        do {
            if cursor.identity != identity || cursor.offset > length {
                cursor = Cursor(provider: cursor.provider, modified: cursor.modified)
                cursor.identity = identity
                if cursor.provider == .codex {
                    var head = try handle.read(upToCount: 65_536) ?? Data()
                    while head.firstIndex(of: 10) == nil && head.count <= maximumLine {
                        let next = try handle.read(upToCount: 65_536) ?? Data()
                        if next.isEmpty { break }; head.append(next)
                    }
                    if let end = head.firstIndex(of: 10), end <= maximumLine { cursor.session.consume(Data(head[..<end])) }
                }
                cursor.offset = length > initialTail ? length - UInt64(initialTail) : 0
                cursor.droppingLine = cursor.offset > 0
            }
            try handle.seek(toOffset: cursor.offset)
            let allowance = min(budget, cursor.caughtUp ? 1_048_576 : 4_194_304)
            let bytes = try handle.read(upToCount: allowance) ?? Data()
            budget -= bytes.count; cursor.offset += UInt64(bytes.count)
            feed(bytes, cursor: &cursor)
            cursor.caughtUp = cursor.offset >= length
        } catch { cursor.caughtUp = false }
    }
    private func feed(_ data: Data, cursor: inout Cursor) {
        var start = data.startIndex
        while start < data.endIndex {
            let end = data[start...].firstIndex(of: 10) ?? data.endIndex
            if !cursor.droppingLine {
                if cursor.pending.count + end - start > maximumLine { cursor.pending.removeAll(keepingCapacity: false); cursor.droppingLine = true }
                else { cursor.pending.append(contentsOf: data[start..<end]) }
            }
            if end < data.endIndex {
                if !cursor.droppingLine { cursor.session.consume(cursor.pending) }
                cursor.pending.removeAll(keepingCapacity: false); cursor.droppingLine = false
                start = end + 1
            } else { break }
        }
    }
}
