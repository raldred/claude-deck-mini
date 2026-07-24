import XCTest
@testable import DeckCore

final class DeckLayoutTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)
    // A resolver whose git runner never matches → every label is the cwd basename.
    private var resolver: NameResolver {
        struct NoGit: GitRunner { func run(_ a: [String], cwd: URL) -> String? { nil } }
        return NameResolver(gitRunner: NoGit())
    }

    private func sessions(_ n: Int, status: SessionStatus = .working) -> [Session] {
        (0..<n).map { i in
            Session(sessionId: "s\(i)",
                    workingDirectory: URL(fileURLWithPath: "/Code/proj\(i)"),
                    status: status,
                    lastActivity: Date(timeIntervalSince1970: TimeInterval(1000 + i)))
        }
    }

    private func kinds(_ keys: [DeckKey]) -> [String] {
        keys.map {
            switch $0.kind {
            case .agent:  return "agent"
            case .more:   return "more"
            case .blank:  return "blank"
            case .banner: return "banner"
            }
        }
    }

    func testEmptyShowsBannerAcrossAllKeys() {
        let keys = DeckLayout.keys(for: [], page: 0, now: now, resolver: resolver)
        XCTAssertEqual(keys.count, 6)
        XCTAssertEqual(kinds(keys), Array(repeating: "banner", count: 6))
        for (i, key) in keys.enumerated() {
            XCTAssertEqual(key.index, i)
            guard case let .banner(text) = key.kind else {
                return XCTFail("expected banner at \(i)")
            }
            XCTAssertEqual(text, "No active sessions")
        }
    }

    func testThreeSessionsFillFirstThreeThenBlank() {
        let keys = DeckLayout.keys(for: sessions(3), page: 0, now: now, resolver: resolver)
        XCTAssertEqual(kinds(keys), ["agent", "agent", "agent", "blank", "blank", "blank"])
    }

    func testExactlySixSessionsAllAgentsNoMoreKey() {
        let keys = DeckLayout.keys(for: sessions(6), page: 0, now: now, resolver: resolver)
        XCTAssertEqual(kinds(keys), Array(repeating: "agent", count: 6))
    }

    func testSevenSessionsUseMoreKeyOnPageZero() {
        let keys = DeckLayout.keys(for: sessions(7), page: 0, now: now, resolver: resolver)
        XCTAssertEqual(kinds(keys), ["agent", "agent", "agent", "agent", "agent", "more"])
        if case let .more(remaining) = keys[5].kind {
            XCTAssertEqual(remaining, 2)   // 7 total − 5 shown
        } else { XCTFail("expected more key") }
    }

    func testSecondPageShowsRemainderAndWraps() {
        // 7 sessions, 5 per page. Page 1 shows the last 2 + a more key back to start.
        let keys = DeckLayout.keys(for: sessions(7), page: 1, now: now, resolver: resolver)
        XCTAssertEqual(kinds(keys), ["agent", "agent", "blank", "blank", "blank", "more"])
        if case let .more(remaining) = keys[5].kind {
            XCTAssertEqual(remaining, 5)   // 7 total − 2 shown on this page
        } else { XCTFail("expected more key") }
    }

    func testPageIndexWrapsAround() {
        // 7 sessions → 2 pages. Page 2 == page 0.
        let p0 = DeckLayout.keys(for: sessions(7), page: 0, now: now, resolver: resolver)
        let p2 = DeckLayout.keys(for: sessions(7), page: 2, now: now, resolver: resolver)
        XCTAssertEqual(kinds(p0), kinds(p2))
    }

    func testStatusDoesNotChangeSlot() {
        // A session going to .waiting must keep its slot — order is fixed by
        // first-seen, so the last session stays last even when it needs you.
        var s = sessions(6, status: .working)
        s[5].status = .waiting
        s[5].lastActivity = Date(timeIntervalSince1970: 1)
        let keys = DeckLayout.keys(for: s, page: 0, now: now, resolver: resolver)
        // First key is still s0 (working); the waiting session stays in slot 5.
        if case let .agent(_, status, _, _, _) = keys[0].kind {
            XCTAssertEqual(status, .working)
        } else { XCTFail("expected agent") }
        if case let .agent(_, status, _, _, _) = keys[5].kind {
            XCTAssertEqual(status, .waiting)
        } else { XCTFail("expected agent") }
    }

    func testAgentKeyCarriesLabelAndAge() {
        let keys = DeckLayout.keys(for: sessions(1), page: 0, now: now, resolver: resolver)
        guard case let .agent(label, status, age, _, _) = keys[0].kind else {
            return XCTFail("expected agent")
        }
        XCTAssertEqual(label, .plain("proj0"))
        XCTAssertEqual(status, .working)
        XCTAssertFalse(age.isEmpty)
    }

    func testWaitingSessionMarkedStuckPastThreshold() {
        var s = sessions(1, status: .waiting)
        s[0].lastActivity = now.addingTimeInterval(-200)  // 200s ago > 180 default
        let keys = DeckLayout.keys(for: s, page: 0, now: now, resolver: resolver)
        guard case let .agent(_, _, _, _, stuck) = keys[0].kind else { return XCTFail("expected agent") }
        XCTAssertTrue(stuck)
    }

    func testWaitingSessionNotStuckBeforeThreshold() {
        var s = sessions(1, status: .waiting)
        s[0].lastActivity = now.addingTimeInterval(-10)
        let keys = DeckLayout.keys(for: s, page: 0, now: now, resolver: resolver)
        guard case let .agent(_, _, _, _, stuck) = keys[0].kind else { return XCTFail("expected agent") }
        XCTAssertFalse(stuck)
    }

    func testWorkingSessionNeverStuck() {
        var s = sessions(1, status: .working)
        s[0].lastActivity = now.addingTimeInterval(-9999)
        let keys = DeckLayout.keys(for: s, page: 0, now: now, resolver: resolver)
        guard case let .agent(_, _, _, _, stuck) = keys[0].kind else { return XCTFail("expected agent") }
        XCTAssertFalse(stuck)
    }

    func testSessionsForPageMapsKeyIndexToSession() {
        let mapped = DeckLayout.sessionsForPage(sessions(3), page: 0)
        XCTAssertEqual(mapped.count, 6)
        XCTAssertEqual(mapped[0]?.sessionId, "s0")
        XCTAssertEqual(mapped[2]?.sessionId, "s2")
        XCTAssertNil(mapped[3])  // blank slot
    }

    func testSessionsForPageMoreKeyIsNil() {
        let mapped = DeckLayout.sessionsForPage(sessions(7), page: 0)
        XCTAssertEqual(mapped[0]?.sessionId, "s0")
        XCTAssertNil(mapped[5])  // the "more" key maps to no session
    }
}
