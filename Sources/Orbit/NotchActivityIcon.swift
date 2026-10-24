import SwiftUI
import OrbitCore

/// Motion is local to the visible compact icon, so expanded/disabled notches do no animation work.
struct NotchActivityIcon: View {
    let activity: NotchActivityKind
    let symbol: String
    let waiting: Bool
    let timerPaused: Bool
    let motionEnabled: Bool
    let eventID: String
    var musicPlaying = true
    var agentProvider: AIProvider? = nil
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let agentProvider, activity == .agent || activity == .agentFinished {
                NotchProviderGlyph(provider: agentProvider, working: activity == .agent && !waiting,
                    badge: activity == .agentFinished ? symbol : waiting ? "exclamationmark.circle.fill" : nil,
                    motionEnabled: motionEnabled).id("\(agentProvider.rawValue)-\(eventID)")
            } else if !motionEnabled {
                glyph
            } else {
                switch activity {
                case .agent:
                    if waiting { NotchEventGlyph(symbol: symbol, eventID: eventID) }
                    else { glyph.symbolEffect(.pulse.byLayer, options: .repeating.speed(0.65), isActive: true) }
                case .music:
                    if musicPlaying { NotchMusicGlyph() } else { glyph }
                case .keepAwake, .meeting, .stopwatch: glyph
                case .download: glyph.symbolEffect(.pulse, options: .repeating, isActive: true)
                case .timer:
                    if timerPaused { glyph }
                    else { NotchTimerGlyph() }
                case .copied, .notification, .agentFinished, .timerFinished:
                    NotchEventGlyph(symbol: symbol, eventID: eventID)
                }
            }
        }.frame(width: 18, height: 18).scaleEffect(size / 18)
            .frame(width: size, height: size).accessibilityHidden(true).allowsHitTesting(false)
    }
    private var glyph: some View { Image(systemName: symbol).resizable().scaledToFit().frame(width: 16, height: 16) }
}

private struct NotchProviderGlyph: View {
    let provider: AIProvider
    let working: Bool
    let badge: String?
    let motionEnabled: Bool
    @State private var breathing = false
    @State private var arrival = 0

    var body: some View {
        Group {
            if working && motionEnabled {
                AgentProviderIcon(provider: provider, size: 16)
                    .scaleEffect(breathing ? 1 : 0.88).opacity(breathing ? 1 : 0.72)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: breathing)
                    .onAppear { breathing = true }
            } else { AgentProviderIcon(provider: provider, size: 16) }
        }.overlay(alignment: .bottomTrailing) {
            if let badge {
                Image(systemName: badge).font(.system(size: 8, weight: .bold))
                    .background(.black, in: Circle()).offset(x: 3, y: 2)
                    .symbolEffect(.bounce, value: arrival)
            }
        }.onAppear { if motionEnabled { arrival += 1 } }
    }
}

private struct NotchMusicGlyph: View {
    @State private var moving = false
    private let low: [Double] = [0.3, 0.7, 0.4, 0.85, 0.35]
    private let high: [Double] = [0.8, 0.35, 1, 0.45, 0.75]
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<5) { index in
                Capsule().frame(width: 2, height: 14)
                    .scaleEffect(y: moving ? high[index] : low[index])
                    .animation(.easeInOut(duration: 0.45 + Double(index) * 0.12)
                        .repeatForever(autoreverses: true).delay(Double(index) * 0.08), value: moving)
            }
        }.onAppear { moving = true }
    }
}

private struct NotchTimerGlyph: View {
    @State private var ticking = false
    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 1.25).frame(width: 12.5, height: 12.5)
            Capsule().frame(width: 3.5, height: 1.5).offset(y: -8)
            Capsule().frame(width: 1.25, height: 4.5).offset(y: -2.25)
                .rotationEffect(.degrees(ticking ? 360 : 0))
                .animation(.linear(duration: 60).repeatForever(autoreverses: false), value: ticking)
            Circle().frame(width: 2, height: 2)
        }.onAppear { ticking = true }
    }
}

private struct NotchEventGlyph: View {
    let symbol: String
    let eventID: String
    @State private var arrival = 0
    var body: some View {
        Image(systemName: symbol).resizable().scaledToFit().frame(width: 16, height: 16)
            .symbolEffect(.bounce.byLayer, options: .speed(0.9), value: arrival)
            .onAppear { arrival += 1 }
            .onChange(of: eventID) { _, _ in arrival += 1 }
    }
}

/// A fixed-width meter keeps music's compact wing independent of track names.
struct NotchCompactMusicBars: View {
    let playing: Bool
    let height: Double
    @State private var moving = false
    private let levels: [Double] = [0.4, 0.75, 0.5, 1, 0.6, 0.85, 0.35]
    var body: some View {
        HStack(spacing: 1.53) {
            ForEach(0..<7) { index in
                Capsule().frame(width: 1.8, height: height)
                    .scaleEffect(y: playing ? (moving ? levels[index] : levels[6 - index] * 0.65) : 0.2)
                    .animation(playing ? .easeInOut(duration: 0.4 + Double(index) * 0.07).repeatForever(autoreverses: true) : nil, value: moving)
            }
        }.frame(width: NotchLayout.musicBarsWidth, height: height).onAppear { moving = true }
            .accessibilityHidden(true)
    }
}
