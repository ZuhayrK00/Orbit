import SwiftUI
import OrbitCore

struct NotchHeaderView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var media: MediaService
    var cameraWidth: Double
    var stripHeight: Double
    var physicalCamera = true
    init(store: OrbitStore, cameraWidth: Double, stripHeight: Double = 34) { self.store = store; self.media = store.media; self.cameraWidth = cameraWidth; self.stripHeight = stripHeight }
    private var activeAgent: AgentStatus? { store.liveNotchAgent }
    private var activity: NotchActivityKind? { store.currentNotchActivity }
    private func compactLabel(_ activity: NotchActivityKind) -> String {
        switch activity {
        case .music: return media.isPlaying ? "Playing" : "Paused"
        case .keepAwake: return store.awake.until.map { NotchLayout.compactDuration($0.timeIntervalSince(max(store.now, Date()))) } ?? "∞"
        case .timer:
            let seconds = store.timerState.remaining(at: store.now)
            return seconds >= 60 ? NotchLayout.compactDuration(seconds) : "\(max(0, Int(ceil(seconds))))s"
        default: return label(activity)
        }
    }
    private var agentProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in store.activeAgents.contains { AIProvider(activityName: $0.provider) == provider } }
    }
    private func textSize(for kind: NotchActivityKind) -> Double {
        kind == .agent ? NotchLayout.compactAgentTextSize(height: stripHeight) : NotchLayout.compactTextSize(height: stripHeight)
    }
    private var textSize: Double { textSize(for: activity ?? .timer) }
    private var iconSize: Double { NotchLayout.compactIconSize(height: stripHeight) }
    private var agentIconSize: Double { iconSize }
    private func iconInset(for kind: NotchActivityKind) -> Double {
        if kind == .music { return NotchLayout.musicArtworkInset(height: stripHeight) }
        let height = kind == .agent ? agentIconSize + 4 : iconSize
        return NotchLayout.compactInset(height: stripHeight, contentHeight: height, radius: height / 2)
    }
    private var textInset: Double { NotchLayout.compactInset(height: stripHeight, contentHeight: textSize * 0.72) }
    func widthStyle(for kind: NotchActivityKind) -> NotchLayout.ActivityWidth {
        switch kind {
        case .timer, .keepAwake: return .timer
        case .agent: return .agent
        case .music: return .music
        case .notification: return .notification
        default: return .notice
        }
    }
    func stripSize(for kind: NotchActivityKind?, companion: NotchActivityKind? = nil, availableWing: Double, screenWidth: Double) -> CGSize {
        let base = CGSize(width: cameraWidth, height: stripHeight)
        guard let kind else { return base }
        return NotchLayout.compactSize(cameraSize: base, requiredWing: requiredWingWidth(for: kind, companion: companion),
                                      availableWing: availableWing, activity: widthStyle(for: kind), screenWidth: screenWidth)
    }
    func requiredWingWidth(for activity: NotchActivityKind, companion: NotchActivityKind? = nil) -> Double {
        if activity == .music { return NotchLayout.musicWing(height: stripHeight, physicalCamera: physicalCamera) }
        if activity == .notification, let notice = store.notifications.announcement {
            let font = NSFont.systemFont(ofSize: 11, weight: .medium)
            let app = (String(notice.app.prefix(80)) as NSString).size(withAttributes: [.font: font]).width
            let message = (String(notice.compactDetail.prefix(240)) as NSString).boundingRect(with: CGSize(width: 158, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).width
            return min(190, max(iconSize + 7 + ceil(app), ceil(message)) + 28)
        }
        let font = textSize(for: activity)
        // Measure a stable digit pattern, so seconds do not shake the surface.
        let shape = String(compactLabel(activity).map { $0.isNumber ? Character("0") : $0 })
        let readingWidth = activity == .keepAwake && store.awake.until == nil
            ? NotchSymbolMeasure.width("infinity", size: font)
            : ceil((shape as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: font, weight: .medium)]).width)
        let reading = readingWidth + NotchLayout.compactInset(height: stripHeight, contentHeight: font * 0.72)
        let mark = companion ?? activity
        let markWidth: Double
        if mark == .agent {
            let count = max(1, agentProviders.count)
            markWidth = Double(count) * (agentIconSize * 1.45 + 1) + Double(count - 1)
        } else if mark == .music { markWidth = NotchLayout.musicArtworkSide(height: stripHeight) }
        else if mark == .keepAwake {
            markWidth = NotchSymbolMeasure.width(symbol(mark), size: iconSize)
        } else { markWidth = iconSize }
        return max(reading, markWidth + iconInset(for: mark)) + 6
    }
    private var animates: Bool { store.configuration.notch.animateActivityIcons && !store.reduceMotion && !store.notchExpanded }
    @ViewBuilder private func compactMark(_ mark: NotchActivityKind) -> some View {
        if mark == .notification, let notice = store.notifications.announcement {
            NotificationAppIcon(notice: notice, size: iconSize)
        } else if mark == .music {
            let side = iconSize
            MediaCover(media: media, size: side)
        } else if mark == .agent, !agentProviders.isEmpty {
            HStack(spacing: 1) {
                ForEach(agentProviders, id: \.self) { provider in
                    NotchActivityIcon(activity: mark, symbol: symbol(mark), waiting: activeAgent?.displayedPhase(now: store.now) == .waiting,
                        timerPaused: false, motionEnabled: animates, eventID: eventID(mark), agentProvider: provider, size: agentIconSize)
                        .frame(width: agentIconSize * 1.45 + 1)
                }
            }
        } else {
            NotchActivityIcon(activity: mark, symbol: symbol(mark), waiting: activeAgent?.displayedPhase(now: store.now) == .waiting,
                timerPaused: store.timerState.end == nil, motionEnabled: animates, eventID: eventID(mark),
                musicPlaying: media.isPlaying, agentProvider: provider(mark), size: iconSize)
                .frame(width: mark == .keepAwake ? nil : iconSize)
        }
    }
    var body: some View {
            GeometryReader { proxy in
                let center = cameraWidth == 0 && activity == nil ? proxy.size.width : max(0, cameraWidth)
                let wing = max(0, (proxy.size.width - center) / 2)
                HStack(spacing: 0) {
                // The compositor fades this header out as the shell opens.
                // Keep its content alive until that fade has actually finished.
                let showsActivity = wing >= (activity == .music ? min(44, requiredWingWidth(for: .music)) : 44)
                if let activity, showsActivity {
                    let mark = store.notchCompanion ?? activity
                    Button { store.openNotchActivity(mark) } label: {
                    if activity == .notification, let notice = store.notifications.announcement {
                        HStack(spacing: 7) {
                            NotificationAppIcon(notice: notice, size: iconSize)
                            if !notice.app.isEmpty { Text(notice.app).font(.system(size: 11, weight: .semibold)).lineLimit(1) }
                        }.padding(.leading, 14).padding(.trailing, 8)
                            .frame(width: wing, height: proxy.size.height, alignment: .leading).contentShape(Rectangle())
                    } else {
                    compactMark(mark).fixedSize().id(mark)
                        .foregroundStyle(color(mark)).padding(.leading, iconInset(for: mark))
                        .frame(width: wing, height: proxy.size.height, alignment: .leading).contentShape(Rectangle())
                    }
                    }.buttonStyle(.plain).accessibilityLabel("Open live \(provider(mark)?.title ?? mark.title)").help("Open \(provider(mark)?.title ?? mark.title)")
                } else { Color.clear.frame(width: wing) }
                if center > 0 { Button {
                    if store.notchExpanded { store.notchExpanded = false; store.notchPinned = false }
                    else { store.expandNotch(pinned: true) }
                } label: { Color.clear.frame(width: center, height: proxy.size.height).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Open Orbit notch: \(store.rememberedNotchSection.title)")
                    .accessibilityValue(activity.map { "\($0.title): \(label($0))" } ?? "")
                    .help("Open \(store.rememberedNotchSection.title)")
                }
                if let activity, showsActivity {
                    Button { store.openNotchActivity(activity) } label: {
                    Group {
                        if activity == .notification, let notice = store.notifications.announcement {
                            Text(notice.compactDetail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                                .lineLimit(stripHeight >= 30 ? 2 : 1).padding(.leading, 8).padding(.trailing, 14)
                        } else if activity == .music {
                            NotchCompactMusicBars(playing: media.isPlaying && animates, height: min(16, max(6, stripHeight - 10)))
                                .foregroundStyle(.mint)
                                .padding(.trailing, NotchLayout.compactInset(height: stripHeight, contentHeight: min(16, max(6, stripHeight - 10)), radius: 0.9))
                        } else if activity == .keepAwake, store.awake.until == nil {
                            Image(systemName: "infinity").font(.system(size: textSize, weight: .medium))
                                .foregroundStyle(color(activity)).padding(.trailing, textInset)
                        } else {
                            Text(compactLabel(activity)).font(.system(size: textSize, weight: .medium)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(activity == .agent ? 0.6 : 0.65).foregroundStyle(color(activity))
                                .padding(.trailing, textInset)
                        }
                    }.frame(width: wing, height: proxy.size.height, alignment: .trailing).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Open \(activity.title): \(label(activity))").help(label(activity))
                } else { Color.clear.frame(width: wing) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(.black).contentShape(Rectangle())
                .preferredColorScheme(.dark)
                .contextMenu {
                    if !store.availableNotchActivities.isEmpty {
                        Button("Choose live activity…") { store.showNotchActivityPicker() }
                    }
                    ForEach(store.availableNotchActivities) { kind in
                        Button("Show \(kind.title)") { store.selectNotchActivity(kind) }
                    }
                }
    }
    func provider(_ activity: NotchActivityKind) -> AIProvider? {
        let name: String?
        switch activity {
        case .agent: name = activeAgent?.provider
        case .agentFinished: name = store.finishedNotchAgent?.provider
        default: name = nil
        }
        return name.flatMap(AIProvider.init(activityName:))
    }
    @ViewBuilder func activityIcon(_ activity: NotchActivityKind) -> some View {
        if let provider = provider(activity) { AgentProviderIcon(provider: provider, size: 16) }
        else { Image(systemName: symbol(activity)).font(.system(size: 15, weight: .medium)) }
    }
    func symbol(_ activity: NotchActivityKind) -> String {
        switch activity {
        case .download: return "arrow.down.circle.fill"
        case .meeting: return "calendar"
        case .stopwatch: return "stopwatch"
        case .notification: return "bell.fill"
        case .agent: return activeAgent?.displayedPhase(now: store.now) == .waiting ? "hand.raised.fill" : "sparkles"
        case .agentFinished: return store.finishedNotchAgent?.phase == .failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        case .timer: return store.timerState.end == nil ? "pause.fill" : "timer"
        case .timerFinished: return "bell.fill"
        case .music: return media.isPlaying ? "waveform" : "pause.fill"
        case .copied: return "doc.on.clipboard.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        }
    }
    func eventID(_ activity: NotchActivityKind) -> String {
        switch activity {
        case .copied: return store.clipboardHistory.items.first?.id.uuidString ?? "copied"
        case .download: return store.downloads.live?.id ?? "download"
        case .meeting: return store.calendar.nextMeeting?.id ?? "meeting"
        case .stopwatch: return "stopwatch"
        case .notification: return store.notifications.announcement?.id ?? "notification"
        case .agent, .agentFinished:
            let agent = activity == .agent ? activeAgent : store.finishedNotchAgent
            return "\(agent?.id ?? "agent")-\(agent?.phase.rawValue ?? "unknown")"
        case .timer, .timerFinished: return "timer"
        case .music: return "music"
        case .keepAwake: return "keepAwake"
        }
    }
    func label(_ activity: NotchActivityKind) -> String {
        switch activity {
        case .download: return store.downloads.live.map { $0.state == .complete ? "Done" : $0.fraction.map { "\(Int($0 * 100))%" } ?? ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file) } ?? "Downloading"
        case .meeting: return store.calendar.nextMeeting.map { $0.start > store.now ? OrbitTimer.label($0.start.timeIntervalSince(store.now)) : "Join" } ?? "Meeting"
        case .stopwatch: return OrbitTimer.label(floor(store.stopwatch.elapsed(at: store.now)))
        case .notification: return store.notifications.announcement?.app ?? "Notification"
        case .agent:
            if activeAgent?.displayedPhase(now: store.now) == .waiting { return "Needs you" }
            return activeAgent?.elapsed(at: store.now).map(OrbitTimer.label) ?? "Working"
        case .agentFinished: return store.finishedNotchAgent?.phase == .failed ? "Failed" : "Done"
        case .timer: return OrbitTimer.label(store.timerState.remaining(at: store.now))
        case .timerFinished: return "Time’s up"
        case .music: return media.title
        case .copied: return "Copied"
        case .keepAwake: return store.awake.until.map { OrbitTimer.label(max(0, $0.timeIntervalSince(store.now))) } ?? "Awake"
        }
    }
    func color(_ activity: NotchActivityKind) -> Color {
        switch activity {
        case .download, .meeting, .stopwatch: return .mint
        case .notification: return OrbitDesign.accent(.blue)
        case .agent: return activeAgent?.displayedPhase(now: store.now).color ?? .mint
        case .agentFinished: return store.finishedNotchAgent?.phase == .failed ? .orange : .mint
        case .timer, .timerFinished: return .orange
        case .music: return .mint
        case .copied: return .white
        case .keepAwake: return .orange
        }
    }
}

struct NotchContentView: View {
    @ObservedObject var store: OrbitStore
    let width: Double
    let cameraSize: CGSize
    let toolBudget: Double
    var measured: (OrbitAction, Double) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.notchShowsNotification {
                NotificationArrivalView(store: store, monitor: store.notifications, cameraSize: cameraSize)
            } else {
            HStack(spacing: 0) {
                Menu {
                    ForEach(OrbitAction.surfaceTools) { action in
                        Button { store.selectNotchTool(action, pinned: true) } label: { Label(action.title, systemImage: action.symbol) }
                    }
                    Divider()
                    Button("Notch settings…") { store.settingsTab = "Notch"; store.openSettings?() }
                    Button("Close notch") { store.notchExpanded = false; store.notchPinned = false }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: store.notchSection.symbol).foregroundStyle(store.notchSection.toolColor).font(.system(size: 12, weight: .medium))
                        if store.notchSection != .music && store.notchSection != .notifications { Text(store.notchSection.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.8) }
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true).accessibilityLabel("Notch tools").help("Switch tool · Notch settings")
                .frame(maxWidth: .infinity, alignment: .leading)
                // Use the camera's wings for the title rather than a blank header band.
                Color.clear.frame(width: cameraSize.width > 0 ? cameraSize.width + 16 : 0)
                HStack {
                    Spacer(minLength: 0)
                    if store.notchSection == .agents {
                        Text("\(store.activeAgents.count) active").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if store.configuration.notch.showInbox { Button { store.selectNotchTool(.notifications, pinned: true) } label: {
                        Image(systemName: store.notifications.items.isEmpty ? "bell" : "bell.badge.fill")
                            .font(.system(size: 12)).foregroundStyle(store.notchSection == .notifications ? OrbitDesign.accent(.blue) : .secondary)
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }.buttonStyle(OrbitIconButtonStyle()).accessibilityLabel("Notification inbox").help("Notification inbox") }
                }.frame(maxWidth: .infinity)
            }.frame(height: NotchLayout.headingHeight(cameraHeight: cameraSize.height))
            SurfaceToolView(store: store, section: store.notchSection) { store.selectNotchTool($0) }
            }
        }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 16)
            .frame(width: width).fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: NotchMeasurementKey.self, value: NotchMeasurement(section: store.notchSection, height: proxy.size.height))
            })
            .onPreferenceChange(NotchMeasurementKey.self) { value in
                if let value { measured(value.section, value.height) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .environment(\.notchToolBudget, toolBudget)
            .preferredColorScheme(.dark).foregroundStyle(.primary).environment(\.orbitSurface, .notch).orbitControls(store)
            .environment(\.controlActiveState, .active)
    }
}

private struct NotchMeasurement: Equatable {
    let section: OrbitAction
    let height: Double
}
private struct NotchMeasurementKey: PreferenceKey {
    static var defaultValue: NotchMeasurement?
    static func reduce(value: inout NotchMeasurement?, nextValue: () -> NotchMeasurement?) { value = nextValue() ?? value }
}

struct NotchRailView: View {
    @ObservedObject var store: OrbitStore
    let actions: [OrbitAction]
    var horizontal = false
    var body: some View {
        OrbitGlassGroup {
            if horizontal {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: min(6, max(1, actions.count))), spacing: 8) { buttons }
            } else { VStack(spacing: 8) { buttons }.frame(width: 44) }
        }.preferredColorScheme(.dark).orbitControls(store)
            .environment(\.controlActiveState, .active)
            .environment(\.orbitGlassOutline, store.configuration.notch.outlineEnabled ? OrbitGlassOutline(color: store.configuration.notch.outlineColor.swiftUI, width: store.configuration.notch.outlineWidth) : nil)
    }
    private var buttons: some View {
        ForEach(actions) { action in
            SurfaceIcon(action: action, selected: action == store.notchSection, accent: action.toolColor, title: store.configuration.notch.shortcutTitle(action)) {
                if action == .settings { store.settingsTab = "Notch"; store.openSettings?() }
                else {
                    withAnimation(store.reduceMotion ? nil : .easeOut(duration: 0.16)) { store.selectNotchTool(action) }
                }
            }
        }
    }
}

@MainActor private enum NotchSymbolMeasure {
    private static var widths: [String: Double] = [:]
    static func width(_ name: String, size: Double) -> Double {
        let key = "\(name)-\(size)"
        if let cached = widths[key] { return cached }
        let measured = Double(NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))?.size.width ?? CGFloat(size)).rounded(.up)
        widths[key] = measured
        return measured
    }
}
