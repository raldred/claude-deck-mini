import Foundation

/// JSON Claude Code pipes to a hook command on stdin.
///
/// We decode only the fields the status pipeline needs. `tool_input` is
/// deliberately not decoded: its values are heterogeneous (strings, numbers,
/// arrays, nested objects), so typing it would make the whole decode throw on
/// tools like Grep/TodoWrite and drop the event. Unknown JSON keys are ignored.
public struct HookInput: Codable, Equatable {
    public let sessionId: String?
    public let hookEventName: String
    public let cwd: String?
    public let toolName: String?
    public let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case toolName = "tool_name"
        case notificationType = "notification_type"
    }
}
