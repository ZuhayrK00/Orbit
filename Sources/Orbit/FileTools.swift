import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPEG", png = "PNG", heic = "HEIC", tiff = "TIFF"
    var id: String { rawValue }
    var type: UTType { switch self { case .jpeg: return .jpeg; case .png: return .png; case .heic: return .heic; case .tiff: return .tiff } }
    var ext: String { switch self { case .jpeg: return "jpg"; case .png: return "png"; case .heic: return "heic"; case .tiff: return "tiff" } }
}
enum FileTools {
    static func uniqueURL(directory: URL, name: String, ext: String) -> URL {
        var url = directory.appendingPathComponent(name).appendingPathExtension(ext); var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(name) \(counter)").appendingPathExtension(ext); counter += 1
        }
        return url
    }
    static func convert(_ files: [URL], format: ImageFormat, quality: Double, maxDimension: Int?, directory: URL) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            var outputs: [URL] = []
            do {
                for file in files {
                    try Task.checkCancellation()
                    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { throw failure("\(file.lastPathComponent) is not a supported image.") }
                    guard CGImageSourceGetCount(source) == 1 else { throw failure("\(file.lastPathComponent) contains multiple frames or pages. Orbit preserves it; choose a single-frame image.") }
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                    let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0, height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
                    guard width > 0, height > 0, width <= 30_000, height <= 30_000, Int64(width) * Int64(height) <= 100_000_000 else { throw failure("\(file.lastPathComponent) is too large to process safely.") }
                    let dimension = maxDimension.map { min($0, max(width, height)) } ?? max(width, height)
                    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: dimension, kCGImageSourceShouldCacheImmediately: true]
                    guard let original = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw failure("Could not read \(file.lastPathComponent).") }
                    var image = original
                    if format == .jpeg, let context = CGContext(data: nil, width: original.width, height: original.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: original.width, height: original.height)); context.draw(original, in: CGRect(x: 0, y: 0, width: original.width, height: original.height))
                        if let flattened = context.makeImage() { image = flattened }
                    }
                    let stem = file.deletingPathExtension().lastPathComponent + "-orbit"
                    let destination = uniqueURL(directory: directory, name: stem, ext: format.ext)
                    guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, 1, nil) else { throw failure("This Mac cannot write \(format.rawValue).") }
                    // Deliberately omit source metadata, including GPS and author information.
                    CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: min(1, max(0.1, quality))] as CFDictionary)
                    guard CGImageDestinationFinalize(writer) else { try? FileManager.default.removeItem(at: destination); throw failure("Could not write \(destination.lastPathComponent).") }
                    outputs.append(destination)
                }
                return outputs
            } catch {
                // Roll back only the new outputs from this operation, never source files.
                for file in outputs { try? FileManager.default.removeItem(at: file) }; throw error
            }
        }.value
    }
    static func zip(_ files: [URL], destination: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            for file in files {
                guard !file.hasDirectoryPath else { throw failure("Choose files rather than folders for ZIP creation.") }
                let target = uniqueURL(directory: staging, name: file.deletingPathExtension().lastPathComponent, ext: file.pathExtension)
                try FileManager.default.copyItem(at: file, to: target)
            }
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--norsrc", staging.path, destination.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { try? FileManager.default.removeItem(at: destination); throw failure("ZIP creation failed.") }
            return destination
        }.value
    }
    static func renamedCopy(_ files: [URL], prefix: String, directory: URL) async throws -> [URL] {
        guard !prefix.isEmpty, !prefix.contains("/"), !prefix.contains(":"), !prefix.contains("\0") else { throw failure("Use a filename without slashes or colons.") }
        return try await Task.detached(priority: .utility) {
            var outputs: [URL] = []
            do {
                for (index, file) in files.enumerated() {
                    let target = uniqueURL(directory: directory, name: files.count == 1 ? prefix : "\(prefix)-\(String(format: "%02d", index + 1))", ext: file.pathExtension)
                    try FileManager.default.copyItem(at: file, to: target); outputs.append(target)
                }
                return outputs
            } catch { for file in outputs { try? FileManager.default.removeItem(at: file) }; throw error }
        }.value
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "Orbit.Files", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
