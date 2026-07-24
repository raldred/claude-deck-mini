import XCTest
@testable import DeckCore

final class SessionStatusTests: XCTestCase {
    func testWorkingEventsMapToThinking() {
        XCTAssertEqual(HookEventName.sessionStart.status, .thinking)
        XCTAssertEqual(HookEventName.userPromptSubmit.status, .thinking)
        XCTAssertEqual(HookEventName.preToolUse.status, .thinking)
        XCTAssertEqual(HookEventName.postToolUse.status, .thinking)
        XCTAssertEqual(HookEventName.postCompact.status, .thinking)
    }

    func testCompactionAndTurnAndPermission() {
        XCTAssertEqual(HookEventName.preCompact.status, .compacting)
        XCTAssertEqual(HookEventName.stop.status, .turnDone)
        XCTAssertEqual(HookEventName.permissionRequest.status, .permission)
        XCTAssertEqual(HookEventName.sessionEnd.status, .ended)
    }

    // Notification's fine status depends on notification_type, resolved in
    // HookHandler; the event's own default is the idle nudge.
    func testNotificationDefaultsToIdle() {
        XCTAssertEqual(HookEventName.notification.status, .idle)
    }

    func testTiers() {
        XCTAssertEqual(SessionStatus.permission.tier, .needsYou)
        XCTAssertEqual(SessionStatus.turnDone.tier, .needsYou)
        XCTAssertEqual(SessionStatus.idle.tier, .needsYou)
        XCTAssertEqual(SessionStatus.thinking.tier, .working)
        XCTAssertEqual(SessionStatus.compacting.tier, .working)
        XCTAssertEqual(SessionStatus.ended.tier, .ended)
    }

    func testSortPriorityOrdersNeedsYouThenWorkingThenEnded() {
        XCTAssertLessThan(SessionStatus.permission.sortPriority, SessionStatus.thinking.sortPriority)
        XCTAssertLessThan(SessionStatus.thinking.sortPriority, SessionStatus.ended.sortPriority)
    }

    func testHookEventParsesNewNames() {
        XCTAssertEqual(HookEventName(rawValue: "PreCompact"), .preCompact)
        XCTAssertEqual(HookEventName(rawValue: "PostCompact"), .postCompact)
        XCTAssertEqual(HookEventName(rawValue: "PermissionRequest"), .permissionRequest)
    }

    // Legacy status files (written before this change) and any unknown value
    // decode to a safe working default instead of dropping the record.
    func testLegacyAndUnknownStatusDecode() throws {
        func decode(_ raw: String) throws -> SessionStatus {
            try JSONDecoder().decode(SessionStatus.self, from: Data("\"\(raw)\"".utf8))
        }
        XCTAssertEqual(try decode("working"), .thinking)
        XCTAssertEqual(try decode("waiting"), .idle)
        XCTAssertEqual(try decode("idle"), .idle)
        XCTAssertEqual(try decode("wibble"), .thinking)
        XCTAssertEqual(try decode("permission"), .permission)
    }

    // The custom decoder pairs with the synthesized encoder — round-trip the
    // hyphenated rawValue so the on-disk contract can't silently drift.
    func testEncodeRoundTripsRawValue() throws {
        for status in [SessionStatus.permission, .turnDone, .idle, .thinking, .compacting, .ended] {
            let data = try JSONEncoder().encode(status)
            XCTAssertEqual(try JSONDecoder().decode(SessionStatus.self, from: data), status)
        }
        XCTAssertEqual(String(data: try JSONEncoder().encode(SessionStatus.turnDone), encoding: .utf8),
                       "\"turn_done\"")
    }
}
