import Foundation

/// Pure-ish fold from the status files on disk into a `SessionStore`, used by
/// both the FSEvents watcher and the poll timer (the wiring lives in the app
/// target).
///
/// Beyond folding, `refresh` does two housekeeping jobs:
/// - **Reap** any status file or subagent sidecar whose owning Claude process
///   is gone. `SessionEnd`/`SubagentStop` aren't crash-safe, so a pid-liveness
///   check is what actually keeps the deck honest. Records with no pid (written
///   before pids existed) are left alone.
/// - **Count subagents** per parent session from the sidecars and stamp the
///   count onto each session for the badge.
public enum StatusEngine {
    /// Default liveness probe; injectable so tests stay deterministic.
    public static func refresh(store: StatusFileStore, into sessions: inout SessionStore,
                               subagents: SubagentFileStore? = nil,
                               isAlive: (Int) -> Bool = ProcessLiveness.isAlive) {
        // 1. Reap dead status files, keep the survivors.
        var events: [StatusEvent] = []
        for (url, event) in store.readAllWithURLs() {
            if let pid = event.pid, !isAlive(pid) {
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
