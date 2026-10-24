import SwiftUI
import AppKit
import OrbitCore

struct PermissionsSettingsView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var permissions: PermissionCenter
    @State private var surfaceID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OrbitCard {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.shield").font(.system(size: 26, weight: .light))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Choose what Orbit can access").font(.system(size: 15, weight: .semibold))
                        Text("Each permission belongs to a feature. Your keyboard shortcut, notch and menu bar work without granting them all.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button { permissions.refresh(automation: true) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(OrbitButtonStyle()).help("Check all permissions").accessibilityLabel("Check all permissions")
                }
            }
            group("Controls & tools", kinds: [.accessibility, .screenCapture, .calendar, .notifications])
            group("App connections", kinds: [.music, .spotify, .finder, .systemAudio])
            OrbitCard {
                DisclosureGroup("Files & mouse troubleshooting") {
                    VStack(spacing: 18) {
                        PermissionRow(permissions: permissions, kind: .files)
                        Divider().opacity(0.3)
                        PermissionRow(permissions: permissions, kind: .inputMonitoring)
                        if store.configuration.mouseEnabled {
                            Label(store.mouseTriggerStatus, systemImage: store.mouseMonitoring ? "checkmark.circle" : "info.circle").font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 14)
                }.font(.system(size: 13, weight: .medium))
            }
            Text("Statuses update while this page is open and when you return from System Settings. Access can be removed there at any time.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .onAppear { permissions.setVisible(surfaceID, true) }
        .onDisappear { permissions.setVisible(surfaceID, false) }
    }
    private func group(_ title: String, kinds: [OrbitPermission]) -> some View {
        OrbitCard {
            VStack(alignment: .leading, spacing: 18) {
                Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                ForEach(kinds) { kind in
                    if kind != kinds.first { Divider().opacity(0.3).padding(.leading, 42) }
                    PermissionRow(permissions: permissions, kind: kind)
                }
            }
        }
    }
}

struct PermissionRow: View {
    @ObservedObject var permissions: PermissionCenter
    let kind: OrbitPermission
    @State private var showRecovery = false
    @State private var confirmReset = false
    private var status: PermissionStatus { permissions.status(kind) }
    private var color: Color { status == .granted ? .green : [.denied, .notGranted, .restricted, .limited].contains(status) ? .orange : .secondary }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(color)
                .frame(width: 32, height: 32).background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(kind.title).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    HStack(spacing: 5) {
                        Image(systemName: status == .granted ? "checkmark.circle.fill" : "circle.fill").font(.system(size: status == .granted ? 10 : 5))
                        Text(permissions.requesting.contains(kind) ? "Waiting for macOS…" : status.title).font(.system(size: 11, weight: .medium))
                    }.foregroundStyle(color).accessibilityElement(children: .combine)
                }
                Text(kind.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let error = permissions.errors[kind] { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 8) {
                    if kind.canRequest(status) {
                        Button("Allow access") { permissions.request(kind) }.buttonStyle(OrbitButtonStyle(prominent: true)).disabled(permissions.requesting.contains(kind)).accessibilityLabel("Allow \(kind.title) access")
                    }
                    Button("System Settings") { permissions.openSettings(kind, guided: kind.resetService != nil && status != .granted) }.buttonStyle(OrbitButtonStyle()).accessibilityLabel("\(kind.title) System Settings")
                }.padding(.top, 2)
                if kind.resetService != nil, status != .granted {
                    DisclosureGroup("Already enabled?", isExpanded: $showRecovery) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("An older copy can appear enabled while this copy has no access. Toggle Orbit off and on in System Settings, then check again. If needed, remove its old entry and add this copy.")
                            HStack {
                                Button("Show this app") { permissions.revealApp() }.buttonStyle(OrbitButtonStyle())
                                Button("Check again") { permissions.refresh() }.buttonStyle(OrbitButtonStyle())
                                Button("Start over…") { confirmReset = true }.buttonStyle(OrbitButtonStyle()).disabled(permissions.requesting.contains(kind))
                            }
                            Text(Bundle.main.bundleURL.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        }.font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .alert("Reset Orbit’s \(kind.title) access?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) { }
            Button("Reset access", role: .destructive) { permissions.reset(kind) }
        } message: { Text("This removes only Orbit’s \(kind.title) permission. You’ll need to enable it again in System Settings. Other apps and Orbit’s other permissions are unchanged.") }
    }
    private var hint: String? {
        if kind == .notifications { return permissions.notificationDetail }
        if kind.automationBundleID != nil, status == .unknown { return "Open \(kind.title) to check its status. Orbit won’t launch it just to check access." }
        if kind == .calendar, status == .limited { return "Write-only access cannot display your agenda. Allow full Calendar access to read events." }
        if status == .restricted { return "This Mac’s restrictions control this permission." }
        if kind == .systemAudio { return "macOS has no separate status check for this. The mixer reports whether each audio route is working." }
        return nil
    }
}

