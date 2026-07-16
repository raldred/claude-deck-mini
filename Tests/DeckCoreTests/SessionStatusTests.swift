import XCTest
@testable import DeckCore

final class SessionStatusTests: XCTestCase {
    func testWorkingEvents() {
        XCTAssertEqual(HookEventName.sessionStart.status, .working)
        XCTAssertEqual(HookEventName.userPromptSubmit.status, .working)
        // Tool use means Claude is actively working — crucially this flips back
        // to working after a permission grant (which fires no UserPromptSubmit).
        XCTAssertEqual(HookEventName.preToolUse.status, .working)
        XCTAssertEqual(HookEventName.postToolUse.status, .working)
    }

    func testSessionEndIsFinished() {
        XCTAssertEqual(HookEventName.sessionEnd.status, .finished)
    }

    // Anything where Claude has stopped and it's the user's move is "needs you":
    // a finished turn (Stop), a permission prompt, or the idle "waiting for your
    // input" notification all collapse into the single highlighted waiting state.
    func testNeedsYouEventsAllMapToWaiting() {
        XCTAssertEqual(HookEventName.stop.status, .waiting)
        XCTAssertEqual(HookEventName.notification.status, .waiting)
        XCTAssertEqual(HookEventName.permissionRequest.status, .waiting)
    }

    func testHookEventParsesFromRawClaudeName() {
        XCTAssertEqual(HookEventName(rawValue: "Notification"), .notification)
        XCTAssertEqual(HookEventName(rawValue: "PermissionRequest"), .permissionRequest)
        XCTAssertEqual(HookEventName(rawValue: "Stop"), .stop)
        XCTAssertEqual(HookEventName(rawValue: "PreToolUse"), .preToolUse)
        XCTAssertEqual(HookEventName(rawValue: "PostToolUse"), .postToolUse)
        XCTAssertNil(HookEventName(rawValue: "PreCompact"))
    }

    func testSortPriorityOrdersWaitingFirst() {
        XCTAssertLessThan(SessionStatus.waiting.sortPriority, SessionStatus.working.sortPriority)
        XCTAssertLessThan(SessionStatus.working.sortPriority, SessionStatus.idle.sortPriority)
        XCTAssertLessThan(SessionStatus.idle.sortPriority, SessionStatus.finished.sortPriority)
    }
}
