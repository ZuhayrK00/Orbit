import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook
import OrbitCore

struct LibraryView: View {
    @Environment(\.openOrbitTool) private var openTool
    @ObservedObject var store: OrbitStore
    @ObservedObject var library: ItemLibrary
    var shelf = false
    @State private var query = ""
    @State private var page = 0
    @State private var selected: UUID?
    @State private var preview: URL?
    @State private var link = ""
    @State private var showLink = false
    private var matches: [StoredItem] { library.items.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }.sorted { $0.pinned && !$1.pinned } }
    var body: some View {
        VStack(spacing: 10) {
            if !shelf && !store.configuration.clipboardEnabled {
                EmptyState(symbol: "clipboard", title: "Your clipboard, by choice", detail: "Keep text, images and files. Concealed and transient copies are skipped. Disk history is optional in Productivity settings.")
                Button("Enable history") { store.configuration.clipboardEnabled = true }.buttonStyle(OrbitButtonStyle(prominent: true))
            } else {
                HStack {
                    TextField(shelf ? "Find on shelf" : "Search clipboard", text: $query).textFieldStyle(OrbitTextFieldStyle())
                    if shelf { Button { library.choose() } label: { Image(systemName: "plus") }.help("Add files"); Button { showLink.toggle() } label: { Image(systemName: "link") }.help("Add link") }
                    Button("Clear unpinned") { library.clear() }.font(.system(size: 10))
                }.buttonStyle(OrbitButtonStyle())
                if showLink { HStack { TextField("https://…", text: $link).textFieldStyle(OrbitTextFieldStyle()); Button("Add") { if let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { library.addURLs([url]); link = ""; showLink = false } } } }
                if matches.isEmpty {
                    EmptyState(symbol: shelf ? "tray.and.arrow.down" : "doc.on.clipboard", title: shelf ? "Drop something here" : "Copy something useful", detail: shelf ? "Files, images and links. Drag them back out whenever you need them." : "Use ↑ and ↓ to choose, Return to copy, and Space to preview.")
                } else if shelf {
                    CompactPages(items: matches, page: $page, pageSize: 4) { item in row(item) }
                } else {
                    ScrollViewReader { reader in
                        ScrollView { LazyVStack(spacing: 6) { ForEach(matches) { item in row(item).id(item.id) } } }.scrollIndicators(.never).frame(height: 245)
                            .onChange(of: selected) { _, value in if let value { reader.scrollTo(value, anchor: .center) } }
                    }.focusable().onMoveCommand { direction in
                        let index = matches.firstIndex { $0.id == selected } ?? -1
                        if direction == .down { selected = matches[min(matches.count - 1, index + 1)].id }
                        else if direction == .up { selected = matches[max(0, index - 1)].id }
                    }.onKeyPress(.return) { guard let item = matches.first(where: { $0.id == selected }) else { return .ignored }; library.copy(item); return .handled }
                    .onKeyPress(.space) { guard let item = matches.first(where: { $0.id == selected }) else { return .ignored }; preview = library.urls(item).first(where: \.isFileURL); return .handled }
                }
                if let message = library.message { Text(message).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }.onDrop(of: [UTType.fileURL.identifier, UTType.url.identifier, UTType.image.identifier, UTType.plainText.identifier], isTargeted: nil) { shelf ? library.accept($0) : false }
            .quickLookPreview($preview).onChange(of: query) { _, _ in page = 0; selected = nil }
    }
    private func row(_ item: StoredItem) -> some View {
        HStack(spacing: 10) {
            Button { selected = item.id; if shelf { preview = library.urls(item).first(where: \.isFileURL) } else { library.copy(item) } } label: {
                HStack(spacing: 10) {
                    thumbnail(item).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.text).font(.system(size: 11, weight: .medium)).lineLimit(2)
                        Text(item.kind.rawValue.capitalized + (item.pinned ? " · Pinned" : "")).font(.system(size: 9)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { library.togglePin(item.id) } label: { Image(systemName: item.pinned ? "pin.fill" : "pin") }.help("Pin or unpin").accessibilityLabel("Pin \(item.text.prefix(30))")
            Menu {
                Button("Copy") { library.copy(item) }
                if !library.urls(item).isEmpty {
                    Button("Open") { for url in library.urls(item).prefix(1) { NSWorkspace.shared.open(url) } }
                    Button("Preview") { preview = library.urls(item).first(where: \.isFileURL) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(library.urls(item).filter(\.isFileURL)) }
                    Button("Use in File tools") { store.selectedFiles = library.urls(item).filter(\.isFileURL); openTool(.files) }
                    ShareLink(items: library.urls(item)) { Text("Share…") }
                } else { ShareLink(item: item.text) { Text("Share…") } }
                if !shelf { Button("Add to shelf") { store.shelf.importItem(item, from: library) } }
                Button("Remove from \(shelf ? "shelf" : "history")") { library.remove(item.id) }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 22)
        }.buttonStyle(.plain).padding(10).background(selected == item.id ? Color.white.opacity(0.12) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .onDrag { if let url = library.urls(item).first { return NSItemProvider(object: url as NSURL) }; return NSItemProvider(object: item.text as NSString) }
    }
    @ViewBuilder private func thumbnail(_ item: StoredItem) -> some View {
        if let url = library.assetURL(item), let image = NSImage(contentsOf: url) { Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 5)) }
        else if let path = item.paths.first { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().scaledToFit() }
        else { Image(systemName: item.kind == .link ? "link" : "text.alignleft").font(.system(size: 18)).foregroundStyle(.secondary) }
    }
}

struct CompactPages<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @Binding var page: Int
    var pageSize = 3
    @ViewBuilder var content: (Item) -> Content
    private var last: Int { max(0, (items.count - 1) / pageSize) }
    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(items.dropFirst(min(page, last) * pageSize).prefix(pageSize))) { content($0) }
            if items.count > pageSize { HStack { Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }.disabled(page == 0); Spacer(); Text("\(min(page, last) + 1) / \(last + 1)").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Button { page = min(last, page + 1) } label: { Image(systemName: "chevron.right") }.disabled(page >= last) }.buttonStyle(OrbitIconButtonStyle()) }
        }
    }
}

