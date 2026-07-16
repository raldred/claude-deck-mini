import XCTest
@testable import DeckCore

final class SessionStoreTests: XCTestCase {
    private func event(_ id: String, _ status: SessionStatus, cwd: String? = "/w",
                       at t: TimeInterval = 1) -> StatusEvent {
        StatusEvent(sessionId: id, status: status, cwd: cwd,
                    timestamp: Date(timeIntervalSince1970: t))
    }

    func testApplyInsertsUnknownSession() {
        var store = SessionStore()

        store.apply(event("sess-1", .waiting, cwd: "/work/foo", at: 3))

        let inserted = store.session(sessionId: "sess-1")
        XCTAssertEqual(inserted?.status, .waiting)
        XCTAssertEqual(inserted?.workingDirectory.path, "/work/foo")
        XCTAssertEqual(inserted?.lastActivity, Date(timeIntervalSince1970: 3))
    }

    func testApplyUpdatesExistingSessionInPlace() {
        var store = SessionStore()
        store.apply(event("sess-1", .working, at: 1))
        store.apply(event("sess-1", .waiting, at: 2))

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.session(sessionId: "sess-1")?.status, .waiting)
        XCTAssertEqual(store.session(sessionId: "sess-1")?.lastActivity,
                       Date(timeIntervalSince1970: 2))
    }

    func testApplyKeepsPriorCwdWhenEventHasNone() {
        var store = SessionStore()
        store.apply(event("sess-1", .working, cwd: "/work/foo", at: 1))
        store.apply(event("sess-1", .waiting, cwd: nil, at: 2))

        XCTAssertEqual(store.session(sessionId: "sess-1")?.workingDirectory.path, "/work/foo")
    }

    func testRemoveDropsSessionById() {
        var store = SessionStore()
        store.apply(event("a", .working))
        store.apply(event("b", .working))

        store.remove(sessionId: "a")

        XCTAssertNil(store.session(sessionId: "a"))
        XCTAssertNotNil(store.session(sessionId: "b"))
    }

    func testSortedByStatusOrdersWaitingWorkingIdleFinished() {
        var store = SessionStore()
        store.apply(event("fin", .finished))
        store.apply(event("idle", .idle))
        store.apply(event("wait", .waiting))
        store.apply(event("work", .working))

        XCTAssertEqual(store.sortedByStatus.map(\.sessionId), ["wait", "work", "idle", "fin"])
    }

    func testSortedByStatusIsStableWithinSameStatus() {
        var store = SessionStore()
        store.apply(event("work-a", .working))
        store.apply(event("wait", .waiting))
        store.apply(event("work-b", .working))

        XCTAssertEqual(store.sortedByStatus.map(\.sessionId), ["wait", "work-a", "work-b"])
    }

    // MARK: - worktree / project grouping

    private func session(cwd: String) -> Session {
        Session(sessionId: "s", workingDirectory: URL(fileURLWithPath: cwd))
    }

    func testProjectGroupUsesLeafForPlainRepo() {
        XCTAssertEqual(session(cwd: "/Users/rob/Code/claude-deck").projectGroup, "claude-deck")
    }

    func testProjectGroupFoldsClaudeWorktreeIntoParentRepo() {
        let cwd = "/Users/rob/Code/residently/contractor/.claude/worktrees/funny-bose-1c8834"
        XCTAssertEqual(session(cwd: cwd).projectGroup, "contractor")
    }

    func testProjectGroupFoldsDotWorktreesIntoParentRepo() {
        let cwd = "/Users/rob/Code/residently/foundations/.worktrees/templates-client-account-switch"
        XCTAssertEqual(session(cwd: cwd).projectGroup, "foundations")
    }

    func testWorktreeLabelStripsTrailingHash() {
        let cwd = "/Users/rob/Code/residently/contractor/.claude/worktrees/funny-bose-1c8834"
        XCTAssertEqual(session(cwd: cwd).worktreeLabel, "funny-bose")
    }

    func testWorktreeLabelForDotWorktreesPath() {
        let cwd = "/Users/rob/Code/residently/foundations/.worktrees/templates-client-account-switch"
        XCTAssertEqual(session(cwd: cwd).worktreeLabel, "templates-client-account-switch")
    }

    func testWorktreeLabelNilForPlainRepo() {
        XCTAssertNil(session(cwd: "/Users/rob/Code/claude-deck").worktreeLabel)
    }
}
