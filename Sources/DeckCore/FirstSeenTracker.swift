import Foundation

/// Remembers when each session was first observed so its slot in the ordering
/// stays fixed across store rebuilds. `StatusEngine` rebuilds the `SessionStore`
/// from disk on every poll, so first-seen can't live on the session itself — the
/// app keeps one tracker for the process lifetime and stamps each refresh.
public struct FirstSeenTracker {
    private var seen: [String: Date] = [:]

    public init() {}

    /// Stamp every session's `firstSeen`: reuse a remembered date, or record the
    /// session's current `lastActivity` for a newly-seen id. Sessions no longer
    /// present are pruned, so a returning id takes a fresh (end-of-list) slot.
    public mutating func stamp(_ sessions: [Session]) -> [Session] {
        let present = Set(sessions.map(\.sessionId))
        seen = seen.filter { present.contains($0.key) }

        return sessions.map { session in
            let date = seen[session.sessionId] ?? session.lastActivity
            seen[session.sessionId] = date
            var stamped = session
            stamped.firstSeen = date
            return stamped
        }
    }
}
