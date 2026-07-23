import Foundation

/// Tests whether a process is still alive. `SessionEnd` isn't crash-safe (hard
/// kill / closed terminal skip it), so the app reaps status files whose owning
/// Claude process is gone. `kill(pid, 0)` sends no signal — it just checks the
/// process exists and we can signal it (or returns EPERM if it exists but is
/// owned by someone else, which still means alive).
public enum ProcessLiveness {
    public static func isAlive(pid: Int) -> Bool {
        if pid <= 0 { return false }
        let result = kill(pid_t(pid), 0)
        if result == 0 { return true }
        return errno == EPERM   // exists but not signalable by us
    }
}
