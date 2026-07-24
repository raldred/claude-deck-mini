import Foundation

/// Maps the observed sessions onto the deck's fixed set of keys, handling
/// ordering, overflow paging, and blank fill. Pure and deterministic — the only
/// external input is the `NameResolver` cache lookup for each session's label.
public enum DeckLayout {
    /// Build the key layout for a given page.
    ///
    /// - `≤ keyCount` sessions: every session gets a key, unused keys are blank;
    ///   `page` is ignored (there's nothing to page through).
    /// - `> keyCount` sessions: the first `keyCount - 1` keys show a page of
    ///   sessions and the last key becomes `.more(remaining)`. `page` wraps, so
    ///   pressing "more" past the end returns to the first page.
    public static func keys(for sessions: [Session], page: Int, now: Date,
                            resolver: NameResolver, keyCount: Int = 6,
                            stuckThreshold: TimeInterval = 180) -> [DeckKey] {
        let ordered = sessions.sorted(by: SessionOrdering.precedes)

        // No sessions — paint a banner spanning every key.
        if ordered.isEmpty {
            return (0..<keyCount).map { DeckKey(index: $0, kind: .banner(text: "No active sessions")) }
        }

        func agentKey(_ index: Int, _ session: Session) -> DeckKey {
            let stuck = session.status == .waiting
                && now.timeIntervalSince(session.lastActivity) >= stuckThreshold
            return DeckKey(index: index, kind: .agent(
                label: resolver.label(sessionId: session.sessionId, cwd: session.workingDirectory),
                status: session.status,
                age: RelativeTime.since(session.lastActivity, now: now),
                subagents: session.subagentCount,
                stuck: stuck))
        }

        // Fits on one screen — no paging key needed.
        if ordered.count <= keyCount {
            return (0..<keyCount).map { i in
                i < ordered.count ? agentKey(i, ordered[i]) : DeckKey(index: i, kind: .blank)
            }
        }

        // Overflow: reserve the last key for paging.
        let perPage = keyCount - 1
        let pageCount = (ordered.count + perPage - 1) / perPage
        let p = ((page % pageCount) + pageCount) % pageCount   // safe wrap for negatives
        let start = p * perPage
        let slice = Array(ordered[start..<min(start + perPage, ordered.count)])

        var result: [DeckKey] = (0..<perPage).map { i in
            i < slice.count ? agentKey(i, slice[i]) : DeckKey(index: i, kind: .blank)
        }
        result.append(DeckKey(index: keyCount - 1, kind: .more(remaining: ordered.count - slice.count)))
        return result
    }

    /// The session shown at each key index for a page, or nil where the key isn't
    /// a session (blank / paging / banner). Mirrors `keys(for:)`'s ordering and
    /// paging so a key press can resolve back to its session.
    public static func sessionsForPage(_ sessions: [Session], page: Int,
                                       keyCount: Int = 6) -> [Session?] {
        let ordered = sessions.sorted(by: SessionOrdering.precedes)
        if ordered.isEmpty { return Array(repeating: nil, count: keyCount) }
        if ordered.count <= keyCount {
            return (0..<keyCount).map { $0 < ordered.count ? ordered[$0] : nil }
        }
        let perPage = keyCount - 1
        let pageCount = (ordered.count + perPage - 1) / perPage
        let p = ((page % pageCount) + pageCount) % pageCount
        let start = p * perPage
        let slice = Array(ordered[start..<min(start + perPage, ordered.count)])
        var result: [Session?] = (0..<perPage).map { $0 < slice.count ? slice[$0] : nil }
        result.append(nil)  // paging key — not a session
        return result
    }
}
