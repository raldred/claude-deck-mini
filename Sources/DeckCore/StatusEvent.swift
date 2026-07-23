import Foundation

/// One status record, written to `<sessionId>.json` and read back by the app.
///
/// Claude Deck is a pure observer — it never owns a session — so the storage key
/// is always Claude's own `sessionId`. (Depot, which launches sessions, needed a
/// separate launch id and an `isExternal` flag; neither applies here.)
public struct StatusEvent: Codable, Equatable, Sendable {
    public let sessionId: String
    public let status: SessionStatus
    public let cwd: String?
    public let timestamp: Date
    /// The owning Claude process id, recorded by the hook so the app can reap
    /// files whose process has died (SessionEnd isn't crash-safe). Optional for
    /// backward compatibility with files written before this field existed.
    public let pid: Int?

    public init(sessionId: String, status: SessionStatus, cwd: String?,
                timestamp: Date, pid: Int? = nil) {
        self.sessionId = sessionId
        self.status = status
        self.cwd = cwd
        self.timestamp = timestamp
        self.pid = pid
    }
}
