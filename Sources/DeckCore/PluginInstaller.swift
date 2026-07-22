import Foundation

public enum PluginInstallerError: Error, CustomStringConvertible {
    /// `register` was called with a `pluginDir` that has no `plugins/<name>/`
    /// subtree to copy — usually `writePluginTree` hasn't run yet.
    case missingPluginTree(String)

    public var description: String {
        switch self {
        case let .missingPluginTree(path):
            return "plugin tree not found at \(path); run writePluginTree first"
        }
    }
}

/// Installs the Claude Deck plugin the way claude-status does: ship the plugin
/// tree in the app bundle and register it as a directory-source marketplace via
/// Claude Code's three registry files. All paths are injectable for testing.
public struct PluginInstaller {
    /// `~/.claude` (or a temp dir in tests).
    public let claudeDir: URL

    public init(claudeDir: URL? = nil) {
        self.claudeDir = claudeDir
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    private var knownMarketplaces: URL { claudeDir.appendingPathComponent("plugins/known_marketplaces.json") }
    private var installedPlugins: URL { claudeDir.appendingPathComponent("plugins/installed_plugins.json") }
    private var settings: URL { claudeDir.appendingPathComponent("settings.json") }

    /// Where Claude Code expects the plugin's files: a version-scoped copy under
    /// its cache. `register()` populates this from the bundle's plugin subtree.
    private func cacheDir(version: String) -> URL {
        claudeDir.appendingPathComponent(
            "plugins/cache/\(PluginManifest.marketplaceName)/\(PluginManifest.pluginName)/\(version)")
    }

    // MARK: - plugin tree

    /// Lay down a valid marketplace: `.claude-plugin/marketplace.json` at the root
    /// and the plugin nested at `plugins/<name>/` with its own manifest + hooks.
    public func writePluginTree(to pluginRoot: URL, version: String) throws {
        let marketDir = pluginRoot.appendingPathComponent(".claude-plugin")
        try FileManager.default.createDirectory(at: marketDir, withIntermediateDirectories: true)
        try writeJSON(PluginManifest.marketplaceJSON(version: version),
                      to: marketDir.appendingPathComponent("marketplace.json"))

        let pluginDir = pluginRoot.appendingPathComponent("plugins/\(PluginManifest.pluginName)")
        let manifestDir = pluginDir.appendingPathComponent(".claude-plugin")
        let hooksDir = pluginDir.appendingPathComponent("hooks")
        try FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        try writeJSON(PluginManifest.pluginJSON(version: version),
                      to: manifestDir.appendingPathComponent("plugin.json"))
        try writeJSON(PluginManifest.hooksJSON(),
                      to: hooksDir.appendingPathComponent("hooks.json"))
    }

    // MARK: - registry

    /// Register the marketplace, copy the plugin into Claude Code's cache (CC reads
    /// from there, not in-place), and enable it. Idempotent — merges into the
    /// existing registry files and replaces any existing cache copy.
    public func register(pluginDir: URL, version: String, now: Date = Date()) throws {
        let marketplacePath = pluginDir.path
        let iso = ISO8601DateFormatter().string(from: now)

        // Copy the plugin subtree into CC's cache — CC reads from here, not in-place.
        let source = pluginDir.appendingPathComponent("plugins/\(PluginManifest.pluginName)")
        let cache = cacheDir(version: version)
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw PluginInstallerError.missingPluginTree(source.path)
        }
        if fm.fileExists(atPath: cache.path) { try fm.removeItem(at: cache) }
        try fm.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: cache)

        // 1. known_marketplaces.json — marketplace root as a directory source.
        var markets = readObject(knownMarketplaces)
        markets[PluginManifest.marketplaceName] = [
            "source": ["source": "directory", "path": marketplacePath],
            "installLocation": marketplacePath,
            "lastUpdated": iso,
        ]
        try writeJSON(markets, to: knownMarketplaces)

        // 2. installed_plugins.json — installPath points at the CACHE copy.
        var installedRoot = readObject(installedPlugins)
        if installedRoot["version"] == nil { installedRoot["version"] = 2 }
        var plugins = installedRoot["plugins"] as? [String: Any] ?? [:]
        plugins[PluginManifest.qualifiedName] = [[
            "scope": "user",
            "installPath": cache.path,
            "version": version,
            "installedAt": iso,
            "lastUpdated": iso,
        ]]
        installedRoot["plugins"] = plugins
        try writeJSON(installedRoot, to: installedPlugins)

        // 3. settings.json → enabledPlugins
        var settingsRoot = readObject(settings)
        var enabled = settingsRoot["enabledPlugins"] as? [String: Any] ?? [:]
        enabled[PluginManifest.qualifiedName] = true
        settingsRoot["enabledPlugins"] = enabled
        try writeJSON(settingsRoot, to: settings)
    }

    /// Remove just our three registry entries, leaving everything else intact.
    public func unregister() throws {
        var markets = readObject(knownMarketplaces)
        if markets.removeValue(forKey: PluginManifest.marketplaceName) != nil {
            try writeJSON(markets, to: knownMarketplaces)
        }

        var installedRoot = readObject(installedPlugins)
        if var plugins = installedRoot["plugins"] as? [String: Any],
           plugins.removeValue(forKey: PluginManifest.qualifiedName) != nil {
            installedRoot["plugins"] = plugins
            try writeJSON(installedRoot, to: installedPlugins)
        }

        var settingsRoot = readObject(settings)
        if var enabled = settingsRoot["enabledPlugins"] as? [String: Any],
           enabled.removeValue(forKey: PluginManifest.qualifiedName) != nil {
            settingsRoot["enabledPlugins"] = enabled
            try writeJSON(settingsRoot, to: settings)
        }

        // Drop our whole cache tree so no stale version copy lingers.
        let cacheRoot = claudeDir.appendingPathComponent(
            "plugins/cache/\(PluginManifest.marketplaceName)")
        if FileManager.default.fileExists(atPath: cacheRoot.path) {
            try FileManager.default.removeItem(at: cacheRoot)
        }
    }

    // MARK: - JSON helpers

    private func readObject(_ url: URL) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) ?? [:]
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
