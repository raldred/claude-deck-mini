import XCTest
@testable import DeckCore

final class PluginManifestTests: XCTestCase {
    func testHooksCoverEveryTrackedEvent() {
        let hooks = PluginManifest.hooksJSON()["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks)
        for event in PluginManifest.trackedEvents {
            XCTAssertNotNil(hooks?[event], "missing hook for \(event)")
        }
        // Every tracked event must be a recognised HookEventName.
        for event in PluginManifest.trackedEvents {
            XCTAssertNotNil(HookEventName(rawValue: event), "\(event) not a known event")
        }
    }

    func testHookCommandInvokesBundledScript() {
        XCTAssertTrue(PluginManifest.hookCommand.contains("CLAUDE_PLUGIN_ROOT"))
        XCTAssertTrue(PluginManifest.hookCommand.contains("scripts/write-status"))
        XCTAssertFalse(PluginManifest.hookCommand.contains("MacOS/ClaudeDeck"),
                       "hook must not reach into the app bundle; CC caches the plugin")
    }

    func testMarketplaceListsThePlugin() {
        let m = PluginManifest.marketplaceJSON(version: "1.2.3")
        XCTAssertEqual(m["name"] as? String, "claude-deck-marketplace")
        let plugins = m["plugins"] as? [[String: Any]]
        XCTAssertEqual(plugins?.first?["name"] as? String, "claude-deck")
        XCTAssertEqual(plugins?.first?["source"] as? String, "./plugins/claude-deck")
    }

    func testPluginJSONCarriesNameAndVersion() {
        let json = PluginManifest.pluginJSON(version: "1.2.3")
        XCTAssertEqual(json["name"] as? String, "claude-deck")
        XCTAssertEqual(json["version"] as? String, "1.2.3")
    }

    func testQualifiedName() {
        XCTAssertEqual(PluginManifest.qualifiedName, "claude-deck@claude-deck-marketplace")
    }
}