struct AgendaView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var calendar: CalendarService
    @State private var page = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Next seven days").font(.system(size: 11, weight: .medium)); Spacer(); Button { calendar.refresh(force: true) } label: { Image(systemName: "arrow.clockwise") }; Button("Calendar") { calendar.openCalendar() } }.buttonStyle(OrbitButtonStyle())
            if store.configuration.productivity.calendarEnabled != true {
                EmptyState(symbol: "calendar", title: "Your agenda, close by", detail: "Read upcoming events from the calendars on this Mac.")
                Button("Connect Calendar") { store.editProductivity { $0.calendarEnabled = true }; calendar.requestAccess() }.buttonStyle(OrbitButtonStyle(prominent: true)).disabled(calendar.requestingAccess)
            } else if !calendar.allowed { Button(calendar.accessButtonTitle) { calendar.requestAccess() }.buttonStyle(OrbitButtonStyle(prominent: true)).disabled(calendar.requestingAccess) }
            else if calendar.events.isEmpty { EmptyState(symbol: "calendar.badge.checkmark", title: "Nothing coming up", detail: "Your next events will appear here.") }
            else { CompactPages(items: calendar.events, page: $page) { event in
                OrbitCard { HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: event.color)).frame(width: 3)
                    VStack(alignment: .leading, spacing: 4) { Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(2); Text(event.start, format: .dateTime.weekday().day().month()).font(.system(size: 10)).foregroundStyle(.secondary); Text(event.allDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened) + " – " + event.end.formatted(date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
                    if event.meeting != nil { Button("Join") { calendar.join(event) }.buttonStyle(OrbitButtonStyle(prominent: true)) }
                } }
            } }
            if let message = calendar.message { Text(message).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}

