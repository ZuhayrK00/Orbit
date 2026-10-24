import SwiftUI
import OrbitCore

struct OnboardingView: View {
    @ObservedObject var store: OrbitStore
    private var accent: Color { OrbitDesign.accent(store.configuration.accent) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                OrbitMark(size: 24, color: accent); Text("Orbit").font(.system(size: 17, weight: .semibold))
                Spacer()
                HStack(spacing: 6) { ForEach(0..<3) { step in Capsule().fill(step == store.onboardingStep ? accent : Color.primary.opacity(0.12)).frame(width: step == store.onboardingStep ? 24 : 6, height: 6) } }
                Spacer()
                Button("Set up later") { store.finishOnboarding() }.font(.system(size: 12)).foregroundStyle(.secondary).buttonStyle(.plain)
            }.padding(.horizontal, 44).padding(.top, 50)
            Group {
                switch store.onboardingStep {
                case 0: welcome
                case 1: surfaces
                default: permissions
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 52)
                .id(store.onboardingStep).transition(.opacity.combined(with: .offset(x: store.reduceMotion ? 0 : 16)))
            HStack {
                if store.onboardingStep > 0 { Button { changeStep(-1) } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(OrbitButtonStyle()) }
                else { Label("No account. No subscription.", systemImage: "lock.shield").font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    if store.onboardingStep == 2 { store.finishOnboarding() } else { changeStep(1) }
                } label: { HStack(spacing: 16) { Text(store.onboardingStep == 0 ? "Make it yours" : store.onboardingStep == 1 ? "Continue" : "Start using Orbit"); Image(systemName: "arrow.right") }.padding(.vertical, 3).padding(.horizontal, 4) }
                    .buttonStyle(OrbitButtonStyle(prominent: true, color: accent))
            }.padding(.horizontal, 52).padding(.bottom, 40)
        }.frame(minWidth: 840, minHeight: 660)
    }
    private var welcome: some View {
        HStack(spacing: 42) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your tools.\nWithin reach.").font(.system(size: 32, weight: .semibold)).tracking(-0.8).lineSpacing(-1)
                Text("The tools you reach for,\nright where you need them.").font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
                HStack(spacing: 16) { Label("A gesture away", systemImage: "cursorarrow.rays"); Label("Always local", systemImage: "lock") }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.top, 5)
            }.frame(maxWidth: .infinity, alignment: .leading)
            WheelView(store: store, preview: true).frame(width: 300, height: 300)
        }
    }
    private var surfaces: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionTitle(title: "Choose your way in.", subtitle: "Use one, or use them all. You can change everything later.")
            OrbitCard { VStack(spacing: 22) {
                surfaceRow("The action wheel", detail: "Open it anywhere with \(store.configuration.keyboardLabel)", symbol: "circle.hexagongrid", value: $store.configuration.keyboardEnabled)
                Divider().opacity(0.4)
                surfaceRow("The notch", detail: "Hover over the island, right up to the screen edge", symbol: "macbook", value: $store.configuration.notchEnabled)
                Divider().opacity(0.4)
                surfaceRow("The menu bar", detail: "A quiet home for your everyday tools", symbol: "menubar.rectangle", value: $store.configuration.menuBarEnabled)
            } }
            Label("Mouse buttons and Logitech gestures can be connected in Settings → Controls.", systemImage: "computermouse").font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: 630)
    }
    private var permissions: some View {
        SetupPermissionsView(store: store, permissions: store.permissions)
    }
    private func surfaceRow(_ title: String, detail: String, symbol: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(accent).frame(width: 42)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 15, weight: .semibold)); Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
            Spacer(); Toggle(title, isOn: value).labelsHidden().accessibilityLabel(title)
        }
    }
    private func changeStep(_ direction: Int) { withAnimation(store.reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.92)) { store.onboardingStep += direction } }
}
