import XCTest
@testable import DeckCore

final class SessionOrderingTests: XCTestCase {
    private func session(_ id: String, firstSeen t: TimeInterval) -> Session {
        Session(sessionId: id, workingDirectory: URL(fileURLWithPath: "/w"),
                status: .working, lastActivity: Date(timeIntervalSince1970: t),
                firstSeen: Date(timeIntervalSince1970: t))
    }

    func testOrdersByFirstSeenAscending() {
        let ordered = [session("c", firstSeen: 300),
                       session("a", firstSeen: 100),
                       session("b", firstSeen: 200)]
            .sorted(by: SessionOrdering.precedes).map(\.sessionId)
        XCTAssertEqual(ordered, ["a", "b", "c"])
    }

    func testStatusDoesNotAffectOrder() {
        let waiting = Session(sessionId: "later", workingDirectory: URL(fileURLWithPath: "/w"),
                              status: .waiting, lastActivity: Date(timeIntervalSince1970: 200),
                              firstSeen: Date(timeIntervalSince1970: 200))
        let working = Session(sessionId: "earlier", workingDirectory: URL(fileURLWithPath: "/w"),
                              status: .working, lastActivity: Date(timeIntervalSince1970: 100),
                              firstSeen: Date(timeIntervalSince1970: 100))
        let ordered = [waiting, working].sorted(by: SessionOrdering.precedes).map(\.sessionId)
        XCTAssertEqual(ordered, ["earlier", "later"])
    }

    func testTieBreaksOnSessionId() {
        let ordered = [session("b", firstSeen: 100),
                       session("a", firstSeen: 100)]
            .sorted(by: SessionOrdering.precedes).map(\.sessionId)
        XCTAssertEqual(ordered, ["a", "b"])
    }
}
