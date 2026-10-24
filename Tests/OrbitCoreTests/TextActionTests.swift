import XCTest
@testable import OrbitCore

final class TextActionTests: XCTestCase {
    func testTextTransformsPreserveUnicodeAndNormalizeWindowsLines() throws {
        XCTAssertEqual(try TextTransform.uppercase.apply(to: "café Straße 🚀"), "CAFÉ STRASSE 🚀")
        XCTAssertEqual(try TextTransform.trim.apply(to: "  first  \r\n second \r\n"), "first\nsecond")
        XCTAssertEqual(try TextTransform.singleLine.apply(to: "one\n\t two   three"), "one two three")
        XCTAssertEqual(try TextTransform.uniqueLines.apply(to: "one\r\ntwo\r\none"), "one\ntwo")
        XCTAssertEqual(TextActions.wordCount(" one\n two\tthree "), 3)
    }
    func testCleanLinkPreservesQueryBytesAndFragment() throws {
        let source = "https://example.com/a?utm_source=mail&q=a%20b&q=a+b&key=%2Fsecret%2B&fbclid=123#section"
        XCTAssertEqual(try TextActions.cleanLink(source), "https://example.com/a?q=a%20b&q=a+b&key=%2Fsecret%2B#section")
        XCTAssertEqual(try TextActions.cleanLink("https://example.com/?UTM_medium=email"), "https://example.com/")
        XCTAssertEqual(try TextActions.cleanLink("https://example.com/?ref=important&token=keep"), "https://example.com/?ref=important&token=keep")
        XCTAssertThrowsError(try TextActions.cleanLink("https://example.com/?utm_source=mail&X-Amz-Signature=signed"))
        XCTAssertThrowsError(try TextActions.cleanLink("javascript:alert(1)"))
        XCTAssertNil(TextActions.webURL("https://user:secret@example.com/"))
        XCTAssertNil(TextActions.webURL("https://example.com/ and some other text"))
    }
    func testURLCodingAndSearchDontInterpretSelectedTextAsURLSyntax() throws {
        let input = "one & two/🚀?q=three#four"
        let encoded = try TextTransform.encodeURL.apply(to: input)
        XCTAssertFalse(encoded.contains("&")); XCTAssertEqual(try TextTransform.decodeURL.apply(to: encoded), input)
        XCTAssertThrowsError(try TextTransform.decodeURL.apply(to: "%ZZ"))
        let search = try XCTUnwrap(TextActions.searchURL(input))
        let parts = try XCTUnwrap(URLComponents(url: search, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "duckduckgo.com")
        XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "q", value: input)])
        XCTAssertNil(TextActions.searchURL(String(repeating: "x", count: 4001)))
    }
    func testJSONErrorsAndSizeLimitAreVisibleWithoutReturningEmptyOutput() throws {
        XCTAssertThrowsError(try TextTransform.formatJSON.apply(to: "{broken}"))
        let formatted = try TextTransform.formatJSON.apply(to: "{\"b\":2,\"a\":1}")
        let decoded = try JSONSerialization.jsonObject(with: Data(formatted.utf8)) as? [String: Int]
        XCTAssertEqual(decoded, ["a": 1, "b": 2])
        XCTAssertTrue(formatted.contains("\n"))
        XCTAssertThrowsError(try TextTransform.uppercase.apply(to: String(repeating: "é", count: 70_000)))
    }
    func testScratchpadRoundTripAndOversizeNeverOverwritesSavedNote() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("note.txt")
        XCTAssertEqual(try ScratchpadDocument.load(from: url), "")
        let note = "A thought.\nSecond line 🪐"
        try ScratchpadDocument.save(note, to: url)
        XCTAssertEqual(try ScratchpadDocument.load(from: url), note)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertThrowsError(try ScratchpadDocument.save(String(repeating: "x", count: ScratchpadDocument.maximumBytes + 1), to: url))
        XCTAssertEqual(try ScratchpadDocument.load(from: url), note)
        try Data([0xFF, 0xFE]).write(to: url)
        XCTAssertThrowsError(try ScratchpadDocument.load(from: url))
        XCTAssertEqual(try Data(contentsOf: url), Data([0xFF, 0xFE]))
    }
}
