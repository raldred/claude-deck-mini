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

    func testHookCommandInvokesAppBinaryWithHookArg() {
        XCTAssertTrue(PluginManifest.hookCommand.contains("CLAUDE_PLUGIN_ROOT"))
        XCTAssertTrue(PluginManifest.hookCommand.hasSuffix("hook"))
        XCTAssertTrue(PluginManifest.hookCommand.contains("MacOS/ClaudeDeck"))
    }

    /// The plugin dir is `…app/Contents/Resources/claude-deck-plugin`; the binary
    /// is at `…app/Contents/MacOS/ClaudeDeck` — exactly two levels up, not three.
    func testHookCommandPathReachesBinaryFromPluginRoot() {
        XCTAssertTrue(PluginManifest.hookCommand.contains("/../../MacOS/ClaudeDeck"),
                      "hook path must be two levels up: \(PluginManifest.hookCommand)")
        XCTAssertFalse(PluginManifest.hookCommand.contains("/../../../MacOS/ClaudeDeck"),
                       "three ../ overshoots Contents: \(PluginManifest.hookCommand)")
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
