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
                            resolver: NameResolver, keyCount: Int = 6) -> [DeckKey] {
        let ordered = sessions.sorted(by: SessionOrdering.precedes)

        func agentKey(_ index: Int, _ session: Session) -> DeckKey {
            DeckKey(index: index, kind: .agent(
                label: resolver.label(sessionId: session.sessionId, cwd: session.workingDirectory),
                status: session.status,
                age: RelativeTime.since(session.lastActivity, now: now)))
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
}
