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
        try store.write(StatusEvent(sessionId: "c1", status: .waiting, cwd: "/w",
                                    timestamp: Date(timeIntervalSince1970: 9)))

        var sessions = SessionStore()
        StatusEngine.refresh(store: store, into: &sessions)

        XCTAssertEqual(sessions.session(sessionId: "c1")?.status, .waiting)
        XCTAssertEqual(sessions.session(sessionId: "c1")?.workingDirectory.path, "/w")
    }

    func testRefreshAppliesNewestEventLast() throws {
        let store = StatusFileStore(directory: tempDir())
        // Two sessions, written out of order — refresh sorts by timestamp so the
        // final state per session is its latest event.
        try store.write(StatusEvent(sessionId: "a", status: .working, cwd: "/w",
                                    timestamp: Date(timeIntervalSince1970: 5)))
        try store.write(StatusEvent(sessionId: "b", status: .waiting, cwd: "/w",
                                    timestamp: Date(timeIntervalSince1970: 9)))

        var sessions = SessionStore()
        StatusEngine.refresh(store: store, into: &sessions)

        XCTAssertEqual(sessions.session(sessionId: "a")?.status, .working)
        XCTAssertEqual(sessions.session(sessionId: "b")?.status, .waiting)
        XCTAssertEqual(sessions.sessions.count, 2)
    }
}
