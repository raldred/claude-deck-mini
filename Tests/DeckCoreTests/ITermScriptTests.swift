import XCTest
@testable import DeckCore

final class ITermScriptTests: XCTestCase {
    func testEmbedsTheTtyAndActivates() {
        let script = ITermScript.focus(tty: "/dev/ttys003")
        XCTAssertTrue(script.contains("/dev/ttys003"))
        XCTAssertTrue(script.contains("tell application \"iTerm2\""))
        XCTAssertTrue(script.contains("activate"))
    }
}
