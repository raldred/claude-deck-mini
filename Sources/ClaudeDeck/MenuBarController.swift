import AppKit
import DeckCore

/// The menu bar presence: an `NSStatusItem` whose title shows the waiting count,
/// with a dropdown listing each session plus actions.
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let resolver = NameResolver()

    var onInstallPlugin: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        update(waiting: 0, ordered: [])
    }

    func update(waiting: Int, ordered: [Session]) {
        if let button = statusItem.button {
            button.title = waiting > 0 ? "● \(waiting)" : "○"
        }
        statusItem.menu = buildMenu(waiting: waiting, ordered: ordered)
    }

    private func buildMenu(waiting: Int, ordered: [Session]) -> NSMenu {
        let menu = NSMenu()

        let header = waiting > 0 ? "\(waiting) waiting on you" : "No agents waiting"
        let headerItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        if ordered.isEmpty {
            let none = NSMenuItem(title: "No active sessions", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for session in ordered {
                let label = resolver.label(sessionId: session.sessionId,
                                           cwd: session.workingDirectory).text
                let age = RelativeTime.since(session.lastActivity)
                let title = "\(marker(session.status)) \(label) · \(session.status.label) · \(age)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Install / Repair Plugin…",
                     action: #selector(installPlugin), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…",
                     action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claude Deck Mini",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func marker(_ status: SessionStatus) -> String {
        switch status {
        case .waiting:  return "🔴"
        case .working:  return "🟢"
        case .idle:     return "⚪️"
        case .finished: return "⚫️"
        }
    }

    @objc private func installPlugin() { onInstallPlugin?() }
    @objc private func openSettings() { onOpenSettings?() }
}
