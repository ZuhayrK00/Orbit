import XCTest
@testable import OrbitCore

final class TimerPresetsTests: XCTestCase {
    func testExistingConfigurationKeepsDefaultsAndOtherPreferences() throws {
        var original = OrbitConfiguration()
        original.hoverDelay = 0.42
        original.notchWidth = 509
        original.slots[0].label = "My files"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "timerPresets")
        var restored = try JSONDecoder().decode(OrbitConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        restored.normalize()
        XCTAssertNil(restored.timerPresets)
        XCTAssertEqual(restored.effectiveTimerPresets.map(\.minutes), [5, 15, 25, 45])
        XCTAssertEqual(restored.hoverDelay, 0.42)
        XCTAssertEqual(restored.notchWidth, 509)
        XCTAssertEqual(restored.slots[0].label, "My files")
    }

    func testCustomOrderDurationsAndIdentitiesPersist() throws {
        var config = OrbitConfiguration()
        // Duplicate durations are independent editable presets, with stable identities.
        let presets = [45, 7, 120, 7, 1, 1440].map { TimerPreset(minutes: $0) }
        config.timerPresets = presets
        config.normalize()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ConfigurationIO.save(config, to: url)
        let restored = try ConfigurationIO.load(from: url)
        XCTAssertEqual(restored.effectiveTimerPresets, presets)
        XCTAssertEqual(restored, config)
    }

    func testImportedPresetsAreBoundedAndHaveUniqueIdentity() {
        let repeatedID = UUID()
        var values = [TimerPreset(minutes: -20, id: repeatedID), TimerPreset(minutes: 9999, id: repeatedID)]
        values += (1...10).map { TimerPreset(minutes: $0) }
        var config = OrbitConfiguration()
        config.timerPresets = values
        config.normalize()
        let repaired = config.effectiveTimerPresets
        XCTAssertEqual(repaired.count, 8)
        XCTAssertEqual(repaired.map(\.minutes), [1, 1440, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(repaired[0].id, repeatedID)
        XCTAssertEqual(Set(repaired.map(\.id)).count, repaired.count)
        XCTAssertEqual(TimerPresets.normalize(repaired), repaired)
    }

    func testEmptyPresetListRecoversDefaultsAndSinglePresetIsAllowed() {
        var config = OrbitConfiguration()
        config.timerPresets = []
        config.normalize()
        XCTAssertEqual(config.effectiveTimerPresets.map(\.minutes), [5, 15, 25, 45])
        let single = [TimerPreset(minutes: 90)]
        config.timerPresets = single
        config.normalize()
        XCTAssertEqual(config.effectiveTimerPresets, single)
    }
}
