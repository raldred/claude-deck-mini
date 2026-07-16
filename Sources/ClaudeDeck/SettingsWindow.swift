import AppKit

/// Native settings window. Fully built in task 11; minimal shell here so the app
/// wiring (task 10) compiles and the menu's Settings… item opens something.
final class SettingsWindow {
    private var window: NSWindow?

    func show() {
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Claude Deck Mini Settings"
        window.isReleasedWhenClosed = false
        return window
    }
}
