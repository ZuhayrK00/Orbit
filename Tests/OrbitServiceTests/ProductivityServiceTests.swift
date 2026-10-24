import XCTest
import AppKit
import Vision
@testable import Orbit
import OrbitCore

final class ProductivityServiceTests: XCTestCase {
    private func folder() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-feature-test-" + UUID().uuidString); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
    func testClipboardImageSurvivesSessionOnlySaveButTextIsNotPersisted() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let io = ItemLibraryIO(folder: directory)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let result = try await io.image(data), item = try XCTUnwrap(result)
        try await io.save([item, StoredItem(kind: .text, text: "private fixture")], persist: false, revision: 1)
        let loaded = try await io.load(); XCTAssertTrue(loaded.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.asset!).path))
        try await io.save([], persist: false, revision: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.asset!).path))
    }
    func testStaleWritesCannotReplaceNewPinnedHistory() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let io = ItemLibraryIO(folder: directory); var item = StoredItem(kind: .text, text: "keep"); item.pinned = true
        try await io.save([item], persist: true, revision: 2); try await io.save([], persist: true, revision: 1)
        let loaded = try await io.load(); XCTAssertEqual(loaded, [item])
    }
    func testUnreadableLibraryIsPreservedInsteadOfOverwritten() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = directory.appendingPathComponent("items.json"), original = Data("incomplete saved history".utf8)
        try original.write(to: manifest)
        let io = ItemLibraryIO(folder: directory)
        do { _ = try await io.load(); XCTFail("Expected a read failure") } catch {}
        do { try await io.save([], persist: true, revision: 1); XCTFail("Must preserve the unreadable file") } catch {}
        XCTAssertEqual(try Data(contentsOf: manifest), original)
    }
    func testSafariPackageCompletesOnlyAfterItsPayloadMovesAndSettles() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let package = directory.appendingPathComponent("fixture.zip.download", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let payload = package.appendingPathComponent("fixture.zip"), final = directory.appendingPathComponent("fixture.zip")
        try Data(repeating: 1, count: 1000).write(to: payload)
        try Data("metadata".utf8).write(to: package.appendingPathComponent("Info.plist"))
        let scanner = DownloadScanner(); var tracker = DownloadTracker(); let now = Date()
        let first = try await scanner.scan(directory)
        XCTAssertEqual(first.first?.bytes, 1000)
        XCTAssertNotNil(first.first?.identifier)
        tracker.ingest(first, now: now)
        try FileManager.default.moveItem(at: payload, to: final)
        try FileManager.default.removeItem(at: package)
        tracker.ingest(try await scanner.scan(directory), now: now.addingTimeInterval(1))
        XCTAssertEqual(tracker.activities.first?.state, .downloading)
        tracker.ingest(try await scanner.scan(directory), now: now.addingTimeInterval(2))
        XCTAssertEqual(tracker.activities.first?.state, .complete)
        XCTAssertEqual(tracker.activities.first.map { URL(fileURLWithPath: $0.target).resolvingSymlinksInPath() }, final.resolvingSymlinksInPath())
    }
    @MainActor func testLegacyNoteMigratesWithoutChangingTheOriginalAndPersistsMultipleNotes() throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("scratchpad.txt"); try Data("old note".utf8).write(to: legacy)
        let notes = Scratchpad(url: legacy); XCTAssertEqual(notes.text, "old note")
        notes.add(); notes.text = "- [ ] a new task"; notes.flush(); notes.toggleChecklist(0); notes.flush()
        let reopened = Scratchpad(url: legacy); XCTAssertEqual(reopened.notes.count, 2); XCTAssertEqual(reopened.notes[1].text, "- [x] a new task")
        XCTAssertEqual(try String(contentsOf: legacy, encoding: .utf8), "old note")
    }
    @MainActor func testClaudeControlConversationUsesNoPromptAndParsesLimits() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("claude-fixture")
        let program = #"""
        #!/bin/sh
        IFS= read -r init
        case "$init" in *'"control_request"'*'"orbit.initialize"'*|*'"orbit.initialize"'*'"control_request"'*) ;; *) exit 5;; esac
        echo '{"type":"control_response","response":{"request_id":"orbit.initialize","subtype":"success","response":{}}}'
        IFS= read -r usage
        case "$usage" in *get_usage*) ;; *) exit 6;; esac
        echo '{"type":"control_response","response":{"request_id":"orbit.usage","subtype":"success","response":{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":25,"resets_at":"2099-01-01T00:00:00Z"}}}}}'
        while IFS= read -r line; do exit 7; done
        """#
        try Data(program.utf8).write(to: script); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let reader = ClaudeUsageReader(); let windows = try await reader.read(executable: script, environment: [:])
        XCTAssertEqual(windows.first?.usedPercent, 25)
    }
    @MainActor func testClaudeCancellationEndsTheControlProcess() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("slow-fixture")
        try Data("#!/bin/sh\nwhile IFS= read -r line; do :; done\n".utf8).write(to: script); try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let reader = ClaudeUsageReader(); let task = Task { try await reader.read(executable: script, environment: [:]) }
        try await Task.sleep(nanoseconds: 50_000_000); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }
}

extension ProductivityServiceTests {
    @MainActor func testLocalOCRRecognisesRenderedFixtureWithoutScreenCapture() async throws {
        let directory = try folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1100, pixelsHigh: 160, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1100, height: 160).fill()
        ("Orbit reads text locally" as NSString).draw(at: NSPoint(x: 35, y: 65), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let url = directory.appendingPathComponent("text.png"); try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        // Match the app's background OCR path so Vision can use main-thread
        // services during initialization without blocking the test runner.
        let result = try await Task.detached(priority: .userInitiated) { try ScreenTextService.recognize(at: url) }.value
        XCTAssertTrue(result.contains("Orbit reads text locally"), result)
    }
}