struct DownloadsView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var downloads: DownloadService
    @State private var page = 0
    var body: some View {
        VStack(spacing: 10) {
            HStack { Text("Downloads").font(.system(size: 12, weight: .semibold)); Spacer(); Button("Clear finished") { downloads.clearFinished() }.buttonStyle(OrbitButtonStyle()) }
            if store.configuration.productivity.downloadsEnabled != true { EmptyState(symbol: "arrow.down.circle", title: "Follow your downloads", detail: "Track browser download files locally. Progress uses byte totals when the browser publishes them."); Button("Watch Downloads folder") { store.editProductivity { $0.downloadsEnabled = true } }.buttonStyle(OrbitButtonStyle(prominent: true)) }
            else if downloads.activities.isEmpty { EmptyState(symbol: "arrow.down.circle", title: "Ready for your next download", detail: "New .download, .crdownload and .part transfers will appear here.") }
            CompactPages(items: downloads.activities, page: $page) { item in
                OrbitCard { VStack(alignment: .leading, spacing: 8) {
                    HStack { Image(systemName: item.state == .complete ? "checkmark.circle.fill" : "arrow.down.circle").foregroundStyle(item.state == .complete ? .mint : .blue); Text(URL(fileURLWithPath: item.target).lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1); Spacer() }
                    if item.state == .downloading { if let fraction = item.fraction { ProgressView(value: fraction) } else { HStack { ProgressView().controlSize(.small); Text("Downloading…").font(.system(size: 10)) } } }
                    HStack { Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file) + (item.state == .missing ? " · Cancelled or moved" : item.state == .complete ? " · Complete" : " received")).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); if item.state == .complete { Button("Open") { downloads.open(item) }; Button("Finder") { downloads.reveal(item) } } }.buttonStyle(OrbitButtonStyle())
                } }
            }
            if let error = downloads.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
        }
    }
}

struct ScreenTextView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var ocr: ScreenTextService
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.viewfinder").font(.system(size: 35)).foregroundStyle(.mint)
            Text("Copy text from your screen").font(.system(size: 16, weight: .semibold))
            Text("Draw around text in an image, video or app. Orbit reads it locally, copies it and deletes the capture.").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(ocr.busy ? "Selecting…" : "Select a screen region") { store.captureScreenText() }.buttonStyle(OrbitButtonStyle(prominent: true)).disabled(ocr.busy)
            if let message = ocr.message { Text(message).font(.system(size: 11)).foregroundStyle(.secondary) }
            if !ocr.text.isEmpty { Text(ocr.text).font(.system(size: 11)).lineLimit(6).textSelection(.enabled); Button("Copy again") { store.copy(ocr.text) }.buttonStyle(OrbitButtonStyle()) }
        }.padding(.vertical, 15)
    }
}

struct HomeView: View {
    @Environment(\.openOrbitTool) private var openTool
    @ObservedObject var store: OrbitStore
    @ObservedObject var media: MediaService
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            card(.agents, title: "Agents", detail: "\(store.activeAgents.count) active")
            card(.music, title: media.isPlaying ? media.title : "Now playing", detail: media.isPlaying ? media.artist : "Music controls")
            card(.calendar, title: store.calendar.events.first?.title ?? "Your agenda", detail: store.calendar.events.first?.start.formatted(date: .abbreviated, time: .shortened) ?? "Upcoming events")
            card(.shelf, title: "File shelf", detail: "\(store.shelf.items.count) parked items")
            card(.timer, title: store.focusCycle.running ? store.focusCycle.title : "Timer", detail: store.timerState.isActive ? OrbitTimer.label(store.timerState.remaining(at: store.now)) : "Time to focus")
            card(.downloads, title: "Downloads", detail: store.downloads.live.map { URL(fileURLWithPath: $0.target).lastPathComponent } ?? "Ready for your next file")
        }
    }
    private func card(_ action: OrbitAction, title: String, detail: String) -> some View {
        Button { openTool(action) } label: {
            VStack(alignment: .leading, spacing: 7) { Image(systemName: action.symbol).font(.system(size: 18)).foregroundStyle(action.toolColor); Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1); Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
