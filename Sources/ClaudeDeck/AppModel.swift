import AppKit
import DeckCore
import Foundation

/// The app's brain: watches the status dir (FSEvents + poll fallback), folds it
/// into sessions, resolves names, lays out the 6 keys for the current page, and
/// pushes the render to the deck. Handles key presses (paging only in v1).
final class AppModel {
    private let statusStore: StatusFileStore
    private let resolver = NameResolver()
    private let bridge: DeckdBridge
    private var prefs: DeckPreferences

    private(set) var sessions = SessionStore()
    private var page = 0

    /// Called after each refresh so the menu bar can update its title/list.
    var onChange: ((_ waiting: Int, _ ordered: [Session]) -> Void)?

    private var pollTimer: Timer?
    private var eventStream: FSEventStreamRef?

    init(bridge: DeckdBridge = DeckdBridge(),
         statusStore: StatusFileStore = StatusFileStore(directory: DeckPaths.statusDir),
         prefs: DeckPreferences = DeckPreferences.load()) {
        self.bridge = bridge
        self.statusStore = statusStore
        self.prefs = prefs
    }

    func start() {
        // Ensure the status dir exists so the watcher has something to watch.
        try? FileManager.default.createDirectory(
            at: DeckPaths.statusDir, withIntermediateDirectories: true)

        bridge.onKeyDown = { [weak self] index in self?.handleKeyDown(index) }
        bridge.onReady = { [weak self] _, _ in self?.render() }
        bridge.start()

        startWatching()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stop() {
        pollTimer?.invalidate()
        stopWatching()
        bridge.clear()
        bridge.stop()
    }

    /// Apply changed preferences (from the settings window) and re-render.
    func apply(_ newPrefs: DeckPreferences) {
        prefs = newPrefs
        clampPage()
        render()
    }

    // MARK: - refresh / render

    /// Sessions to actually show: hidden projects filtered out.
    private var visibleSessions: [Session] {
        guard !prefs.hiddenProjects.isEmpty else { return sessions.sessions }
        let hidden = Set(prefs.hiddenProjects)
        return sessions.sessions.filter { !hidden.contains($0.projectGroup) }
    }

    private func refresh() {
        var updated = SessionStore()
        StatusEngine.refresh(store: statusStore, into: &updated)
        sessions = updated
        clampPage()
        render()
        let ordered = visibleSessions.sorted(by: SessionOrdering.precedes)
        let waiting = ordered.filter { $0.status == .waiting }.count
        onChange?(waiting, ordered)
    }

    private func render() {
        // Paging off → cap at the first keyCount sessions (no "more" key).
        let keyCount = 6
        let source = prefs.pagingEnabled ? visibleSessions : Array(visibleSessions.prefix(keyCount))
        let keys = DeckLayout.keys(for: source, page: page,
                                   now: Date(), resolver: resolver, keyCount: keyCount)
        bridge.render(keys: keys, brightness: prefs.brightness)
    }

    // MARK: - paging / key presses

    private func handleKeyDown(_ index: Int) {
        // Only the "more" key (last key, when in overflow) does anything in v1.
        let source = prefs.pagingEnabled ? visibleSessions : Array(visibleSessions.prefix(6))
        let keys = DeckLayout.keys(for: source, page: page,
                                   now: Date(), resolver: resolver)
        guard index < keys.count, case .more = keys[index].kind else { return }
        page += 1
        clampPage()
        render()
    }

    private var pageCount: Int {
        guard prefs.pagingEnabled else { return 1 }
        let count = visibleSessions.count
        guard count > 6 else { return 1 }
        let perPage = 5
        return (count + perPage - 1) / perPage
    }

    private func clampPage() {
        let pages = pageCount
        page = pages > 0 ? ((page % pages) + pages) % pages : 0
    }

    // MARK: - FSEvents

    private func startWatching() {
        let path = DeckPaths.statusDir.path as CFString
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let model = Unmanaged<AppModel>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { model.refresh() }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    private func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }
}
