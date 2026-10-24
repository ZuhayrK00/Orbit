import AppKit
import Combine
import Vision
import OrbitCore

@MainActor final class ScreenTextService: ObservableObject {
    @Published var text = ""
    @Published var message: String?
    @Published private(set) var busy = false
    private var process: Process?
    private let permissions: PermissionCenter
    init(permissions: PermissionCenter) { self.permissions = permissions }
    func capture(completion: @escaping (String) -> Void) {
        guard !busy else { return }
        guard CGPreflightScreenCaptureAccess() else {
            permissions.request(.screenCapture)
            message = permissions.isAllowed(.screenCapture) ? "Screen access is ready. Choose Capture text again." : "Enable Orbit in System Settings → Screen & System Audio Recording, then try again. The permission guide will confirm access."
            return
        }
        busy = true; message = "Drag around the text. Press Escape to cancel."
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-ocr-\(UUID().uuidString).png")
        let capture = Process(); process = capture
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); capture.arguments = ["-i", "-s", "-x", "-r", url.path]
        capture.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else { self.busy = false; self.message = "Capture cancelled"; return }
                let result = await Task.detached(priority: .userInitiated) { () -> Result<String, Error> in
                    defer { try? FileManager.default.removeItem(at: url) }
                    return Result {
                        try Self.recognize(at: url)
                    }
                }.value
                self.busy = false
                switch result {
                case .success(let text): self.text = text; self.message = text.isEmpty ? "No readable text found" : "Text recognised and copied"; if !text.isEmpty { completion(text) }
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
        do { try capture.run() } catch { busy = false; message = error.localizedDescription; process = nil }
    }
    nonisolated static func recognize(at url: URL) throws -> String {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(url: url).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    func cancel() { process?.terminate() }
}
