import XCTest
@testable import DeckCore

final class StatusFileStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testWriteThenReadAllRoundtrips() throws {
        let store = StatusFileStore(directory: tempDir())
        let event = StatusEvent(sessionId: "c1", status: .waiting, cwd: "/w",
                                timestamp: Date(timeIntervalSince1970: 1))

        try store.write(event)

        XCTAssertEqual(try store.readAll(), [event])
    }

    func testRemoveFileDeletesTheStatusFile() throws {
        let store = StatusFileStore(directory: tempDir())
        try store.write(StatusEvent(sessionId: "c1", status: .waiting, cwd: nil,
                                    timestamp: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(try store.readAll().count, 1)

        try store.removeFile(sessionId: "c1")

        XCTAssertEqual(try store.readAll().count, 0)
    }

    func testRemoveFileIsNoOpWhenMissing() throws {
        let store = StatusFileStore(directory: tempDir())
        XCTAssertNoThrow(try store.removeFile(sessionId: "nope"))
    }

    func testWriteOverwritesSameSessionId() throws {
        let store = StatusFileStore(directory: tempDir())
        let first = StatusEvent(sessionId: "c1", status: .working, cwd: nil,
                                timestamp: Date(timeIntervalSince1970: 1))
        let second = StatusEvent(sessionId: "c1", status: .idle, cwd: nil,
                                 timestamp: Date(timeIntervalSince1970: 2))

        try store.write(first)
        try store.write(second)

        XCTAssertEqual(try store.readAll(), [second])
    }
}
