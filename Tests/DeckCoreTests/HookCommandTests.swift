import XCTest
@testable import DeckCore

final class HookCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func tempStore() -> StatusFileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-hookcmd-\(UUID().uuidString)")
        return StatusFileStore(directory: dir)
    }

    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    func testWaitingEventWritesStatusFile() throws {
        let store = tempStore()
        try HookCommand.handle(
            jsonData: json(#"{"session_id":"s1","hook_event_name":"Stop","cwd":"/w"}"#),
            store: store, now: now)

        let all = try store.readAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.sessionId, "s1")
        XCTAssertEqual(all.first?.status, .turnDone)
    }

    func testWorkingEventWritesStatusFile() throws {
        let store = tempStore()
        try HookCommand.handle(
            jsonData: json(#"{"session_id":"s1","hook_event_name":"PreToolUse","cwd":"/w","tool_name":"Bash"}"#),
            store: store, now: now)
        XCTAssertEqual(try store.readAll().first?.status, .thinking)
    }

    func testSessionEndRemovesStatusFile() throws {
        let store = tempStore()
        try HookCommand.handle(
            jsonData: json(#"{"session_id":"s1","hook_event_name":"Stop","cwd":"/w"}"#),
            store: store, now: now)
        XCTAssertEqual(try store.readAll().count, 1)

        try HookCommand.handle(
            jsonData: json(#"{"session_id":"s1","hook_event_name":"SessionEnd","cwd":"/w"}"#),
            store: store, now: now)

        XCTAssertEqual(try store.readAll().count, 0)
    }

    func testIgnoredEventDoesNothing() throws {
        let store = tempStore()
        let applied = try HookCommand.handle(
            jsonData: json(#"{"session_id":"s1","hook_event_name":"Wibble","cwd":"/w"}"#),
            store: store, now: now)
        XCTAssertNil(applied)
        XCTAssertEqual(try store.readAll().count, 0)
    }

    func testMissingSessionIdIsIgnored() throws {
        let store = tempStore()
        let applied = try HookCommand.handle(
            jsonData: json(#"{"hook_event_name":"Stop","cwd":"/w"}"#),
            store: store, now: now)
        XCTAssertNil(applied)
    }
}
