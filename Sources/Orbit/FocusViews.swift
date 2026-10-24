import SwiftUI
import OrbitCore

struct FocusToolsView: View {
    @ObservedObject var store: OrbitStore
    var compact: Bool
    var body: some View {
        VStack(spacing: 12) {
            OrbitSegmentedPicker(selection: $store.timerMode, options: [("Timer", 0), ("Pomodoro", 1), ("Stopwatch", 2)])
            if store.timerMode == 0 { TimerView(store: store, compact: compact) }
            else if store.timerMode == 1 {
                VStack(spacing: 12) {
                    Text(store.focusCycle.running ? store.focusCycle.title : "A little room to focus").font(.system(size: 13, weight: .medium))
                    Text(OrbitTimer.label(store.focusCycle.running ? store.timerState.remaining(at: store.now) : Double(store.configuration.productivity.focusMinutes ?? 25) * 60)).font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit()
                    Text("\(store.configuration.productivity.focusMinutes ?? 25) min focus · \(store.configuration.productivity.breakMinutes ?? 5) min break · \(store.configuration.productivity.focusRounds ?? 4) rounds").font(.system(size: 10)).foregroundStyle(.secondary)
                    HStack {
                        if store.focusCycle.running {
                            Button(store.timerState.end == nil ? "Resume" : "Pause") { store.toggleTimer() }.buttonStyle(OrbitButtonStyle(prominent: true))
                            Button("Skip phase") { store.skipFocus() }.buttonStyle(OrbitButtonStyle())
                            Button("End") { store.cancelTimer() }.buttonStyle(OrbitButtonStyle())
                        } else { Button(store.timerState.isActive ? "Finish the current timer first" : "Start focus cycle") { store.startFocus() }.buttonStyle(OrbitButtonStyle(prominent: true)).disabled(store.timerState.isActive) }
                    }
                    Text("Focus and breaks advance automatically while Orbit is running.").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.vertical, 15)
            } else {
                VStack(spacing: 12) {
                    Text(OrbitTimer.label(floor(store.stopwatch.elapsed(at: store.now)))).font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit()
                    HStack { Button(store.stopwatch.started == nil ? "Start" : "Pause") { store.changeStopwatch(0) }.buttonStyle(OrbitButtonStyle(prominent: true)); Button("Lap") { store.changeStopwatch(1) }.buttonStyle(OrbitButtonStyle()).disabled(store.stopwatch.started == nil); Button("Reset") { store.changeStopwatch(2) }.buttonStyle(OrbitButtonStyle()).disabled(store.stopwatch.started != nil) }
                    ForEach(Array(store.stopwatch.laps.prefix(4).enumerated()), id: \.offset) { index, value in HStack { Text("Lap \(store.stopwatch.laps.count - index)"); Spacer(); Text(OrbitTimer.label(floor(value))).monospacedDigit() }.font(.system(size: 11)).foregroundStyle(.secondary) }
                }.padding(.vertical, 15)
            }
        }
    }
}

struct NotesView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var note: Scratchpad
    @State private var preview = false
    @State private var deletePrompt = false
    @State private var page = 0
    private var title: Binding<String> { Binding(get: { note.notes.first { $0.id == note.selectedID }?.title ?? "Note" }, set: { note.rename($0) }) }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Menu { ForEach(note.notes) { item in Button(item.title.isEmpty ? "Untitled" : item.title) { note.select(item.id); page = 0 } } } label: { Label("Notes · \(note.notes.count)", systemImage: "note.text") }
                Spacer(); Button { note.add(); page = 0 } label: { Image(systemName: "plus") }.disabled(note.notes.count >= 30 || note.loadFailed)
                Button(preview ? "Edit" : "Preview") { preview.toggle() }
                Menu { Button("Copy") { store.copy(note.text) }; Button("Export…") { note.export() }; Button("Delete note…", role: .destructive) { deletePrompt = true }.disabled(note.notes.count < 2) } label: { Image(systemName: "ellipsis") }.frame(width: 25)
            }.buttonStyle(OrbitButtonStyle())
            TextField("Note title", text: title).textFieldStyle(OrbitTextFieldStyle()).disabled(note.loadFailed)
            if preview {
                let lines = note.text.components(separatedBy: "\n")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()).dropFirst(page * 8).prefix(8), id: \.offset) { index, line in
                        if line.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ] ") || line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("- [x] ") {
                            Button { note.toggleChecklist(index) } label: { HStack(alignment: .top, spacing: 8) { Image(systemName: line.lowercased().contains("- [x]") ? "checkmark.circle.fill" : "circle"); Text(String(line.trimmingCharacters(in: .whitespaces).dropFirst(6))).strikethrough(line.lowercased().contains("- [x]")) }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
                        } else { Text((try? AttributedString(markdown: line)) ?? AttributedString(line)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    }
                    if lines.count > 8 { HStack { Button("Previous") { page = max(0, page - 1) }.disabled(page == 0); Spacer(); Button("Next") { page = min((lines.count - 1) / 8, page + 1) }.disabled((page + 1) * 8 >= lines.count) }.buttonStyle(OrbitButtonStyle()) }
                }.font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            } else { TextEditor(text: $note.text).font(.system(size: 12)).scrollContentBackground(.hidden).scrollIndicators(.never).frame(height: 185).disabled(note.loadFailed).accessibilityLabel("Note text") }
            HStack { Text(note.status).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Button("Add checklist") { note.append("- [ ] New item") }.buttonStyle(OrbitButtonStyle()).disabled(note.loadFailed) }
        }.alert("Delete this note?", isPresented: $deletePrompt) { Button("Delete", role: .destructive) { note.deleteSelected() }; Button("Cancel", role: .cancel) {} } message: { Text("Export a copy first if you want to keep it.") }
    }
}
