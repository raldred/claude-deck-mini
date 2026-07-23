import XCTest
@testable import DeckCore

final class FirstSeenTrackerTests: XCTestCase {
    private func session(_ id: String, lastActivity t: TimeInterval) -> Session {
        Session(sessionId: id, workingDirectory: URL(fileURLWithPath: "/w"),
                status: .working, lastActivity: Date(timeIntervalSince1970: t))
    }

    func testNewSessionStampsFromLastActivity() {
        var tracker = FirstSeenTracker()
        let stamped = tracker.stamp([session("a", lastActivity: 100)])
        XCTAssertEqual(stamped.first?.firstSeen, Date(timeIntervalSince1970: 100))
    }

    func testFirstSeenPersistsAcrossRefreshes() {
        var tracker = FirstSeenTracker()
        _ = tracker.stamp([session("a", lastActivity: 100)])
        // Same id refreshed with newer activity keeps its original first-seen.
        let stamped = tracker.stamp([session("a", lastActivity: 500)])
        XCTAssertEqual(stamped.first?.firstSeen, Date(timeIntervalSince1970: 100))
    }

    func testDepartedSessionGetsFreshSlotOnReturn() {
        var tracker = FirstSeenTracker()
        _ = tracker.stamp([session("a", lastActivity: 100)])
        _ = tracker.stamp([])                     // "a" gone → pruned
        let stamped = tracker.stamp([session("a", lastActivity: 900)])
        XCTAssertEqual(stamped.first?.firstSeen, Date(timeIntervalSince1970: 900))
    }
}
