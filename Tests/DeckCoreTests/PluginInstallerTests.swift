import XCTest
@testable import DeckCore

final class PluginInstallerTests: XCTestCase {
    private func tempClaudeDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-claude-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func readJSON(_ url: URL) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) ?? [:]
    }

    /// A realistic bundle marketplace dir: the plugin tree plus a stub hook script,
    /// so `register()`'s cache copy has a real source to copy from.
    private func makeBundleDir(_ installer: PluginInstaller, version: String) throws -> URL {
        let bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-bundle-\(UUID().uuidString)")
        try installer.writePluginTree(to: bundle, version: version)
        let scriptsDir = bundle.appendingPathComponent("plugins/claude-deck/scripts")
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try Data("#!/usr/bin/env python3\n".utf8)
            .write(to: scriptsDir.appendingPathComponent("write-status"))
        return bundle
    }

    func testWritePluginTreeCreatesMarketplaceAndNestedPlugin() throws {
        let installer = PluginInstaller(claudeDir: tempClaudeDir())
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-plugin-\(UUID().uuidString)")

        try installer.writePluginTree(to: root, version: "1.0.0")

        let market = readJSON(root.appendingPathComponent(".claude-plugin/marketplace.json"))
        let plugins = market["plugins"] as? [[String: Any]]
        XCTAssertEqual(plugins?.first?["source"] as? String, "./plugins/claude-deck")

        let manifest = readJSON(
            root.appendingPathComponent("plugins/claude-deck/.claude-plugin/plugin.json"))
        XCTAssertEqual(manifest["name"] as? String, "claude-deck")

        let hooks = readJSON(root.appendingPathComponent("plugins/claude-deck/hooks/hooks.json"))
        XCTAssertNotNil(hooks["hooks"])
    }

    func testRegisterCopiesPluginIntoCacheAndPointsInstallPathThere() throws {
        let claude = tempClaudeDir()
        let installer = PluginInstaller(claudeDir: claude)
        let bundle = try makeBundleDir(installer, version: "1.0.0")

        try installer.register(pluginDir: bundle, version: "1.0.0")

        let cache = claude.appendingPathComponent(
            "plugins/cache/claude-deck-marketplace/claude-deck/1.0.0")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: cache.appendingPathComponent("hooks/hooks.json").path),
            "hooks not copied into cache")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: cache.appendingPathComponent("scripts/write-status").path),
            "script not copied into cache")

        let installed = readJSON(claude.appendingPathComponent("plugins/installed_plugins.json"))
        let entry = ((installed["plugins"] as? [String: Any])?[
            "claude-deck@claude-deck-marketplace"] as? [[String: Any]])?.first
        XCTAssertEqual(entry?["installPath"] as? String, cache.path,
                       "installPath must point at the cache copy, not the bundle")
    }

    func testRegisterWritesAllThreeRegistryEntries() throws {
        let claude = tempClaudeDir()
        let installer = PluginInstaller(claudeDir: claude)
        let pluginDir = try makeBundleDir(installer, version: "1.0.0")

        try installer.register(pluginDir: pluginDir, version: "1.0.0")

        let markets = readJSON(claude.appendingPathComponent("plugins/known_marketplaces.json"))
        XCTAssertNotNil(markets["claude-deck-marketplace"])

        let installed = readJSON(claude.appendingPathComponent("plugins/installed_plugins.json"))
        let plugins = installed["plugins"] as? [String: Any]
        XCTAssertNotNil(plugins?["claude-deck@claude-deck-marketplace"])
        XCTAssertEqual(installed["version"] as? Int, 2)

        let settings = readJSON(claude.appendingPathComponent("settings.json"))
        let enabled = settings["enabledPlugins"] as? [String: Any]
        XCTAssertEqual(enabled?["claude-deck@claude-deck-marketplace"] as? Bool, true)
    }

    func testRegisterPreservesExistingEntries() throws {
        let claude = tempClaudeDir()
        // Seed pre-existing registry content (other marketplaces/plugins/settings).
        try FileManager.default.createDirectory(
            at: claude.appendingPathComponent("plugins"), withIntermediateDirectories: true)
        try Data(#"{"other-marketplace":{"x":1}}"#.utf8)
            .write(to: claude.appendingPathComponent("plugins/known_marketplaces.json"))
        try Data(#"{"version":2,"plugins":{"foo@bar":[{"scope":"user"}]}}"#.utf8)
            .write(to: claude.appendingPathComponent("plugins/installed_plugins.json"))
        try Data(#"{"model":"opus","enabledPlugins":{"foo@bar":true}}"#.utf8)
            .write(to: claude.appendingPathComponent("settings.json"))

        let installer = PluginInstaller(claudeDir: claude)
        let bundle = try makeBundleDir(installer, version: "1.0.0")
        try installer.register(pluginDir: bundle, version: "1.0.0")

        let markets = readJSON(claude.appendingPathComponent("plugins/known_marketplaces.json"))
        XCTAssertNotNil(markets["other-marketplace"], "existing marketplace clobbered")
        XCTAssertNotNil(markets["claude-deck-marketplace"])

        let settings = readJSON(claude.appendingPathComponent("settings.json"))
        XCTAssertEqual(settings["model"] as? String, "opus", "unrelated setting clobbered")
        let enabled = settings["enabledPlugins"] as? [String: Any]
        XCTAssertEqual(enabled?["foo@bar"] as? Bool, true)
        XCTAssertEqual(enabled?["claude-deck@claude-deck-marketplace"] as? Bool, true)
    }

    func testRegisterIsIdempotent() throws {
        let claude = tempClaudeDir()
        let installer = PluginInstaller(claudeDir: claude)
        let pluginDir = try makeBundleDir(installer, version: "1.0.0")

        try installer.register(pluginDir: pluginDir, version: "1.0.0")
        try installer.register(pluginDir: pluginDir, version: "1.0.0")

        let installed = readJSON(claude.appendingPathComponent("plugins/installed_plugins.json"))
        let entries = (installed["plugins"] as? [String: Any])?["claude-deck@claude-deck-marketplace"] as? [Any]
        XCTAssertEqual(entries?.count, 1, "duplicate install entry")
    }

    func testUnregisterRemovesOnlyOurEntries() throws {
        let claude = tempClaudeDir()
        try FileManager.default.createDirectory(
            at: claude.appendingPathComponent("plugins"), withIntermediateDirectories: true)
        try Data(#"{"model":"opus","enabledPlugins":{"foo@bar":true}}"#.utf8)
            .write(to: claude.appendingPathComponent("settings.json"))

        let installer = PluginInstaller(claudeDir: claude)
        let bundle = try makeBundleDir(installer, version: "1.0.0")
        try installer.register(pluginDir: bundle, version: "1.0.0")
        try installer.unregister()

        let markets = readJSON(claude.appendingPathComponent("plugins/known_marketplaces.json"))
        XCTAssertNil(markets["claude-deck-marketplace"])
        let settings = readJSON(claude.appendingPathComponent("settings.json"))
        let enabled = settings["enabledPlugins"] as? [String: Any]
        XCTAssertNil(enabled?["claude-deck@claude-deck-marketplace"])
        XCTAssertEqual(enabled?["foo@bar"] as? Bool, true, "unrelated plugin removed")
    }
}
