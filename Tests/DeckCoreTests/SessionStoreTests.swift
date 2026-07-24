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

        store.apply(event("sess-1", .idle, cwd: "/work/foo", at: 3))

        let inserted = store.session(sessionId: "sess-1")
        XCTAssertEqual(inserted?.status, .idle)
        XCTAssertEqual(inserted?.workingDirectory.path, "/work/foo")
        XCTAssertEqual(inserted?.lastActivity, Date(timeIntervalSince1970: 3))
    }

    func testApplyUpdatesExistingSessionInPlace() {
        var store = SessionStore()
        store.apply(event("sess-1", .thinking, at: 1))
        store.apply(event("sess-1", .idle, at: 2))

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.session(sessionId: "sess-1")?.status, .idle)
        XCTAssertEqual(store.session(sessionId: "sess-1")?.lastActivity,
                       Date(timeIntervalSince1970: 2))
    }

    func testApplyKeepsPriorCwdWhenEventHasNone() {
        var store = SessionStore()
        store.apply(event("sess-1", .thinking, cwd: "/work/foo", at: 1))
        store.apply(event("sess-1", .idle, cwd: nil, at: 2))

        XCTAssertEqual(store.session(sessionId: "sess-1")?.workingDirectory.path, "/work/foo")
    }

    func testApplyStoresAndUpdatesPid() {
        var store = SessionStore()
        store.apply(StatusEvent(sessionId: "s", status: .thinking, cwd: "/w",
                                timestamp: Date(timeIntervalSince1970: 1), pid: 111))
        XCTAssertEqual(store.session(sessionId: "s")?.pid, 111)

        store.apply(StatusEvent(sessionId: "s", status: .idle, cwd: "/w",
                                timestamp: Date(timeIntervalSince1970: 2), pid: 222))
        XCTAssertEqual(store.session(sessionId: "s")?.pid, 222)
    }

    func testRemoveDropsSessionById() {
        var store = SessionStore()
        store.apply(event("a", .thinking))
        store.apply(event("b", .thinking))

        store.remove(sessionId: "a")

        XCTAssertNil(store.session(sessionId: "a"))
        XCTAssertNotNil(store.session(sessionId: "b"))
    }

    func testSortedByStatusOrdersByTier() {
        var store = SessionStore()
        store.apply(event("end", .ended))
        store.apply(event("idle", .idle))
        store.apply(event("perm", .permission))
        store.apply(event("think", .thinking))

        // needsYou (idle, perm) share priority 0, stable by insertion; think = 1; end = 2.
        XCTAssertEqual(store.sortedByStatus.map(\.sessionId), ["idle", "perm", "think", "end"])
    }

    func testSortedByStatusIsStableWithinSameStatus() {
        var store = SessionStore()
        store.apply(event("work-a", .thinking))
        store.apply(event("perm", .permission))
        store.apply(event("work-b", .thinking))

        XCTAssertEqual(store.sortedByStatus.map(\.sessionId), ["perm", "work-a", "work-b"])
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
