import SwiftUI
import AppKit
import OrbitCore

struct TextToolsView: View {
    @Environment(\.orbitSurface) private var surface
    @Environment(\.notchToolBudget) private var budget
    @ObservedObject var store: OrbitStore
    @ObservedObject var selection: TextSelection
    var compact: Bool
    private var valid: Bool { if case .success = selection.result { return !selection.input.isEmpty }; return false }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            if !compact { SectionTitle(title: "Make something of your selection.", subtitle: "Highlight text in any supported app and open the wheel. Or paste something here.") }
            HStack(spacing: 8) {
                Label(selection.source, systemImage: selection.hasSelection ? "cursorarrow.rays" : "text.cursor").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Use clipboard") {
                    if let text = NSPasteboard.general.string(forType: .string) { selection.useText(text, source: "Clipboard") }
                    else { selection.feedback = "There’s no text on the clipboard." }
                }.buttonStyle(OrbitButtonStyle())
            }
            if compact {
                sourceCard
                actionChooser
                resultCard
            } else {
                HStack(alignment: .top, spacing: 16) { sourceCard; resultCard }
                actionChooser
            }
            HStack(spacing: 10) {
                Button { if let url = TextActions.searchURL(selection.input) { NSWorkspace.shared.open(url) } } label: { Label("Search web", systemImage: "magnifyingglass") }.buttonStyle(OrbitButtonStyle()).disabled(TextActions.searchURL(selection.input) == nil)
                if let url = TextActions.webURL(selection.input) { Button("Open link") { NSWorkspace.shared.open(url) }.buttonStyle(OrbitButtonStyle()) }
                Spacer(minLength: 0)
            }
            if let feedback = selection.feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if !compact { Text("Text actions run locally. Search web sends the source text to DuckDuckGo only when you choose it. Reading and replacing another app’s selection needs Accessibility; clipboard input works without it.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3) }
        }
    }
    private var sourceCard: some View {
        OrbitCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("SOURCE").tracking(1.3); Spacer(); Text(sourceCount) }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    TextEditor(text: $selection.input).font(.system(size: 13)).scrollContentBackground(.hidden).scrollIndicators(.never)
                        .frame(height: compact ? surface == .notch ? min(85, max(36, (budget - 285) / 2)) : 85 : 176)
                        .overlay(alignment: .topLeading) { if selection.input.isEmpty { Text("Your text goes here…").font(.system(size: 13)).foregroundStyle(.tertiary).padding(.top, 2).padding(.leading, 5).allowsHitTesting(false) } }
                        .accessibilityLabel("Source text")
                }
            }
    }
    private var sourceCount: String {
        let words = TextActions.wordCount(selection.input)
        let characters = selection.input.count
        return "\(words) \(words == 1 ? "word" : "words") · \(characters) \(characters == 1 ? "character" : "characters")"
    }
    private var actionChooser: some View {
        Group { if compact {
                OrbitMenuPicker(title: "Text action", selection: $selection.transform, options: TextTransform.allCases.map { ($0.title, $0) })
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 8)], spacing: 8) {
                    ForEach(TextTransform.allCases) { action in
                        Button { selection.transform = action } label: {
                            Label(action.title, systemImage: action.symbol).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(OrbitButtonStyle(prominent: selection.transform == action))
                    }
                }
            } }
    }
    private var resultCard: some View {
        OrbitCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("RESULT").tracking(1.3).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary); Spacer(); Label("On device", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(.secondary) }
                    switch selection.result {
                    case .success(let text):
                        ScrollView { Text(text.isEmpty ? "Choose an action to see your result." : text).font(.system(size: 13, design: selection.transform == .formatJSON ? .monospaced : .default)).foregroundStyle(text.isEmpty ? .secondary : .primary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.scrollIndicators(.never).frame(height: compact ? surface == .notch ? min(80, max(36, (budget - 285) / 2)) : 80 : 128)
                    case .failure(let error): Text(error.localizedDescription).font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    HStack(spacing: 8) {
                        Button("Copy result") { store.copy(selection.output); selection.feedback = "Result copied." }.buttonStyle(OrbitButtonStyle(prominent: true)).disabled(!valid)
                        if selection.canReplace { Button("Replace selection") { selection.replaceSelection() }.buttonStyle(OrbitButtonStyle()).disabled(!valid).help("Replace only the original selection, if it has not changed") }
                        Spacer(); Button { store.scratchpad.append(selection.output); selection.feedback = store.scratchpad.status == "Saving…" ? "Added to scratchpad." : store.scratchpad.status } label: { Image(systemName: "square.and.pencil") }.buttonStyle(OrbitIconButtonStyle()).disabled(!valid || store.scratchpad.loadFailed).help("Add result to scratchpad").accessibilityLabel("Add result to scratchpad")
                    }
                }
            }
    }

}

struct ScratchpadView: View {
    @Environment(\.openOrbitTool) private var openTool
    @ObservedObject var store: OrbitStore
    @ObservedObject var note: Scratchpad
    var compact: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact { SectionTitle(title: "A place for the thought.", subtitle: "Jot it down. Come back to it from the notch, wheel or menu bar.") }
            OrbitCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Label("Scratchpad", systemImage: "square.and.pencil").font(.system(size: 12, weight: .semibold)); Spacer(); Text("\(note.text.count) characters").font(.system(size: 10)).foregroundStyle(.secondary) }
                    TextEditor(text: $note.text).font(.system(size: 12)).scrollContentBackground(.hidden).scrollIndicators(.never)
                        .frame(minHeight: compact ? 155 : 320).disabled(note.loadFailed).accessibilityLabel("Scratchpad note")
                        .overlay(alignment: .topLeading) { if note.text.isEmpty { Text("A thought, a draft, something to remember…").font(.system(size: 13)).foregroundStyle(.tertiary).padding(.top, 2).padding(.leading, 5).allowsHitTesting(false) } }
                    HStack { Text(note.status).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Button("Copy") { store.copy(note.text) }.buttonStyle(OrbitButtonStyle()).disabled(note.text.isEmpty) }
                }
            }
            HStack {
                Button("Add clipboard") { if let text = NSPasteboard.general.string(forType: .string) { note.append(text) } }.buttonStyle(OrbitButtonStyle()).disabled(note.loadFailed)
                Button("Export…") { note.export() }.buttonStyle(OrbitButtonStyle()).disabled(note.text.isEmpty)

            }
            Button("Use in Text Studio") { store.selection.useText(note.text, source: "Scratchpad"); openTool(.textTools) }.buttonStyle(OrbitButtonStyle()).disabled(note.text.isEmpty || note.text.utf8.count > TextActions.maximumBytes)
            if !compact { Label("Autosaved locally. No cloud account or subscription.", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}
