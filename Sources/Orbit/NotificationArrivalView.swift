import SwiftUI
import OrbitCore

/// A temporary message uses the notch itself, rather than opening the inbox.
struct NotificationArrivalView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var monitor: NotificationMonitor
    let cameraSize: CGSize
    var body: some View {
        if let notice = monitor.announcement {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        NotificationAppIcon(notice: notice, size: 26)
                        if !notice.app.isEmpty { Text(notice.app).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: cameraSize.width > 0 ? cameraSize.width + 16 : 0)
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)
                        Text(notice.received, format: .dateTime.hour().minute()).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                        Button { monitor.dismiss(notice.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(OrbitIconButtonStyle()).accessibilityLabel("Dismiss notification from Orbit")
                    }.frame(maxWidth: .infinity)
                }.frame(height: max(30, cameraSize.height))
                if notice.bundleID != nil {
                    Button { monitor.openApp(notice) } label: { message(notice) }
                        .buttonStyle(.plain).accessibilityLabel("\(notice.title). Open \(notice.app)")
                } else { message(notice) }
                NotificationQuickActions(notice: notice, monitor: monitor)
                if let feedback = monitor.actionMessage {
                    Text(feedback).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !monitor.items.isEmpty {
                    HStack {
                        Spacer()
                        Button { store.selectNotchTool(.notifications, pinned: true) } label: {
                            Label("Inbox · \(monitor.items.count)", systemImage: "tray")
                        }.buttonStyle(OrbitButtonStyle()).accessibilityLabel("Open notification inbox")
                    }
                }
            }.accessibilityElement(children: .contain)
        }
    }
    private func message(_ notice: NotchNotice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !notice.title.isEmpty { Text(notice.title).font(.system(size: 15, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
            if !notice.body.isEmpty { Text(notice.body).font(.system(size: 13)).foregroundStyle(.white.opacity(0.82)).lineLimit(6).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

struct NotificationQuickActions: View {
    let notice: NotchNotice
    @ObservedObject var monitor: NotificationMonitor
    private var actions: [NoticeAction] { monitor.liveActions[notice.id] ?? [] }
    var body: some View {
        if !actions.isEmpty || notice.bundleID != nil {
            // Long native labels wrap as a group instead of clipping or scrolling.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var buttons: some View {
        ForEach(actions) { action in
            Button(action.title) { monitor.perform(action, notice: notice) }
                .buttonStyle(OrbitButtonStyle(prominent: action.kind == .answer, color: action.kind == .answer ? .green : action.kind == .decline ? .red : nil)).fixedSize()
        }
        if notice.bundleID != nil, !actions.contains(where: { $0.kind == .open }) {
            Button("Open app") { monitor.openApp(notice) }.buttonStyle(OrbitButtonStyle()).fixedSize()
        }
    }
}
