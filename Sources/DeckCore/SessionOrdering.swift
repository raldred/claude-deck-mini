import Foundation

/// Shared ordering for sessions, used by the menu and the deck layout so they
/// stay consistent.
///
/// Primary sort is status priority (needs-you → working → idle → finished).
/// Within a tier the tie-break depends on the tier:
/// - **needs-you**: oldest activity first, so the session you've kept waiting
///   longest bubbles to the top — that's the one most in need of attention.
/// - **everything else**: most-recent activity first (fresh work on top).
public enum SessionOrdering {
    public static func precedes(_ lhs: Session, _ rhs: Session) -> Bool {
        let l = lhs.status.sortPriority, r = rhs.status.sortPriority
        if l != r { return l < r }
        if lhs.status == .waiting {
            return lhs.lastActivity < rhs.lastActivity   // longest wait first
        }
        return lhs.lastActivity > rhs.lastActivity       // most recent first
    }
}
