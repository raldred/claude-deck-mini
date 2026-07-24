import Foundation

/// The tier a status belongs to — drives ordering, stuck-blink, idle-reaping,
/// and the menu-bar count. Fine statuses within a tier share these behaviours.
public enum StatusTier: Equatable, Sendable {
    case needsYou  // your move: permission / finished turn / idle
    case working   // Claude is busy: thinking / compacting
    case ended     // session over (file gets removed)
}

/// A session's fine-grained state. The rawValue is the wire contract shared with
/// the Python plugin and the deckd renderer, so don't rename cases lightly.
public enum SessionStatus: String, Codable, Equatable, Sendable {
    case permission          // blocked on a tool-permission yes/no
    case turnDone = "turn_done"  // finished its turn — your move
    case idle                // idle "waiting for your input" nudge
    case thinking            // actively generating / running tools
    case compacting          // compacting context (PreCompact→PostCompact)
    case ended               // session ended → status file removed

    public var tier: StatusTier {
        switch self {
        case .permission, .turnDone, .idle: return .needsYou
        case .thinking, .compacting:        return .working
        case .ended:                        return .ended
        }
    }

    /// Short human label for the menu / status pill.
    public var label: String {
        switch self {
        case .permission: return "Permission"
        case .turnDone:   return "Your turn"
        case .idle:       return "Idle"
        case .thinking:   return "Working"
        case .compacting: return "Compacting"
        case .ended:      return "Ended"
        }
    }

    /// Sort rank — lower first. Derived from the tier so needs-you bubbles up,
    /// then working, then ended tombstones.
    public var sortPriority: Int {
        switch tier {
        case .needsYou: return 0
        case .working:  return 1
        case .ended:    return 2
        }
    }

    /// Tolerant decode: a legacy status string (from a file written before this
    /// change) or any unknown value maps to a safe working default rather than
    /// failing the whole record decode (which would drop the session).
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let known = SessionStatus(rawValue: raw) {
            self = known
        } else {
            switch raw {
            case "working": self = .thinking
            case "waiting": self = .idle
            default:        self = .thinking
            }
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
    case preCompact        = "PreCompact"
    case postCompact       = "PostCompact"
    case sessionEnd        = "SessionEnd"
    case subagentStart     = "SubagentStart"
    case subagentStop      = "SubagentStop"

    /// Payload-independent status for an event. `Notification` returns its idle
    /// default; `HookHandler` upgrades it to `.permission` when the payload's
    /// `notification_type` says so. Subagent events don't affect the parent.
    public var status: SessionStatus? {
        switch self {
        case .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .postCompact:
            return .thinking
        case .preCompact:
            return .compacting
        case .stop:
            return .turnDone
        case .permissionRequest:
            return .permission
        case .notification:
            return .idle
        case .sessionEnd:
            return .ended
        case .subagentStart, .subagentStop:
            return nil
        }
    }
}
