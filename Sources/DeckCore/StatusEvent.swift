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

    public init(sessionId: String, status: SessionStatus, cwd: String?, timestamp: Date) {
        self.sessionId = sessionId
        self.status = status
        self.cwd = cwd
        self.timestamp = timestamp
    }
}
