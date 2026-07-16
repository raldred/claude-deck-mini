import Foundation

public enum HookHandler {
    /// Parse hook stdin JSON into a StatusEvent, or nil for events we ignore
    /// (an unrecognised event name, or a payload with no `session_id` — we key
    /// every record on the Claude session id, so one is required).
    public static func makeEvent(jsonData: Data, now: Date) throws -> StatusEvent? {
        let input = try JSONDecoder().decode(HookInput.self, from: jsonData)
        guard let event = HookEventName(rawValue: input.hookEventName),
              let sessionId = input.sessionId else { return nil }
        return StatusEvent(
            sessionId: sessionId,
            status: event.status,
            cwd: input.cwd,
            timestamp: now
        )
    }
}
