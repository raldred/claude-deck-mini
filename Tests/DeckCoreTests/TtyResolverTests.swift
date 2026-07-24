import XCTest
@testable import DeckCore

final class TtyResolverTests: XCTestCase {
    func testAddsDevPrefixToBareTty() {
        XCTAssertEqual(TtyResolver.ttyPath(fromPS: "ttys003\n"), "/dev/ttys003")
    }

    func testKeepsExistingDevPrefix() {
        XCTAssertEqual(TtyResolver.ttyPath(fromPS: "/dev/ttys007"), "/dev/ttys007")
    }

    func testNilForNoControllingTerminal() {
        XCTAssertNil(TtyResolver.ttyPath(fromPS: "??\n"))
        XCTAssertNil(TtyResolver.ttyPath(fromPS: "?"))
    }

    func testNilForEmptyOutput() {
        XCTAssertNil(TtyResolver.ttyPath(fromPS: "   \n"))
    }
}