struct SetupPermissionsView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var permissions: PermissionCenter
    @State private var surfaceID = UUID()
    @State private var showOptional = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "You're in control.", subtitle: "Enable the tools you want. Everything here is optional.")
                OrbitCard { PermissionRow(permissions: permissions, kind: .accessibility) }
                if let kind = permissions.guide {
                    PermissionGuideContent(permissions: permissions, kind: kind, compact: true)
                }
                OrbitCard {
                    DisclosureGroup("Screen text, Calendar & timer alerts", isExpanded: $showOptional) {
                        VStack(spacing: 18) {
                            ForEach([OrbitPermission.screenCapture, .calendar, .notifications]) { kind in
                                PermissionRow(permissions: permissions, kind: kind)
                                if kind != .notifications { Divider().opacity(0.3) }
                            }
                        }.padding(.top, 16)
                    }.font(.system(size: 12, weight: .medium))
                }
                Text("Music, file access and the sound mixer ask when you use them. You can review every permission later in Settings → Permissions.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button { store.openWheel?() } label: { Label("Try the wheel", systemImage: "circle.hexagongrid") }.buttonStyle(OrbitButtonStyle())
                    Button { store.previewNotch?() } label: { Label("Preview the notch", systemImage: "macbook") }.buttonStyle(OrbitButtonStyle()).disabled(!store.configuration.notchEnabled)
                }
            }.padding(.vertical, 22)
        }.scrollIndicators(.never).frame(maxWidth: 630)
            .onAppear { permissions.setVisible(surfaceID, true) }
            .onDisappear { permissions.setVisible(surfaceID, false); permissions.guide = nil }
    }
}

struct PermissionGuideContent: View {
    @ObservedObject var permissions: PermissionCenter
    let kind: OrbitPermission
    var compact = false
    @State private var stale = false
    @State private var confirmReset = false
    private var allowed: Bool { permissions.isAllowed(kind) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: allowed ? "checkmark.shield.fill" : kind.symbol).foregroundStyle(allowed ? Color.green : .primary)
                Text(kind.title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { permissions.guide = nil } label: { Image(systemName: "xmark").font(.system(size: 11)) }.buttonStyle(OrbitButtonStyle()).accessibilityLabel("Close permission guide")
            }
            if allowed {
                Label("Access confirmed by macOS", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                if kind == .screenCapture { Text("If screen text still cannot capture, reopen Orbit to apply the change.").font(.system(size: 11)).foregroundStyle(.secondary) }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Find Orbit in System Settings.")
                    step(2, "Turn on its switch. Unlock with Touch ID or your Mac password if asked.")
                    step(3, "Keep this guide open. Orbit confirms access automatically.")
                }
                Label("Waiting for macOS to confirm…", systemImage: "clock").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error = permissions.errors[kind] { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if stale && !allowed {
                Text("Switch already on? It may belong to an older build. Add this copy of Orbit, or start over for this permission.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Show this app") { permissions.revealApp() }.buttonStyle(OrbitButtonStyle())
                    if kind.resetService != nil { Button("Start over…") { confirmReset = true }.buttonStyle(OrbitButtonStyle()).disabled(permissions.requesting.contains(kind)) }
                }
            }
            HStack {
                if !allowed { Button("Open Settings") { permissions.openSettings(kind) }.buttonStyle(OrbitButtonStyle(prominent: true)) }
                if kind == .screenCapture { Button("Reopen Orbit") { permissions.relaunch() }.buttonStyle(OrbitButtonStyle()) }
            }
        }
        .padding(compact ? 16 : 20)
        .frame(width: compact ? nil : 330, alignment: .leading)
        .orbitGlass(in: RoundedRectangle(cornerRadius: 20))
        .task(id: kind) { stale = false; try? await Task.sleep(nanoseconds: 12_000_000_000); if !Task.isCancelled { stale = true } }
        .alert("Reset Orbit’s \(kind.title) access?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) { }
            Button("Reset access", role: .destructive) { permissions.reset(kind) }
        } message: { Text("Only Orbit’s \(kind.title) permission will be removed. You must then enable it again in System Settings.") }
    }
    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(String(number)).font(.system(size: 10, weight: .semibold)).frame(width: 18, height: 18).background(.white.opacity(0.1), in: Circle())
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
