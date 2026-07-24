import XCTest
@testable import DeckCore

final class HookHandlerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testBuildsStatusEventFromNotification() throws {
        let json = """
        {"session_id":"abc-123","hook_event_name":"Notification","cwd":"/work/foo"}
        """.data(using: .utf8)!

        let event = try HookHandler.makeEvent(jsonData: json, now: now)

        XCTAssertEqual(event?.sessionId, "abc-123")
        XCTAssertEqual(event?.status, .idle)
        XCTAssertEqual(event?.cwd, "/work/foo")
        XCTAssertEqual(event?.timestamp, now)
    }

    // Finishing a turn means "your move" — needs you, distinct from a permission block.
    func testStopEventMapsToTurnDone() throws {
        let json = """
        {"session_id":"abc-123","hook_event_name":"Stop","cwd":"/work/foo"}
        """.data(using: .utf8)!
        let event = try HookHandler.makeEvent(jsonData: json, now: now)
        XCTAssertEqual(event?.status, .turnDone)
    }

    func testNotificationPermissionTypeMapsToPermission() throws {
        let json = #"{"session_id":"a","hook_event_name":"Notification","notification_type":"permission_prompt"}"#.data(using: .utf8)!
        XCTAssertEqual(try HookHandler.makeEvent(jsonData: json, now: now)?.status, .permission)
    }

    func testPreToolUseMapsToThinking() throws {
        let json = """
        {"session_id":"abc-123","hook_event_name":"PreToolUse","cwd":"/w","tool_name":"Bash"}
        """.data(using: .utf8)!
        let event = try HookHandler.makeEvent(jsonData: json, now: now)
        XCTAssertEqual(event?.status, .thinking)
    }

    func testReturnsNilForUnhandledEvent() throws {
        let json = """
        {"session_id":"abc","hook_event_name":"Wibble","cwd":"/x"}
        """.data(using: .utf8)!
        XCTAssertNil(try HookHandler.makeEvent(jsonData: json, now: now))
    }

    // We key every record on the session id; a payload without one is unusable.
    func testReturnsNilWhenSessionIdMissing() throws {
        let json = """
        {"hook_event_name":"Stop","cwd":"/x"}
        """.data(using: .utf8)!
        XCTAssertNil(try HookHandler.makeEvent(jsonData: json, now: now))
    }
}
