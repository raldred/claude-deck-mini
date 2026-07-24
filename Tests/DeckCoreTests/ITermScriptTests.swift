import XCTest
@testable import DeckCore

final class ITermScriptTests: XCTestCase {
    func testEmbedsTheTtyAndActivates() {
        let script = ITermScript.focus(tty: "/dev/ttys003")
        XCTAssertTrue(script.contains("/dev/ttys003"))
        XCTAssertTrue(script.contains("tell application \"iTerm2\""))
        XCTAssertTrue(script.contains("activate"))
    }

    func testActivatesBeforeSelectingSoFirstPressLands() {
        // Activating iTerm2 re-fronts its previously-key window, which would
        // land *after* our select and show the wrong window on the first press.
        // Activate first, then select, so the selection wins.
        let script = ITermScript.focus(tty: "/dev/ttys003")
        let activate = script.range(of: "activate")
        let selectWindow = script.range(of: "select theWindow")
        XCTAssertNotNil(activate)
        XCTAssertNotNil(selectWindow)
        XCTAssertTrue(activate!.lowerBound < selectWindow!.lowerBound,
                      "activate must precede select theWindow")
    }
}
