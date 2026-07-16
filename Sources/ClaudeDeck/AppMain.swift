import AppKit

/// Entry point for the menu bar app. Boots a programmatic `NSApplication` as an
/// accessory (no Dock icon, menu bar only) and hands off to `AppDelegate`.
enum AppMain {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
