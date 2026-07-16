import XCTest
@testable import DeckCore

final class DeckPreferencesTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-prefs-\(UUID().uuidString).json")
    }

    func testDefaults() {
        let prefs = DeckPreferences()
        XCTAssertEqual(prefs.brightness, 60)
        XCTAssertTrue(prefs.pagingEnabled)
        XCTAssertEqual(prefs.hiddenProjects, [])
    }

    func testSaveThenLoadRoundtrips() throws {
        let url = tempFile()
        var prefs = DeckPreferences()
        prefs.brightness = 25
        prefs.pagingEnabled = false
        prefs.hiddenProjects = ["residently", "notes"]

        try prefs.save(to: url)
        let loaded = DeckPreferences.load(from: url)

        XCTAssertEqual(loaded, prefs)
    }

    func testLoadMissingFileReturnsDefaults() {
        let loaded = DeckPreferences.load(from: tempFile())
        XCTAssertEqual(loaded, DeckPreferences())
    }

    func testLoadCorruptFileReturnsDefaults() throws {
        let url = tempFile()
        try Data("not json".utf8).write(to: url)
        XCTAssertEqual(DeckPreferences.load(from: url), DeckPreferences())
    }
}
