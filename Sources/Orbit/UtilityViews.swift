import SwiftUI
import AppKit
import OrbitCore
import UniformTypeIdentifiers

struct FileToolsView: View {
    @Environment(\.orbitSurface) private var surface
    @Environment(\.notchToolBudget) private var budget
    @ObservedObject var store: OrbitStore
    var compact: Bool
    @State private var format: ImageFormat = .jpeg
    @State private var quality = 0.78
    @State private var resize = false
    @State private var dimension = 1920.0
    @State private var rename = ""
    @State private var result: String?
    @State private var filePage = 0
    @State private var dropTargeted = false
    private var splitTools: Bool { surface == .notch && budget < 600 && !store.selectedFiles.isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact { SectionTitle(title: "Files, taken care of.", subtitle: "Compress, convert and organise. Your originals stay untouched.") }
            OrbitCard {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.on.square").font(.system(size: compact ? 18 : 25, weight: .regular)).foregroundStyle(OrbitDesign.accent(store.configuration.accent))
                    Text(store.selectedFiles.isEmpty ? "Drop files here" : "\(store.selectedFiles.count) file\(store.selectedFiles.count == 1 ? "" : "s") ready").font(.system(size: compact ? 12 : 16, weight: .medium))
                    if store.selectedFiles.isEmpty { Text(surface == .wheel ? "Stays open while you select files in Finder" : "Images or documents · originals stay intact").font(.system(size: 12)).foregroundStyle(OrbitDesign.secondary) }
                    else {
                        Text(store.selectedFiles.prefix(3).map(\.lastPathComponent).joined(separator: " · ") + (store.selectedFiles.count > 3 ? " + more" : "")).font(.system(size: 11)).foregroundStyle(OrbitDesign.secondary).lineLimit(2)
                    }
                    HStack {
                        Button("Choose files") { store.chooseFiles() }.buttonStyle(OrbitButtonStyle(prominent: true, color: OrbitDesign.accent(store.configuration.accent)))
                        Button("From Finder") { store.importFinderSelection() }.buttonStyle(OrbitButtonStyle())
                        if !store.selectedFiles.isEmpty { Button { store.selectedFiles = []; result = nil } label: { Image(systemName: "xmark") }.buttonStyle(OrbitButtonStyle()).help("Clear selected files") }
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, compact ? 2 : 14)
            }.overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(dropTargeted ? OrbitDesign.accent(store.configuration.accent) : .clear, lineWidth: 1.5))
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted, perform: store.acceptDroppedFiles)
            if splitTools { OrbitSegmentedPicker(selection: $filePage, options: [("Images", 0), ("ZIP & copies", 1)]) }
            if !splitTools || filePage == 0 { OrbitCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(OrbitDesign.accent(store.configuration.accent)); Text("Image studio").font(.system(size: 14, weight: .semibold)); Spacer(); OrbitMenuPicker(title: "Format", selection: $format, options: ImageFormat.allCases.map { ($0.rawValue, $0) }).frame(width: 105) }
                    if format == .jpeg || format == .heic { HStack { Text("Quality").font(.system(size: 12)); Slider(value: $quality, in: 0.1...1); Text("\(Int(quality * 100))%").font(.system(size: 11, design: .monospaced)).frame(width: 34) } }
                    Toggle("Resize longest edge", isOn: $resize).font(.system(size: 12))
                    if resize { HStack { Slider(value: $dimension, in: 320...4096, step: 64); Text("\(Int(dimension)) px").font(.system(size: 11, design: .monospaced)).frame(width: 68) } }
                    HStack {
                        Button("Convert images") { convert(compress: false) }.buttonStyle(OrbitButtonStyle(prominent: true, color: OrbitDesign.accent(store.configuration.accent)))
                        Button("Compress as JPEG") { convert(compress: true) }.buttonStyle(OrbitButtonStyle())
                    }.disabled(store.selectedFiles.isEmpty || store.isProcessing)
                    Text("Creates new files. JPEG uses a white background for transparency. Metadata is removed; animated and multi-page images stay untouched. Compression savings depend on the source.").font(.system(size: 10)).foregroundStyle(OrbitDesign.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } }
            if (!compact || !store.selectedFiles.isEmpty) && (!splitTools || filePage == 1) {
                OrbitCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack { Image(systemName: "doc.zipper").foregroundStyle(OrbitDesign.accent(store.configuration.accent)); Text("File essentials").font(.system(size: 14, weight: .semibold)); Spacer(); Button("Create ZIP") { zip() }.buttonStyle(OrbitButtonStyle()) }
                        HStack { TextField("Name for renamed copies", text: $rename).textFieldStyle(OrbitTextFieldStyle()); Button("Make copies") { renamedCopy() }.buttonStyle(OrbitButtonStyle()).disabled(rename.isEmpty) }
                        if !compact { Text("Batch names use your-prefix-01, 02… Originals are never renamed or overwritten.").font(.system(size: 11)).foregroundStyle(OrbitDesign.secondary) }
                    }.disabled(store.selectedFiles.isEmpty || store.isProcessing)
                }
            }
            if store.isProcessing { HStack { ProgressView().controlSize(.small); Text("Working locally…").font(.system(size: 12)) } }
            if let result { Label(result, systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(OrbitDesign.accent(.mint)).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func directory() -> URL? {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Save here"; panel.message = "Choose a folder for the new files. Originals stay untouched."
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func convert(compress: Bool) {
        guard let folder = directory() else { return }
        let files = store.selectedFiles, chosenFormat = compress ? ImageFormat.jpeg : format
        let chosenQuality = compress ? min(quality, 0.78) : quality, maxDimension = resize ? Int(dimension) : nil
        store.isProcessing = true; result = nil
        Task {
            defer { store.isProcessing = false }
            do {
                let outputs = try await FileTools.convert(files, format: chosenFormat, quality: chosenQuality, maxDimension: maxDimension, directory: folder)
                result = "Saved \(outputs.count) new \(chosenFormat.rawValue) image\(outputs.count == 1 ? "" : "s")."
                store.message(result!); NSWorkspace.shared.activateFileViewerSelecting(outputs)
            } catch { store.error = error.localizedDescription }
        }
    }
    private func zip() {
        guard let folder = directory() else { return }; let files = store.selectedFiles
        let destination = FileTools.uniqueURL(directory: folder, name: "Orbit Archive", ext: "zip")
        store.isProcessing = true; result = nil
        Task { defer { store.isProcessing = false }; do { let output = try await FileTools.zip(files, destination: destination); result = "ZIP saved. Original files preserved."; NSWorkspace.shared.activateFileViewerSelecting([output]) } catch { store.error = error.localizedDescription } }
    }
    private func renamedCopy() {
        guard let folder = directory() else { return }; let files = store.selectedFiles, name = rename
        store.isProcessing = true; result = nil
        Task { defer { store.isProcessing = false }; do { let outputs = try await FileTools.renamedCopy(files, prefix: name, directory: folder); result = "\(outputs.count) renamed copies saved."; NSWorkspace.shared.activateFileViewerSelecting(outputs) } catch { store.error = error.localizedDescription } }
    }
}

struct TimerView: View {
    @ObservedObject var store: OrbitStore
    var compact: Bool
    @State private var minutes = 25
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact { SectionTitle(title: "A little time to focus.", subtitle: "Set a timer, get into your flow. Orbit keeps an eye on the clock.") }
            if compact {
                VStack(spacing: 10) {
                    HStack(spacing: 20) {
                        ZStack {
                            Circle().stroke(.white.opacity(0.06), lineWidth: 3)
                            Circle().trim(from: 0, to: store.timerState.isActive ? max(0, min(1, store.timerState.remaining(at: store.now) / max(1, store.timerState.duration))) : 1)
                                .stroke(.orange.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                            VStack(spacing: 4) {
                                Text(store.timerState.isActive ? OrbitTimer.label(store.timerState.remaining(at: store.now)) : OrbitTimer.label(Double(minutes * 60)))
                                    .font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit().tracking(-0.6).minimumScaleFactor(0.65).lineLimit(1)
                                Text(store.timerFinished ? "FINISHED" : store.timerState.pausedRemaining != nil ? "PAUSED" : store.timerState.isActive ? "REMAINING" : "MINUTES")
                                    .font(.system(size: 8, weight: .medium)).tracking(1.2).foregroundStyle(.secondary)
                            }.padding(8)
                        }.frame(width: 114, height: 114)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("Countdown").font(.system(size: 12, weight: .semibold)); Spacer(); Image(systemName: "timer").foregroundStyle(.orange).font(.system(size: 13)) }
                            Text(store.timerState.isActive ? "Your timer stays with you in the notch." : "Set a duration or pick a preset.").font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if !store.timerState.isActive {
                                TimerDurationControl(minutes: $minutes)
                            } else { Text(store.timerState.name).font(.system(size: 10)).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                    TimerPresetButtons(presets: store.configuration.effectiveTimerPresets, minutes: $minutes, disabled: store.timerState.isActive)
                    HStack(spacing: 8) {
                        if store.timerState.isActive {
                            Button { store.toggleTimer() } label: { Label(store.timerState.end == nil ? "Resume" : "Pause", systemImage: store.timerState.end == nil ? "play.fill" : "pause.fill").frame(maxWidth: .infinity) }.buttonStyle(OrbitButtonStyle(prominent: true, color: .orange.opacity(0.85)))
                            Button("Cancel") { store.cancelTimer() }.buttonStyle(OrbitButtonStyle())
                        } else {
                            if store.timerFinished { Button("Dismiss") { store.timerFinished = false }.buttonStyle(OrbitButtonStyle()) }
                            Button { store.startTimer(minutes: Double(minutes)) } label: { Label("Start timer", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(OrbitButtonStyle(prominent: true, color: .orange.opacity(0.85)))
                        }
                    }
                }
            } else { OrbitCard {
                VStack(spacing: compact ? 12 : 20) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.06), lineWidth: 7)
                        Circle().trim(from: 0, to: store.timerState.isActive ? max(0, min(1, store.timerState.remaining(at: store.now) / max(1, store.timerState.duration))) : 1)
                            .stroke(OrbitDesign.accent(store.configuration.accent), style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack(spacing: 6) { Text(store.timerState.isActive ? OrbitTimer.label(store.timerState.remaining(at: store.now)) : OrbitTimer.label(Double(minutes * 60))).font(.system(size: compact ? 28 : 49, weight: .light, design: .rounded)).monospacedDigit(); Text(store.timerState.pausedRemaining != nil ? "Paused" : store.timerFinished ? "Time’s up" : store.timerState.isActive ? "Counting down" : "Ready").font(.system(size: 10, weight: .medium)).foregroundStyle(OrbitDesign.secondary) }
                    }.frame(width: compact ? 110 : 225, height: compact ? 110 : 225)
                    TimerPresetButtons(presets: store.configuration.effectiveTimerPresets, minutes: $minutes, disabled: store.timerState.isActive)
                    HStack { if !store.timerState.isActive { TimerDurationControl(minutes: $minutes) }; Spacer(); if store.timerState.isActive { Button(store.timerState.end == nil ? "Resume" : "Pause") { store.toggleTimer() }.buttonStyle(OrbitButtonStyle(prominent: true)); Button("Cancel") { store.cancelTimer() }.buttonStyle(OrbitButtonStyle()) } else { Button("Start timer") { store.startTimer(minutes: Double(minutes)) }.buttonStyle(OrbitButtonStyle(prominent: true, color: OrbitDesign.accent(store.configuration.accent))) } }.frame(maxWidth: 340)
                }.frame(maxWidth: .infinity).padding(.vertical, compact ? 0 : 16)
            }
            }
            if !compact { Text("Orbit rings and sends a notification when the timer ends while the app is running. Notification delivery follows your macOS settings.").font(.system(size: 12)).foregroundStyle(OrbitDesign.secondary) }
        }
    }
}

struct NowPlayingView: View {
    @ObservedObject var store: OrbitStore
    @ObservedObject var media: MediaService
    var compact: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.configuration.mediaEnabled {
                OrbitCard {
                    VStack(alignment: .leading, spacing: 12) {
                        EmptyState(symbol: "music.note", title: "Connect a player", detail: "Show and control Music or Spotify. macOS asks for Automation access when you connect.")
                        Button("Enable music controls") { store.configuration.mediaEnabled = true; media.refresh() }.buttonStyle(OrbitButtonStyle(prominent: true, color: .pink.opacity(0.75)))
                    }
                }
            } else {
                OrbitCard {
                    VStack(spacing: 16) {
                        HStack(spacing: 13) {
                            MediaCover(media: media, size: compact ? 84 : 110)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(media.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                Text(media.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(spacing: 6) {
                            ProgressView(value: min(media.position, max(1, media.duration)), total: max(1, media.duration)).tint(.white.opacity(0.65))
                            HStack { Text(OrbitTimer.label(media.position)); Spacer(); Text(OrbitTimer.label(media.duration)) }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 18) {
                            transport("backward.end.fill", "previous track", "Previous track")
                            transport(media.isPlaying ? "pause.fill" : "play.fill", "playpause", media.isPlaying ? "Pause music" : "Play music", prominent: true)
                            transport("forward.end.fill", "next track", "Next track")
                        }.disabled(media.provider == nil)
                    }
                }
                if media.provider != nil {
                    HStack(spacing: 9) {
                        Image(systemName: "speaker.wave.1").font(.system(size: 10)).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { media.appVolume }, set: { media.setAppVolume($0) }), in: 0...100).accessibilityLabel("Player volume")
                        Text("\(Int(media.appVolume))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 32)
                    }.padding(.horizontal, 4)
                }
                if let error = media.connectionError { Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
    private func transport(_ symbol: String, _ command: String, _ title: String, prominent: Bool = false) -> some View {
        Button { media.command(command) } label: {
            Image(systemName: symbol).font(.system(size: prominent ? 18 : 13, weight: .medium))
                .frame(width: prominent ? 48 : 38, height: prominent ? 48 : 38).orbitGlass(in: Circle(), interactive: true).contentShape(Circle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}

struct MediaCover: View {
    @ObservedObject var media: MediaService
    var size: CGFloat
    var body: some View {
        Group {
            if let artwork = media.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
            else { RoundedRectangle(cornerRadius: size * 0.17).fill(.white.opacity(0.07)).overlay { Image(systemName: "music.note").font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(.secondary) } }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.17))
            .overlay(RoundedRectangle(cornerRadius: size * 0.17).strokeBorder(.white.opacity(0.12), lineWidth: 0.5)).accessibilityHidden(true)
    }
}
