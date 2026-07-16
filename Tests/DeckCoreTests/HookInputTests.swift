import XCTest
@testable import DeckCore

final class HookInputTests: XCTestCase {
    func testDecodesPreToolUseBashPayload() throws {
        let json = #"""
        {"session_id":"s1","hook_event_name":"PreToolUse","cwd":"/w",
         "tool_name":"Bash","tool_input":{"command":"rm -rf /"}}
        """#.data(using: .utf8)!
        let input = try JSONDecoder().decode(HookInput.self, from: json)
        XCTAssertEqual(input.sessionId, "s1")
        XCTAssertEqual(input.toolName, "Bash")
    }

    // Real tool inputs carry non-string values (numbers, arrays, nested objects).
    // We must still decode the record — dropping it would lose a "working" event.
    func testDecodesPayloadWithHeterogeneousToolInput() throws {
        let json = #"""
        {"session_id":"s1","hook_event_name":"PreToolUse","cwd":"/w",
         "tool_name":"TodoWrite",
         "tool_input":{"todos":[{"id":1,"done":false}],"count":3,"nested":{"a":true}}}
        """#.data(using: .utf8)!
        let input = try JSONDecoder().decode(HookInput.self, from: json)
        XCTAssertEqual(input.toolName, "TodoWrite")
    }

    func testDecodesPayloadWithoutToolFields() throws {
        let json = #"{"hook_event_name":"Stop","session_id":"s1"}"#.data(using: .utf8)!
        let input = try JSONDecoder().decode(HookInput.self, from: json)
        XCTAssertNil(input.toolName)
        XCTAssertEqual(input.hookEventName, "Stop")
    }
}
