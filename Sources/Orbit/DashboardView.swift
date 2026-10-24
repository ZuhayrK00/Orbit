import SwiftUI
import OrbitCore

struct OrbitRootView: View {
    @ObservedObject var store: OrbitStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            OrbitBackdrop(transparency: store.configuration.effectiveGlassTransparency, tint: store.configuration.effectiveGlassColor).ignoresSafeArea()
            if store.onboardingPresented { OnboardingView(store: store).transition(.opacity.combined(with: .scale(scale: 0.98))) }
            else { DashboardView(store: store).transition(.opacity) }
        }
        .preferredColorScheme(.dark).foregroundStyle(.primary)
        .alert("Orbit", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                HStack(spacing: 10) {
                    Image(systemName: store.toastIsPositive ? "checkmark.circle.fill" : "info.circle.fill").foregroundStyle(store.toastIsPositive ? Color.green : Color.secondary)
                    Text(toast).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    Button { store.toast = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }.buttonStyle(.plain)
                }.padding(.horizontal, 18).padding(.vertical, 13).orbitGlass(in: Capsule()).padding(20)
                    .transition(.move(edge: .bottom).combined(with: .opacity)).zIndex(2)
            }
        }.animation(store.reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86), value: store.toast).orbitControls(store)
    }
}
struct DashboardView: View {
    @ObservedObject var store: OrbitStore
    private let sections = [("Controls", "keyboard"), ("Appearance", "circle.lefthalf.filled"), ("Notch", "macbook"), ("Notifications", "bell"), ("Timers", "timer"), ("Productivity", "square.grid.2x2"), ("Wheel", "circle.hexagongrid"), ("Sound", "slider.horizontal.3"), ("Connections", "point.3.connected.trianglepath.dotted"), ("Permissions", "checkmark.shield"), ("Privacy", "hand.raised")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 9) { OrbitMark(size: 23, color: .white.opacity(0.85)); Text("Orbit").font(.system(size: 17, weight: .semibold)) }.padding(.horizontal, 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SETTINGS").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.bottom, 7)
                    ForEach(sections, id: \.0) { name, symbol in
                        Button { store.settingsTab = name } label: {
                            HStack(spacing: 9) {
                                Image(systemName: symbol).font(.system(size: 13)).frame(width: 18)
                                Text(name).font(.system(size: 12, weight: store.settingsTab == name ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }.foregroundStyle(store.settingsTab == name ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 10).frame(height: 34)
                                .background(store.settingsTab == name ? OrbitDesign.accent(store.configuration.accent).opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityValue(store.settingsTab == name ? "Selected" : "")
                    }
                }
                Spacer()
                Button { store.openWheel?() } label: { Label("Open wheel", systemImage: "circle.hexagongrid").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(OrbitButtonStyle())
                Button("Quick setup") { store.startOnboarding() }.font(.system(size: 11)).foregroundStyle(.secondary).buttonStyle(.plain).padding(.horizontal, 10)
                HStack(spacing: 5) { Image(systemName: "lock.shield"); Text("Local & free") }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 10)
            }.padding(.horizontal, 12).padding(.top, 40).padding(.bottom, 20).frame(width: 180).background(Color.black.opacity(0.18))
            Rectangle().fill(.white.opacity(0.055)).frame(width: 0.5)
            ScrollView {
                SettingsView(store: store).frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, 26).padding(.top, 36).padding(.bottom, 28).frame(maxWidth: .infinity)
            }.scrollIndicators(.never).id(store.settingsTab)
        }.frame(minWidth: 840, minHeight: 660)
    }
}
struct UtilityContent: View {
    @ObservedObject var store: OrbitStore
    var compact: Bool
    var section: OrbitAction? = nil
    var body: some View {
        switch section ?? store.selectedSection {
        case .home: HomeView(store: store, media: store.media)
        case .shelf: LibraryView(store: store, library: store.shelf, shelf: true)
        case .downloads: DownloadsView(store: store, downloads: store.downloads)
        case .calendar: AgendaView(store: store, calendar: store.calendar)
        case .screenText: ScreenTextView(store: store, ocr: store.screenText)
        case .files, .compressImage, .convertImage, .zipFiles: FileToolsView(store: store, compact: compact)
        case .textTools: TextToolsView(store: store, selection: store.selection, compact: compact)
        case .scratchpad: NotesView(store: store, note: store.scratchpad)
        case .keepAwake: KeepAwakeView(session: store.awake, store: store, compact: compact)
        case .clipboard: LibraryView(store: store, library: store.clipboardHistory)
        case .sound: SoundView(audio: store.audio, compact: compact)
        case .music: NowPlayingView(store: store, media: store.media, compact: compact)
        case .timer: FocusToolsView(store: store, compact: compact)
        case .agents: AgentsView(store: store, compact: compact)
        case .notifications: NotificationInboxView(store: store, monitor: store.notifications)
        case .settings: if compact { Button("Open settings") { store.openSettings?() }.buttonStyle(OrbitButtonStyle(prominent: true)) } else { SettingsView(store: store) }
        default: EmptyView()
        }
    }
}
