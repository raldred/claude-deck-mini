import Foundation

public enum HookHandler {
    /// Parse hook stdin JSON into a StatusEvent, or nil for events we ignore
    /// (an unrecognised event name, or a payload with no `session_id` — we key
    /// every record on the Claude session id, so one is required).
    public static func makeEvent(jsonData: Data, now: Date) throws -> StatusEvent? {
        let input = try JSONDecoder().decode(HookInput.self, from: jsonData)
        guard let event = HookEventName(rawValue: input.hookEventName),
              var status = event.status,
              let sessionId = input.sessionId else { return nil }
        if event == .notification, input.notificationType == "permission_prompt" {
            status = .permission
        }
        return StatusEvent(
            sessionId: sessionId,
            status: status,
            cwd: input.cwd,
            timestamp: now
        )
    }
}
