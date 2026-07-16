import Foundation

/// Pure fold from the status files on disk into a `SessionStore`, used by both
/// the FSEvents watcher and the poll timer (the wiring lives in the app target).
///
/// As an observer, there's nothing to reconcile: each status file is one
/// session, applied newest-last so the latest event wins.
public enum StatusEngine {
    public static func refresh(store: StatusFileStore, into sessions: inout SessionStore) {
        let events = (try? store.readAll()) ?? []
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            sessions.apply(event)
        }
    }
}
