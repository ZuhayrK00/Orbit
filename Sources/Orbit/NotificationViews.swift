import SwiftUI
import OrbitCore

struct NotificationSettingsView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var monitor: NotificationMonitor
    private func option<Value>(_ key: WritableKeyPath<NotchNotificationOptions, Value>) -> Binding<Value> {
        Binding(get: { store.configuration.notifications[keyPath: key] }, set: { value in
            var options = store.configuration.notifications; options[keyPath: key] = value
            options.normalize(); store.configuration.notificationSettings = options
        })
    }
    var body: some View {
        VStack(spacing: 12) {
            PermissionCard(store: store)
            OrbitCard {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsToggleRow("Show Mac notifications in the notch", isOn: option(\.enabled))
                    HStack(spacing: 8) {
                        Circle().fill(store.configuration.notifications.enabled && store.inputPermission ? Color.mint : .secondary).frame(width: 6, height: 6)
                        Text(monitor.status).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    Text("Orbit mirrors new, visible notification banners using Accessibility. Your access status is shown above and updates automatically.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !store.configuration.notchEnabled {
                        Button("Enable the notch") { store.configuration.notchEnabled = true }.buttonStyle(OrbitButtonStyle(prominent: true))
                    }
                }
            }
            OrbitCard {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsToggleRow("Expand the notch when a notification arrives", isOn: option(\.expandAutomatically))
                    Text("Shows one message with its app icon and available actions. When off, a compact banner shows the app and message beside the camera; hover or click to read it. A notification won’t interrupt an open tool.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    SettingsToggleRow("Show notification previews", isOn: option(\.showPreview))
                    SettingsToggleRow("Show incoming calls", isOn: Binding(get: { store.configuration.notifications.callsEnabled }, set: { var options = store.configuration.notifications; options.includeCalls = $0; store.configuration.notificationSettings = options }))
                    Text("Phone and FaceTime calls appear when macOS exposes their incoming-call controls. Answer and Decline are shown only while those controls are available.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Turn previews off to show only the app’s name and “New notification”.").font(.system(size: 11)).foregroundStyle(.secondary)
                    SettingSlider(title: "Display for", value: option(\.duration), range: 3...15, unit: "s")
                    Button("Preview in notch") { monitor.preview() }.buttonStyle(OrbitButtonStyle(prominent: true)).disabled(!store.configuration.notchEnabled)
                    Text("The preview stays open while your pointer is over it. It is a labelled sample, not a system notification.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            OrbitCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Notification delivery", systemImage: "rectangle.badge.checkmark").font(.system(size: 13, weight: .medium))
                    Text("Orbit mirrors visible Mac banners. macOS doesn’t provide a system-wide replacement switch to third-party apps. Turning off an app’s Mac banners also prevents Orbit from reading them.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Available actions follow the original notification. Reply opens its native reply control; older inbox items can still open their app. Orbit never sends a reply automatically.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open macOS notification settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!) }.buttonStyle(OrbitButtonStyle())
                }
            }
            OrbitCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Only on this Mac", systemImage: "lock.shield").font(.system(size: 13, weight: .medium))
                    Text("Up to 30 notifications stay in memory for this session. Turning mirroring off, locking your Mac or quitting Orbit clears them. Nothing is saved to disk or uploaded.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("The original banners, sounds and Notification Center stay as macOS configured them. Orbit doesn’t import old history or notifications hidden by Focus. Some macOS versions or apps may not expose readable banners.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Clear Orbit’s inbox") { monitor.clear() }.buttonStyle(OrbitButtonStyle()).disabled(monitor.items.isEmpty)
                }
            }
        }
    }
}

struct NotificationInboxView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var monitor: NotificationMonitor
    @Environment(\.notchToolBudget) private var budget
    private var notices: [NotchNotice] { monitor.items }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if notices.isEmpty {
                EmptyState(symbol: "bell", title: store.configuration.notifications.enabled ? "Nothing new yet" : "Your notifications, nearby",
                           detail: store.configuration.notifications.enabled ? monitor.status + ". New visible Mac banners appear here." : "Turn on mirroring to see new Mac notifications in Orbit.")
            } else {
                NotchPagedList(items: notices, heightBudget: max(160, budget - 70), maximumRows: 2) { notice in
                    OrbitCard {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 8) {
                                NotificationAppIcon(notice: notice, size: 22)
                                if !notice.app.isEmpty { Text(notice.app).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                                Spacer()
                                Text(notice.received, format: .dateTime.hour().minute()).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                                Button { monitor.dismiss(notice.id) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(OrbitIconButtonStyle()).accessibilityLabel("Dismiss from Orbit").help("Remove from Orbit only")
                            }
                            if notice.bundleID != nil {
                                Button { monitor.openApp(notice) } label: { message(notice) }
                                    .buttonStyle(.plain).accessibilityLabel("\(notice.title). Open \(notice.app)")
                            } else { message(notice) }
                            NotificationQuickActions(notice: notice, monitor: monitor)
                        }
                    }
                }
            }
            if let message = monitor.actionMessage { Text(message).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Notification settings") { store.settingsTab = "Notifications"; store.openSettings?() }.buttonStyle(OrbitButtonStyle())
                Spacer()
                if !monitor.items.isEmpty { Button("Clear inbox") { monitor.clear() }.buttonStyle(OrbitButtonStyle()) }
            }
        }
    }
    private func message(_ notice: NotchNotice) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(notice.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if !notice.body.isEmpty { Text(notice.body).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(4).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
