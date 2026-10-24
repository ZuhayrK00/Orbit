import SwiftUI
import OrbitCore

/// A quiet, editable readout rather than a boxed form field.
struct TimerDurationControl: View {
    @Binding var minutes: Int
    var label = "Timer duration"
    @State private var draft: String
    @FocusState private var editing: Bool
    init(minutes: Binding<Int>, label: String = "Timer duration") {
        _minutes = minutes; self.label = label
        _draft = State(initialValue: String(minutes.wrappedValue))
    }
    var body: some View {
        HStack(spacing: 8) {
            adjustment(-1, symbol: "minus", name: "Decrease \(label.lowercased())")
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("", text: input).textFieldStyle(.plain)
                    .font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                    .multilineTextAlignment(.center).frame(width: 61)
                    .focused($editing).onSubmit { commit(); editing = false }
                    .accessibilityLabel(label).help("Type a duration in minutes · 1 to 1,440")
                Text("min").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            adjustment(1, symbol: "plus", name: "Increase \(label.lowercased())")
        }.fixedSize().padding(.vertical, 2)
            .onChange(of: editing) { _, focused in if !focused { commit() } }
            .onChange(of: minutes) { _, value in draft = String(value) }
    }
    // Keep the timer ready to start even if a button doesn't resign text focus.
    // External preset selections also replace any draft still being edited.
    private var input: Binding<String> {
        Binding(get: { draft }, set: { value in
            draft = value
            if let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                minutes = min(TimerPresets.durationRange.upperBound, max(TimerPresets.durationRange.lowerBound, number))
            }
        })
    }
    private func adjustment(_ amount: Int, symbol: String, name: String) -> some View {
        let unavailable = amount < 0 ? minutes <= 1 : minutes >= 1440
        return Button {
            commit(); editing = false
            minutes = min(1440, max(1, minutes + amount)); draft = String(minutes)
        } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(unavailable ? 0.2 : 0.75))
                .frame(width: 28, height: 28).background(.white.opacity(0.055), in: Circle())
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(unavailable).accessibilityLabel(name)
    }
    private func commit() {
        if let value = Int(draft.trimmingCharacters(in: .whitespacesAndNewlines)) {
            minutes = min(1440, max(1, value))
        }
        draft = String(minutes)
    }
}

struct TimerPresetButtons: View {
    let presets: [TimerPreset]
    @Binding var minutes: Int
    var disabled = false
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(4, max(1, presets.count))), spacing: 6) {
            ForEach(presets) { preset in
                Button { minutes = preset.minutes } label: { Text("\(preset.minutes) min").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity) }
                    .buttonStyle(OrbitButtonStyle(prominent: minutes == preset.minutes, color: .orange.opacity(0.72)))
                    .disabled(disabled)
            }
        }
    }
}

struct TimerSettingsView: View {
    @ObservedObject var store: OrbitStore
    private var presets: [TimerPreset] { store.configuration.effectiveTimerPresets }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OrbitCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Your timer presets", systemImage: "timer").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("\(presets.count) of \(TimerPresets.maximumCount)").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text("Choose the durations you reach for most. They appear in this order in the notch, wheel and menu bar.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 0) {
                        ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                            HStack(spacing: 16) {
                                Text(String(format: "%02d", index + 1)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 24)
                                TimerDurationControl(minutes: duration(for: preset.id), label: "Preset \(index + 1) minutes")
                                Spacer(minLength: 8)
                                Button { move(preset.id, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .buttonStyle(OrbitIconButtonStyle()).disabled(index == 0).accessibilityLabel("Move preset \(index + 1) up")
                                Button { move(preset.id, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .buttonStyle(OrbitIconButtonStyle()).disabled(index == presets.count - 1).accessibilityLabel("Move preset \(index + 1) down")
                                Button { save(presets.filter { $0.id != preset.id }) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(OrbitIconButtonStyle()).disabled(presets.count == 1).accessibilityLabel("Remove preset \(index + 1)")
                            }.padding(.vertical, 10)
                            if index < presets.count - 1 { Divider().opacity(0.25) }
                        }
                    }
                    HStack {
                        Button { add() } label: { Label("Add preset", systemImage: "plus") }
                            .buttonStyle(OrbitButtonStyle(prominent: true, color: .orange)).disabled(presets.count >= TimerPresets.maximumCount)
                        Spacer()
                        Button("Restore defaults") { save(TimerPresets.defaults) }.buttonStyle(OrbitButtonStyle())
                            .disabled(presets.map(\.minutes) == TimerPresets.defaults.map(\.minutes))
                    }
                }
            }
            Text("From 1 minute to 24 hours. Click a number to type, or use − and +. Changes save automatically and won’t alter a timer already running.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func duration(for id: UUID) -> Binding<Int> {
        Binding(get: { presets.first { $0.id == id }?.minutes ?? 1 }, set: { value in
            var updated = presets
            guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
            updated[index].minutes = value; save(updated)
        })
    }
    private func save(_ values: [TimerPreset]) { store.configuration.timerPresets = TimerPresets.normalize(values) }
    private func add() {
        guard presets.count < TimerPresets.maximumCount else { return }
        let suggested = [10, 20, 30, 60, 90, 120, 180, 240].first { value in !presets.contains { $0.minutes == value } } ?? 10
        save(presets + [TimerPreset(minutes: suggested)])
    }
    private func move(_ id: UUID, by offset: Int) {
        var updated = presets
        guard let index = updated.firstIndex(where: { $0.id == id }), updated.indices.contains(index + offset) else { return }
        updated.swapAt(index, index + offset); save(updated)
    }
}
