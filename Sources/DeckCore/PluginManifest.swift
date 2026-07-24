import Foundation

/// Builds the two JSON documents that make up the bundled Claude Code plugin:
/// `.claude-plugin/plugin.json` and `hooks/hooks.json`. Pure builders so the
/// shape is unit-testable without touching disk.
public enum PluginManifest {
    public static let pluginName = "claude-deck"
    public static let marketplaceName = "claude-deck-marketplace"
    /// `plugin@marketplace` key used in installed_plugins.json + enabledPlugins.
    public static let qualifiedName = "\(pluginName)@\(marketplaceName)"

    /// Hook events we register. Each maps to a status in `HookEventName`.
    public static let trackedEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "Notification", "PermissionRequest", "Stop", "PreCompact", "PostCompact",
        "SessionEnd", "SubagentStart", "SubagentStop",
    ]

    /// `.claude-plugin/plugin.json` contents.
    public static func pluginJSON(version: String) -> [String: Any] {
        [
            "name": pluginName,
            "version": version,
            "description": "Reports Claude Code session status for the Claude Deck Mini "
                + "Stream Deck app",
        ]
    }

    /// The command each hook runs. `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin
    /// dir (in Claude Code's plugin cache), so the hook runs a self-contained
    /// script shipped inside the plugin — no dependency on the app bundle.
    public static let hookCommand =
        #""${CLAUDE_PLUGIN_ROOT}/scripts/write-status""#

    /// `.claude-plugin/marketplace.json` — lists the single nested plugin. Claude
    /// Code reads this to discover the plugin; without it, nothing loads.
    public static func marketplaceJSON(version: String) -> [String: Any] {
        [
            "name": marketplaceName,
            "owner": ["name": "Rob Aldred"],
            "metadata": ["description": "Claude Deck Mini — Stream Deck session status"],
            "plugins": [[
                "name": pluginName,
                "source": "./plugins/\(pluginName)",
                "description": "Reports Claude Code session status for the Claude Deck Mini "
                    + "Stream Deck app",
                "version": version,
            ]],
        ]
    }

    /// `hooks/hooks.json` contents: one group per tracked event.
    public static func hooksJSON() -> [String: Any] {
        var hooks: [String: Any] = [:]
        for event in trackedEvents {
            hooks[event] = [[
                "hooks": [["type": "command", "command": hookCommand, "timeout": 5]],
            ]]
        }
        return [
            "description": "Writes session status to ~/.claude-deck/status/<session-id>.json "
                + "for the Claude Deck Mini app",
            "hooks": hooks,
        ]
    }
}
