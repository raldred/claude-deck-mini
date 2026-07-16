import XCTest
@testable import DeckCore

final class SessionOrderingTests: XCTestCase {
    private func session(_ id: String, _ status: SessionStatus, at t: TimeInterval) -> Session {
        Session(sessionId: id, workingDirectory: URL(fileURLWithPath: "/w"),
                status: status, lastActivity: Date(timeIntervalSince1970: t))
    }

    func testStatusPriorityOrdersNeedsYouThenWorkingThenIdle() {
        let ordered = [session("i", .idle, at: 100),
                       session("w", .working, at: 100),
                       session("n", .waiting, at: 100)]
            .sorted(by: SessionOrdering.precedes).map(\.status)
        XCTAssertEqual(ordered, [.waiting, .working, .idle])
    }

    func testNeedsYouLongestWaitFirst() {
        let recent = session("recent", .waiting, at: 300)
        let oldest = session("oldest", .waiting, at: 100)
        let ordered = [recent, oldest].sorted(by: SessionOrdering.precedes)
        XCTAssertEqual(ordered.first?.sessionId, "oldest")
    }

    func testWorkingMostRecentFirst() {
        let older = session("older", .working, at: 100)
        let newer = session("newer", .working, at: 300)
        let ordered = [older, newer].sorted(by: SessionOrdering.precedes)
        XCTAssertEqual(ordered.first?.sessionId, "newer")
    }
}
