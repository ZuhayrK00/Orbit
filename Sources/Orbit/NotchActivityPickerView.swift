import SwiftUI
import OrbitCore

struct NotchCompactView: View {
    @ObservedObject var store: OrbitStore
    let cameraSize: CGSize
    var physicalCamera: Bool
    var stripWidth: Double
    private var readout: NotchHeaderView {
        var view = NotchHeaderView(store: store, cameraWidth: cameraSize.width, stripHeight: cameraSize.height)
        view.physicalCamera = physicalCamera
        return view
    }
    var body: some View {
        readout.frame(width: stripWidth, height: cameraSize.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A short hover surface: choosing a readout never changes the last open utility.
struct NotchActivityPickerView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var media: MediaService
    init(store: OrbitStore) { self.store = store; media = store.media }
    private var selected: NotchActivityKind? { store.selectedNotchActivity }
    private var display: NotchHeaderView { NotchHeaderView(store: store, cameraWidth: 0) }
    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(3, max(1, store.availableNotchActivities.count))), spacing: 6) {
                ForEach(store.availableNotchActivities) { kind in
                    Button { store.selectNotchActivity(kind) } label: {
                        display.activityIcon(kind)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(selected == kind ? display.color(kind).opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 11))
                            .foregroundStyle(selected == kind ? display.color(kind) : .secondary)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Show live \(kind.title)")
                        .accessibilityValue(selected == kind ? "Selected" : "").help(kind.title)
                }
            }
            if let selected {
                HStack(spacing: 8) {
                    Text(display.label(selected)).font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit().lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if selected == .timer {
                        Button { store.toggleTimer() } label: { Image(systemName: store.timerState.end == nil ? "play.fill" : "pause.fill").frame(width: 28, height: 24).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel(store.timerState.end == nil ? "Resume timer" : "Pause timer")
                    }
                    if selected == .music {
                        Button {
                            store.holdNotchMusic = true; store.media.command("playpause")
                        } label: { Image(systemName: media.isPlaying ? "pause.fill" : "play.fill").frame(width: 28, height: 24).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel(media.isPlaying ? "Pause music" : "Resume music")
                    }
                    Button { store.openNotchActivity(selected) } label: { Image(systemName: "arrow.up.forward").frame(width: 28, height: 24).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Open selected activity").help("Open \(selected.title)")
                }.frame(height: 24)
                if selected == .agent, store.activeAgents.count > 1 {
                    HStack(spacing: 8) {
                        Button { store.stepNotchAgent(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28).contentShape(Rectangle()) }
                            .accessibilityLabel("Previous live agent")
                        Text(store.liveNotchAgent?.title ?? "Agent").font(.system(size: 10)).lineLimit(1).frame(maxWidth: .infinity)
                        Button { store.stepNotchAgent(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28).contentShape(Rectangle()) }
                            .accessibilityLabel("Next live agent")
                    }.buttonStyle(.plain).foregroundStyle(.secondary).frame(height: 28)
                } else if !store.notchCompanionChoices.isEmpty {
                    HStack(spacing: 6) {
                        Text("Pair with").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        ForEach(store.notchCompanionChoices) { companion in
                            Button { store.selectNotchActivity(selected, companion: store.notchCompanion == companion ? nil : companion) } label: {
                                display.activityIcon(companion).frame(width: 32, height: 28)
                                    .background(store.notchCompanion == companion ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Pair timer with \(companion.title)")
                                .accessibilityValue(store.notchCompanion == companion ? "Selected" : "").help(companion.title)
                        }
                    }.frame(height: 28)
                }
            }
        }.padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .top).preferredColorScheme(.dark)
            // The notch compositor owns the background, clipping and reveal.
            // A second native glass surface here escapes the shell's animation.
            .foregroundStyle(.white).orbitControls(store)
            .environment(\.controlActiveState, .active)
    }
}
