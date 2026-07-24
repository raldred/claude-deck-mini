import Foundation

/// The `claude-deck hook` entry point: read the hook JSON Claude Code pipes on
/// stdin and update the status files. Kept in DeckCore so it's unit-testable
/// without spawning a process.
public enum HookCommand {
    /// Apply one hook payload to the store. An `ended` event (session ended)
    /// removes the status file rather than leaving a tombstone — the deck only
    /// shows live sessions. Returns the event applied, or nil if ignored.
    @discardableResult
    public static func handle(jsonData: Data, store: StatusFileStore,
                              now: Date) throws -> StatusEvent? {
        guard let event = try HookHandler.makeEvent(jsonData: jsonData, now: now) else { return nil }
        if event.status == .ended {
            try store.removeFile(sessionId: event.sessionId)
        } else {
            try store.write(event)
        }
        return event
    }

    /// Read all of stdin and apply it. Always returns without throwing to the
    /// caller's process boundary concern — a hook must never block or fail
    /// Claude Code, so `run()` swallows errors and the caller exits 0.
    public static func run(input: FileHandle = .standardInput,
                           store: StatusFileStore = StatusFileStore(directory: DeckPaths.statusDir),
                           now: Date = Date()) {
        let data = input.readDataToEndOfFile()
        guard !data.isEmpty else { return }
        try? handle(jsonData: data, store: store, now: now)
    }
}
