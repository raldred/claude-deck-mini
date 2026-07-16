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
        "Notification", "PermissionRequest", "Stop", "SessionEnd",
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

    /// The command each hook runs. `${CLAUDE_PLUGIN_ROOT}` resolves to the
    /// bundled plugin dir (`…app/Contents/Resources/claude-deck-plugin`); the app
    /// binary sits three levels up at `…/Contents/MacOS/ClaudeDeck`.
    public static let hookCommand =
        #""${CLAUDE_PLUGIN_ROOT}/../../../MacOS/ClaudeDeck" hook"#

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
