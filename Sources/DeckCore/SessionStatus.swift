public enum SessionStatus: String, Codable, Equatable, Sendable {
    case working   // actively processing
    case waiting   // needs you — finished turn / permission prompt / idle prompt
    case idle      // alive but status unknown (seeded from transcript freshness)
    case finished  // session ended / process exited

    /// Short human label for the status pill.
    public var label: String {
        switch self {
        case .working:  return "Working"
        case .waiting:  return "Needs you"
        case .idle:     return "Idle"
        case .finished: return "Finished"
        }
    }

    /// Sort rank — lower sorts first. Sessions needing you bubble to the top,
    /// then actively-working ones, then idle, with finished tombstones last.
    public var sortPriority: Int {
        switch self {
        case .waiting:  return 0
        case .working:  return 1
        case .idle:     return 2
        case .finished: return 3
        }
    }
}

/// The subset of Claude Code hook events we care about.
public enum HookEventName: String {
    case sessionStart      = "SessionStart"
    case userPromptSubmit  = "UserPromptSubmit"
    case preToolUse        = "PreToolUse"
    case postToolUse       = "PostToolUse"
    case notification      = "Notification"
    case permissionRequest = "PermissionRequest"
    case stop              = "Stop"
    case sessionEnd        = "SessionEnd"

    /// Map an event to a status.
    /// - Working: prompt submitted, session start, or any tool use. Tool events
    ///   matter most — they fire after a permission grant (which has no
    ///   UserPromptSubmit), flipping the session back out of "needs you".
    /// - Needs you: a finished turn (`Stop`), a permission prompt, or the idle
    ///   "waiting for your input" notification.
    public var status: SessionStatus {
        switch self {
        case .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse:
            return .working
        case .stop, .notification, .permissionRequest:
            return .waiting
        case .sessionEnd:
            return .finished
        }
    }
}
