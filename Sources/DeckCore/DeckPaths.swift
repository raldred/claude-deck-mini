import Foundation

/// Filesystem locations Claude Deck owns, all under `~/.claude-deck/`.
public enum DeckPaths {
    public static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-deck")
    }

    public static var statusDir: URL { root.appendingPathComponent("status") }
    public static var subagentsDir: URL { root.appendingPathComponent("subagents") }
    public static var namesFile: URL { root.appendingPathComponent("names.json") }
    public static var prefsFile: URL { root.appendingPathComponent("prefs.json") }
}
