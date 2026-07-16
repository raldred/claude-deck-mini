import Foundation

/// User preferences, persisted as JSON at `~/.claude-deck/prefs.json`. Missing or
/// corrupt file → defaults (never throws on load).
public struct DeckPreferences: Codable, Equatable {
    /// Key brightness, 0–100.
    public var brightness: Int
    /// Whether the overflow "▶ more" paging key is enabled (else the first 6
    /// sessions only).
    public var pagingEnabled: Bool
    /// Project group names to hide from the deck (empty = show all).
    public var hiddenProjects: [String]

    public init(brightness: Int = 60, pagingEnabled: Bool = true,
                hiddenProjects: [String] = []) {
        self.brightness = brightness
        self.pagingEnabled = pagingEnabled
        self.hiddenProjects = hiddenProjects
    }

    public static func load(from url: URL = DeckPaths.prefsFile) -> DeckPreferences {
        guard let data = try? Data(contentsOf: url),
              let prefs = try? JSONDecoder().decode(DeckPreferences.self, from: data)
        else { return DeckPreferences() }
        return prefs
    }

    public func save(to url: URL = DeckPaths.prefsFile) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }
}
