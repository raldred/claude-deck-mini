import Foundation

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

    /// Register the plugin dir as a marketplace, install it at user scope, and
    /// enable it. Idempotent — merges into the existing registry files.
    public func register(pluginDir: URL, version: String, now: Date = Date()) throws {
        let path = pluginDir.path
        let iso = ISO8601DateFormatter().string(from: now)

        // 1. known_marketplaces.json
        var markets = readObject(knownMarketplaces)
        markets[PluginManifest.marketplaceName] = [
            "source": ["source": "directory", "path": path],
            "installLocation": path,
            "lastUpdated": iso,
        ]
        try writeJSON(markets, to: knownMarketplaces)

        // 2. installed_plugins.json (version 2 shape: {version, plugins:{key:[entry]}})
        var installedRoot = readObject(installedPlugins)
        if installedRoot["version"] == nil { installedRoot["version"] = 2 }
        var plugins = installedRoot["plugins"] as? [String: Any] ?? [:]
        plugins[PluginManifest.qualifiedName] = [[
            "scope": "user",
            "installPath": path,
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
