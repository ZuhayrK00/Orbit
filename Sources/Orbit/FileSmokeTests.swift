import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum FileSmokeTests {
    static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-smoke-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("input image.png")
        let context = CGContext(data: nil, width: 640, height: 320, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 0.4)); context.fill(CGRect(x: 0, y: 0, width: 640, height: 320))
        let writer = CGImageDestinationCreateWithURL(original as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, nil); CGImageDestinationFinalize(writer)
        let originalData = try Data(contentsOf: original)
        let output = try await FileTools.convert([original], format: .jpeg, quality: 0.7, maxDimension: 160, directory: folder)
        let source = CGImageSourceCreateWithURL(output[0] as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        try require(image.width == 160 && image.height == 80, "Resize dimensions")
        try require(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier, "JPEG encoding")
        try require(try Data(contentsOf: original) == originalData, "Original preserved")
        let duplicate = try await FileTools.convert([original], format: .jpeg, quality: 0.7, maxDimension: nil, directory: folder)
        try require(output[0] != duplicate[0], "Collision-safe outputs")
        let png = try await FileTools.convert([original], format: .png, quality: 1, maxDimension: nil, directory: folder)
        let pngImage = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(png[0] as CFURL, nil)!, 0, nil)!
        try require(pngImage.width == 640 && pngImage.height == 320, "PNG dimensions preserved")
        let bad = folder.appendingPathComponent("not an image.txt"); try Data("text fixture".utf8).write(to: bad)
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        do { _ = try await FileTools.convert([original, bad], format: .jpeg, quality: 0.5, maxDimension: nil, directory: folder); throw FileTools.failure("Invalid image was accepted") }
        catch { try require(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == before, "Partial batch rollback") }
        let renamed = try await FileTools.renamedCopy([original, bad], prefix: "my-file", directory: folder)
        try require(renamed.count == 2 && renamed[0].lastPathComponent == "my-file-01.png", "Batch rename")
        try require(try Data(contentsOf: renamed[0]) == originalData, "Renamed copy content")
        let archive = try await FileTools.zip([original, bad], destination: folder.appendingPathComponent("archive.zip"))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = ["-t", archive.path]; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); try require(process.terminationStatus == 0, "ZIP integrity")
        try require(try Data(contentsOf: original) == originalData, "Original preserved after every operation")
        print("File smoke tests passed: JPEG, PNG, resize, collision handling, original preservation, batch rollback, renamed copies, ZIP integrity.")
    }
    private static func require(_ value: Bool, _ message: String) throws { if !value { throw FileTools.failure("File test failed: " + message) } }
}
