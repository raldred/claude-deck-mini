import Foundation

/// Reads and writes status files named `<sessionId>.json` in a directory.
public struct StatusFileStore {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    public func url(forSessionId id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    public func write(_ event: StatusEvent) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(event)
        try data.write(to: url(forSessionId: event.sessionId), options: .atomic)
    }

    /// Delete the status file for a session id. No-op if it doesn't exist, so a
    /// finished session doesn't reappear on the next poll.
    public func removeFile(sessionId: String) throws {
        let url = url(forSessionId: sessionId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func readAll() throws -> [StatusEvent] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(StatusEvent.self, from: Data(contentsOf: $0)) }
    }
}
