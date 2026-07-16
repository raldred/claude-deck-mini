import XCTest
@testable import DeckCore

final class DeckPathsTests: XCTestCase {
    func testStatusDirIsUnderRoot() {
        XCTAssertEqual(DeckPaths.statusDir.deletingLastPathComponent().path, DeckPaths.root.path)
        XCTAssertEqual(DeckPaths.statusDir.lastPathComponent, "status")
    }
}
