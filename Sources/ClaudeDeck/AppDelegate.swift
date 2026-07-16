import AppKit
import DeckCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let menu = MenuBarController()
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.onOpenSettings = { [weak self] in self?.openSettings() }
        menu.onInstallPlugin = { [weak self] in self?.installPlugin() }

        model.onChange = { [weak self] waiting, ordered in
            self?.menu.update(waiting: waiting, ordered: ordered)
        }
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    private func openSettings() {
        // Accessory apps don't get key focus for free — activate so the window
        // behaves like a normal focused window, then drop back on close.
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil { settingsWindow = SettingsWindow() }
        settingsWindow?.show()
    }

    private func installPlugin() {
        let installer = PluginInstaller()
        guard let pluginDir = Self.bundledPluginDir() else {
            notify("Plugin not found in app bundle. Run scripts/install.sh.")
            return
        }
        do {
            try installer.register(pluginDir: pluginDir, version: Self.appVersion)
            notify("Plugin installed. Start a new Claude Code session to activate it.")
        } catch {
            notify("Plugin install failed: \(error.localizedDescription)")
        }
    }

    /// `…app/Contents/Resources/claude-deck-plugin` when running bundled.
    static func bundledPluginDir() -> URL? {
        let dir = Bundle.main.resourceURL?.appendingPathComponent("claude-deck-plugin")
        if let dir, FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(".claude-plugin/plugin.json").path) {
            return dir
        }
        return nil
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private func notify(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Claude Deck Mini"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
