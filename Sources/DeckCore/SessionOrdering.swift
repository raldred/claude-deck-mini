import Foundation

/// Shared ordering for sessions, used by the menu and the deck layout so they
/// stay consistent.
///
/// Sessions are ordered purely by when they were first observed (`firstSeen`,
/// ascending), so each one keeps a fixed slot — status changes and fresh
/// activity never reshuffle the list. Ties break on `sessionId` for a fully
/// deterministic order.
public enum SessionOrdering {
    public static func precedes(_ lhs: Session, _ rhs: Session) -> Bool {
        if lhs.firstSeen != rhs.firstSeen { return lhs.firstSeen < rhs.firstSeen }
        return lhs.sessionId < rhs.sessionId
    }
}
