import AppKit
import Combine
import OrbitCore

@MainActor final class Scratchpad: ObservableObject {
    @Published var text = "" { didSet { if ready, text != oldValue { if let i = notes.firstIndex(where: { $0.id == selectedID }) { notes[i].text = text }; scheduleSave() } } }
    @Published var notes: [NoteDocument] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var status = "Saved on this Mac"
    @Published private(set) var loadFailed = false
    private let url: URL
    private var ready = false
    private var saveTask: Task<Void, Never>?
    init(url: URL = OrbitPaths.support.appendingPathComponent("scratchpad.txt")) {
        self.url = url.deletingLastPathComponent().appendingPathComponent("notes.json")
        do {
            if FileManager.default.fileExists(atPath: self.url.path) {
                let data = try Data(contentsOf: self.url); guard data.count <= 12_000_000 else { throw TextActionError("Notes are too large to load") }
                notes = try JSONDecoder().decode([NoteDocument].self, from: data)
            } else { notes = [NoteDocument(title: "Scratchpad", text: try ScratchpadDocument.load(from: url))] }
            if notes.isEmpty { notes = [.init()] }; selectedID = notes.first?.id; text = notes.first?.text ?? ""; ready = true
        } catch { status = error.localizedDescription; loadFailed = true }
    }
    func select(_ id: UUID) { guard let note = notes.first(where: { $0.id == id }) else { return }; flush(); ready = false; selectedID = id; text = note.text; ready = true }
    func add() { guard ready, notes.count < 30 else { return }; let note = NoteDocument(); notes.append(note); select(note.id); flush() }
    func rename(_ title: String) { guard let i = notes.firstIndex(where: { $0.id == selectedID }) else { return }; notes[i].title = String(title.prefix(80)); scheduleSave() }
    func deleteSelected() { guard let id = selectedID, notes.count > 1 else { return }; notes.removeAll { $0.id == id }; select(notes[0].id); flush() }
    func toggleChecklist(_ line: Int) { guard let i = notes.firstIndex(where: { $0.id == selectedID }) else { return }; var note = notes[i]; note.toggleChecklist(line: line); text = note.text }
    private func scheduleSave() { saveTask?.cancel(); status = "Saving…"; saveTask = Task { do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }; flush() } }
    func flush() {
        saveTask?.cancel(); saveTask = nil; guard ready else { return }
        do {
            guard notes.allSatisfy({ $0.text.utf8.count <= ScratchpadDocument.maximumBytes }) else { throw TextActionError("Keep each note under 512 KB") }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(notes).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path); status = "Saved on this Mac"
        } catch { status = error.localizedDescription }
    }
    func append(_ value: String) { guard ready else { return }; let next = text.isEmpty ? value : text + "\n\n" + value; guard next.utf8.count <= ScratchpadDocument.maximumBytes else { status = "This note is full"; return }; text = next }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Orbit note.md"; panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try Data(text.utf8).write(to: destination, options: .atomic) } catch { status = error.localizedDescription }
    }
}
