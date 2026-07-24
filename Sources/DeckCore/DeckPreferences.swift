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
    /// Seconds a `waiting` session must sit untouched before the deck escalates
    /// its pulse (louder blink). Default 180 (3 min).
    public var stuckThresholdSeconds: TimeInterval

    public init(brightness: Int = 60, pagingEnabled: Bool = true,
                hiddenProjects: [String] = [], stuckThresholdSeconds: TimeInterval = 180) {
        self.brightness = brightness
        self.pagingEnabled = pagingEnabled
        self.hiddenProjects = hiddenProjects
        self.stuckThresholdSeconds = stuckThresholdSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case brightness, pagingEnabled, hiddenProjects, stuckThresholdSeconds
    }

    /// Decode field-by-field so an older `prefs.json` missing any key falls back
    /// to that field's default instead of failing the whole decode (which would
    /// silently reset every saved preference).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try c.decodeIfPresent(Int.self, forKey: .brightness) ?? 60
        pagingEnabled = try c.decodeIfPresent(Bool.self, forKey: .pagingEnabled) ?? true
        hiddenProjects = try c.decodeIfPresent([String].self, forKey: .hiddenProjects) ?? []
        stuckThresholdSeconds = try c.decodeIfPresent(TimeInterval.self,
                                                      forKey: .stuckThresholdSeconds) ?? 180
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
