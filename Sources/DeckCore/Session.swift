import Foundation

/// A live Claude Code session as observed from its status file. Keyed on Claude's
/// own `sessionId` — Claude Deck never launches sessions, so there's no separate
/// launch id or app-ownership flag.
public struct Session: Identifiable, Equatable {
    public let sessionId: String
    public var workingDirectory: URL
    public var status: SessionStatus
    public var lastActivity: Date
    /// How many background/forked agents this session currently has running,
    /// counted from the subagent sidecars. Shown as a badge on the key.
    public var subagentCount: Int = 0
    /// When this session was first observed. Fixes its slot in the ordering so
    /// projects don't shuffle as their status or activity changes. The app owns
    /// the authoritative value (it survives store rebuilds); this defaults to
    /// `lastActivity` for callers/tests that don't stamp it.
    public var firstSeen: Date
    /// The owning Claude process id, carried from the status file so a key press
    /// can resolve the session's controlling terminal. Nil for records written
    /// before pids existed.
    public var pid: Int?

    public var id: String { sessionId }

    public init(sessionId: String, workingDirectory: URL,
                status: SessionStatus = .thinking, lastActivity: Date = .distantPast,
                firstSeen: Date? = nil, pid: Int? = nil) {
        self.sessionId = sessionId
        self.workingDirectory = workingDirectory
        self.status = status
        self.lastActivity = lastActivity
        self.firstSeen = firstSeen ?? lastActivity
        self.pid = pid
    }

    /// Marker dirs that separate a repo from its worktrees. Claude's own
    /// worktrees live at `<repo>/.claude/worktrees/<name>`; Residently and
    /// claude-depot use `<repo>/.worktrees/<name>`. `.claude/worktrees` is
    /// checked first so a path containing both matches at the outer repo.
    private static let worktreeMarkers = ["/.claude/worktrees/", "/.worktrees/"]

    /// The `(parentRepoPath, worktreeName)` for a worktree session, or nil when
    /// the path isn't inside a recognised worktree tree.
    private var worktreeSplit: (parent: String, name: String)? {
        let path = workingDirectory.path
        for marker in Self.worktreeMarkers {
            guard let range = path.range(of: marker) else { continue }
            let parent = String(path[..<range.lowerBound])
            let name = String(path[range.upperBound...])
                .split(separator: "/").first.map(String.init) ?? ""
            return (parent, name)
        }
        return nil
    }

    /// Project group key. A git worktree path folds into its parent repo (the
    /// dir that owns the worktree tree); any other path uses its leaf folder name.
    public var projectGroup: String {
        if let split = worktreeSplit {
            return URL(fileURLWithPath: split.parent).lastPathComponent
        }
        return workingDirectory.lastPathComponent
    }

    /// For a worktree session, the worktree's own name with any trailing
    /// `-<hash>` suffix stripped (e.g. `funny-bose-1c8834` → `funny-bose`).
    /// Nil when the session isn't in a worktree.
    public var worktreeLabel: String? {
        guard let leaf = worktreeSplit?.name, !leaf.isEmpty else { return nil }
        if let dash = leaf.range(of: "-[0-9a-f]{6,}$", options: .regularExpression) {
            return String(leaf[..<dash.lowerBound])
        }
        return leaf
    }
}

/// Holds the observed sessions, one row per Claude session id.
public struct SessionStore: Equatable {
    public private(set) var sessions: [Session] = []

    public init() {}

    public func session(sessionId: String) -> Session? {
        sessions.first { $0.sessionId == sessionId }
    }

    /// Sessions ordered by tier priority (needs-you → working → ended),
    /// stable within each tier so equal-status rows keep their insertion order and
    /// don't jitter as statuses change. `sorted(by:)` isn't guaranteed stable, so we
    /// tie-break on the original index.
    public var sortedByStatus: [Session] {
        sessions.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.status.sortPriority, r = rhs.element.status.sortPriority
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    public mutating func remove(sessionId: String) {
        sessions.removeAll { $0.sessionId == sessionId }
    }

    /// Stamp each session's `firstSeen` from the tracker so ordering slots stay
    /// fixed across store rebuilds.
    public mutating func stampFirstSeen(using tracker: inout FirstSeenTracker) {
        sessions = tracker.stamp(sessions)
    }

    /// Set each session's `subagentCount` from a parent-id → count map. Sessions
    /// with no entry reset to 0 so a badge clears when the last agent finishes.
    public mutating func applySubagentCounts(_ counts: [String: Int]) {
        for i in sessions.indices {
            sessions[i].subagentCount = counts[sessions[i].sessionId] ?? 0
        }
    }

    /// Upsert a status event by session id: update the existing row, or insert a
    /// new one. As a pure observer, every event either matches a known session or
    /// is a newly-discovered one — there's no app-owned/external distinction.
    public mutating func apply(_ event: StatusEvent) {
        let dir = event.cwd.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory())
        if let i = sessions.firstIndex(where: { $0.sessionId == event.sessionId }) {
            sessions[i].status = event.status
            sessions[i].lastActivity = event.timestamp
            sessions[i].pid = event.pid
            if event.cwd != nil { sessions[i].workingDirectory = dir }
            return
        }
        sessions.append(Session(
            sessionId: event.sessionId,
            workingDirectory: dir,
            status: event.status,
            lastActivity: event.timestamp,
            pid: event.pid))
    }
}
