import Foundation

/// Pure-ish fold from the status files on disk into a `SessionStore`, used by
/// both the FSEvents watcher and the poll timer (the wiring lives in the app
/// target).
///
/// Beyond folding, `refresh` does two housekeeping jobs:
/// - **Reap** any status file or subagent sidecar whose owning Claude process
///   is gone. `SessionEnd`/`SubagentStop` aren't crash-safe, so a pid-liveness
///   check is what actually keeps the deck honest. Records with no pid (written
///   before pids existed) are left alone. A pid-liveness check alone can't catch
///   a session whose terminal was closed but whose process lingers headless under
///   the daemon, so a `waiting` session that hasn't done anything for longer than
///   `idleReapAfter` is also reaped: its `timestamp` freezes when it goes idle
///   (no more hooks fire until the user acts), so `now - timestamp` is its idle
///   time. `working` sessions are never idle-reaped — a long tool call keeps them
///   working with a stale timestamp.
/// - **Count subagents** per parent session from the sidecars and stamp the
///   count onto each session for the badge.
public enum StatusEngine {
    /// A `waiting` session idle longer than this is treated as abandoned and reaped.
    public static let idleReapAfter: TimeInterval = 30 * 60

    /// Default liveness probe and clock; both injectable so tests stay deterministic.
    public static func refresh(store: StatusFileStore, into sessions: inout SessionStore,
                               subagents: SubagentFileStore? = nil,
                               isAlive: (Int) -> Bool = ProcessLiveness.isAlive,
                               now: Date = Date()) {
        // 1. Reap dead status files, keep the survivors.
        var events: [StatusEvent] = []
        for (url, event) in store.readAllWithURLs() {
            let processGone = event.pid.map { !isAlive($0) } ?? false
            let idleTooLong = event.status == .waiting
                && now.timeIntervalSince(event.timestamp) > Self.idleReapAfter
            if processGone || idleTooLong {
                store.removeFile(at: url)
            } else {
                events.append(event)
            }
        }
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            sessions.apply(event)
        }

        // 2. Reap dead subagent sidecars, count the survivors per parent.
        guard let subagents else { return }
        var counts: [String: Int] = [:]
        for (url, record) in subagents.readAllWithURLs() {
            if let pid = record.pid, !isAlive(pid) {
                subagents.removeFile(at: url)
                continue
            }
            if let parent = record.parentId { counts[parent, default: 0] += 1 }
        }
        sessions.applySubagentCounts(counts)
    }
}
