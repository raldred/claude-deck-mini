import XCTest
@testable import DeckCore

final class RelativeTimeTests: XCTestCase {
    private func label(_ ageSeconds: TimeInterval) -> String {
        let now = Date()
        return RelativeTime.since(now.addingTimeInterval(-ageSeconds), now: now)
    }

    func testJustNowUnderAMinute() {
        XCTAssertEqual(label(0), "just now")
        XCTAssertEqual(label(59), "just now")
    }

    func testMinutes() {
        XCTAssertEqual(label(60), "1m ago")
        XCTAssertEqual(label(5 * 60), "5m ago")
        XCTAssertEqual(label(59 * 60), "59m ago")
    }

    func testHours() {
        XCTAssertEqual(label(3600), "1h ago")
        XCTAssertEqual(label(2 * 3600), "2h ago")
        XCTAssertEqual(label(41 * 3600), "41h ago")
    }
}
