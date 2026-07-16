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

    func testWritePluginTreeCreatesManifestAndHooks() throws {
        let installer = PluginInstaller(claudeDir: tempClaudeDir())
        let pluginDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-plugin-\(UUID().uuidString)")

        try installer.writePluginTree(to: pluginDir, version: "1.0.0")

        let manifest = readJSON(pluginDir.appendingPathComponent(".claude-plugin/plugin.json"))
        XCTAssertEqual(manifest["name"] as? String, "claude-deck")
        let hooks = readJSON(pluginDir.appendingPathComponent("hooks/hooks.json"))
        XCTAssertNotNil(hooks["hooks"])
    }

    func testRegisterWritesAllThreeRegistryEntries() throws {
        let claude = tempClaudeDir()
        let installer = PluginInstaller(claudeDir: claude)
        let pluginDir = URL(fileURLWithPath: "/Applications/Claude Deck Mini.app/Contents/Resources/claude-deck-plugin")

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
        try installer.register(pluginDir: URL(fileURLWithPath: "/tmp/p"), version: "1.0.0")

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
        let pluginDir = URL(fileURLWithPath: "/tmp/p")

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
        try installer.register(pluginDir: URL(fileURLWithPath: "/tmp/p"), version: "1.0.0")
        try installer.unregister()

        let markets = readJSON(claude.appendingPathComponent("plugins/known_marketplaces.json"))
        XCTAssertNil(markets["claude-deck-marketplace"])
        let settings = readJSON(claude.appendingPathComponent("settings.json"))
        let enabled = settings["enabledPlugins"] as? [String: Any]
        XCTAssertNil(enabled?["claude-deck@claude-deck-marketplace"])
        XCTAssertEqual(enabled?["foo@bar"] as? Bool, true, "unrelated plugin removed")
    }
}
