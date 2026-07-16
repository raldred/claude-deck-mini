import AppKit
import DeckCore

/// Native settings window: brightness, paging toggle, hidden-project filter, and
/// a plugin install/repair button. Persists to `DeckPreferences`. Programmatic
/// AppKit (no storyboard/xib).
final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var prefs = DeckPreferences.load()

    private let brightnessSlider = NSSlider(value: 60, minValue: 0, maxValue: 100,
                                            target: nil, action: nil)
    private let brightnessLabel = NSTextField(labelWithString: "60%")
    private let pagingCheck = NSButton(checkboxWithTitle: "Page through more than 6 agents",
                                       target: nil, action: nil)
    private let hiddenField = NSTextField(string: "")
    private let statusPathLabel = NSTextField(labelWithString: "")

    /// Called when preferences change so the app can re-render with them.
    var onChange: ((DeckPreferences) -> Void)?
    /// Called when the user asks to install/repair the plugin.
    var onInstallPlugin: (() -> Void)?

    func show() {
        if window == nil { window = buildWindow() }
        syncControlsFromPrefs()
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    // MARK: - build

    private func buildWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Claude Deck Mini Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        // Brightness
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        let brightnessRow = labeledRow("Brightness",
                                       controls: [brightnessSlider, brightnessLabel])
        brightnessSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        stack.addArrangedSubview(brightnessRow)

        // Paging
        pagingCheck.target = self
        pagingCheck.action = #selector(pagingChanged)
        stack.addArrangedSubview(pagingCheck)

        // Hidden projects
        hiddenField.placeholderString = "repo names to hide, comma-separated"
        hiddenField.target = self
        hiddenField.action = #selector(hiddenChanged)
        hiddenField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        stack.addArrangedSubview(labeledRow("Hide projects", controls: [hiddenField]))

        // Plugin install
        let installButton = NSButton(title: "Install / Repair Plugin",
                                     target: self, action: #selector(installTapped))
        stack.addArrangedSubview(installButton)

        // Status dir path (informational)
        statusPathLabel.stringValue = "Status: \(DeckPaths.statusDir.path)"
        statusPathLabel.font = .systemFont(ofSize: 10)
        statusPathLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusPathLabel)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
        ])
        window.contentView = content
        return window
    }

    private func labeledRow(_ title: String, controls: [NSView]) -> NSStackView {
        let row = NSStackView(views: [NSTextField(labelWithString: title)] + controls)
        row.orientation = .horizontal
        row.spacing = 10
        return row
    }

    // MARK: - sync

    private func syncControlsFromPrefs() {
        brightnessSlider.integerValue = prefs.brightness
        brightnessLabel.stringValue = "\(prefs.brightness)%"
        pagingCheck.state = prefs.pagingEnabled ? .on : .off
        hiddenField.stringValue = prefs.hiddenProjects.joined(separator: ", ")
    }

    private func persist() {
        try? prefs.save()
        onChange?(prefs)
    }

    // MARK: - actions

    @objc private func brightnessChanged() {
        prefs.brightness = brightnessSlider.integerValue
        brightnessLabel.stringValue = "\(prefs.brightness)%"
        persist()
    }

    @objc private func pagingChanged() {
        prefs.pagingEnabled = pagingCheck.state == .on
        persist()
    }

    @objc private func hiddenChanged() {
        prefs.hiddenProjects = hiddenField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        persist()
    }

    @objc private func installTapped() { onInstallPlugin?() }

    // Drop back to accessory-only behaviour when settings closes.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
