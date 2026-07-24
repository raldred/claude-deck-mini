import XCTest
@testable import DeckCore

final class StatusEngineTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-engine-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRefreshFoldsStatusFilesIntoStore() throws {
        let store = StatusFileStore(directory: tempDir())
        try store.write(StatusEvent(sessionId: "c1", status: .idle, cwd: "/w",
                                    timestamp: Date(timeIntervalSince1970: 9)))

        var sessions = SessionStore()
        StatusEngine.refresh(store: store, into: &sessions,
                             now: Date(timeIntervalSince1970: 9))

        XCTAssertEqual(sessions.session(sessionId: "c1")?.status, .idle)
        XCTAssertEqual(sessions.session(sessionId: "c1")?.workingDirectory.path, "/w")
    }

    func testRefreshAppliesNewestEventLast() throws {
        let store = StatusFileStore(directory: tempDir())
        // Two sessions, written out of order — refresh sorts by timestamp so the
        // final state per session is its latest event.
        try store.write(StatusEvent(sessionId: "a", status: .thinking, cwd: "/w",
                                    timestamp: Date(timeIntervalSince1970: 5)))
        try store.write(StatusEvent(sessionId: "b", status: .idle, cwd: "/w",
                                    timestamp: Date(timeIntervalSince1970: 9)))

        var sessions = SessionStore()
        StatusEngine.refresh(store: store, into: &sessions,
                             now: Date(timeIntervalSince1970: 9))

        XCTAssertEqual(sessions.session(sessionId: "a")?.status, .thinking)
        XCTAssertEqual(sessions.session(sessionId: "b")?.status, .idle)
        XCTAssertEqual(sessions.sessions.count, 2)
    }

    func testRefreshReapsFilesWhoseProcessIsDead() throws {
        let store = StatusFileStore(directory: tempDir())
        try store.write(StatusEvent(sessionId: "alive", status: .thinking, cwd: "/w",
                                    timestamp: Date(timeIntervalSince1970: 1), pid: 100))
        try store.write(StatusEvent(sessionId: "dead", status: .thinking, cwd: "/w",
                                    timestamp: Date(timeIntervalSince1970: 1), pid: 200))

        var sessions = SessionStore()
        StatusEngine.refresh(store: store, into: &sessions,
                             isAlive: { $0 == 100 })

        XCTAssertNotNil(sessions.session(sessionId: "alive"))
        XCTAssertNil(sessions.session(sessionId: "dead"))
        // The dead file is gone from disk too, so it won't reappear next poll.
        XCTAssertEqual(try store.readAll().map(\.sessionId), ["alive"])
    }

    func testRefreshKeepsFilesWithNoPid() throws {
        let store = StatusFileStore(directory: tempDir())
        try store.write(StatusEvent(sessionId: "legacy", status: .thinking, cwd: "/w",
                                    timestamp: Date(timeIntervalSince1970: 1)))

        var sessions = SessionStore()
        StatusEngine.refresh(store: store, into: &sessions, isAlive: { _ in false })

        XCTAssertNotNil(sessions.session(sessionId: "legacy"))
    }

    func testRefreshReapsWaitingSessionIdleBeyondThreshold() throws {
        let store = StatusFileStore(directory: tempDir())
        let now = Date(timeIntervalSince1970: 10_000)
        // A waiting session whose last activity is 31 min ago — abandoned.
        try store.write(StatusEvent(sessionId: "stale", status: .idle, cwd: "/w",
                                    timestamp: now.addingTimeInterval(-31 * 60), pid: 100))

        var sessions = SessionStore()
        StatusEngine.refresh(store: store, into: &sessions,
                             isAlive: { _ in true }, now: now)

        XCTAssertNil(sessions.session(sessionId: "stale"))
        XCTAssertEqual(try store.readAll().count, 0, "stale waiting file reaped from disk")
    }

    func testRefreshKeepsWaitingSessionWithinThreshold() throws {
        let store = StatusFileStore(directory: tempDir())
        let now = Date(timeIntervalSince1970: 10_000)
        try store.write(StatusEvent(sessionId: "recent", status: .idle, cwd: "/w",
                                    timestamp: now.addingTimeInterval(-29 * 60), pid: 100))

        var sessions = SessionStore()
        StatusEngine.refresh(store: store, into: &sessions,
                             isAlive: { _ in true }, now: now)

        XCTAssertNotNil(sessions.session(sessionId: "recent"))
    }

    func testRefreshNeverReapsWorkingSessionHoweverOld() throws {
        let store = StatusFileStore(directory: tempDir())
        let now = Date(timeIntervalSince1970: 10_000)
        // A long-running tool call keeps status working with an old timestamp —
        // must never be reaped on idle grounds while its process is alive.
        try store.write(StatusEvent(sessionId: "busy", status: .thinking, cwd: "/w",
                                    timestamp: now.addingTimeInterval(-6 * 3600), pid: 100))

        var sessions = SessionStore()
        StatusEngine.refresh(store: store, into: &sessions,
                             isAlive: { _ in true }, now: now)

        XCTAssertNotNil(sessions.session(sessionId: "busy"))
    }

    func testRefreshCountsSubagentsPerParentAndReapsDeadOnes() throws {
        let statusDir = tempDir()
        let subDir = tempDir()
        let store = StatusFileStore(directory: statusDir)
        let subs = SubagentFileStore(directory: subDir)
        try store.write(StatusEvent(sessionId: "parent", status: .thinking, cwd: "/w",
                                    timestamp: Date(timeIntervalSince1970: 1), pid: 100))
        // Two live sidecars for the parent, one dead one.
        try writeSidecar(subDir, "ag1", parent: "parent", pid: 100)
        try writeSidecar(subDir, "ag2", parent: "parent", pid: 100)
        try writeSidecar(subDir, "ag3", parent: "parent", pid: 999)   // dead

        var sessions = SessionStore()
        StatusEngine.refresh(store: store, into: &sessions, subagents: subs,
                             isAlive: { $0 == 100 })

        XCTAssertEqual(sessions.session(sessionId: "parent")?.subagentCount, 2)
        // Dead sidecar reaped.
        XCTAssertEqual(subs.readAllWithURLs().count, 2)
    }

    private func writeSidecar(_ dir: URL, _ agentId: String, parent: String, pid: Int) throws {
        let rec = ["agentId": agentId, "parentId": parent, "pid": pid] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: rec)
        try data.write(to: dir.appendingPathComponent("\(agentId).json"))
    }
}
