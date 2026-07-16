import Foundation

/// Reads a bounded prefix of a Claude Code transcript (`*.jsonl`) to extract a
/// human-friendly label: Claude's own auto `aiTitle`, the first real user prompt,
/// and the recorded `cwd`. Used by `NameResolver` only as a *fallback* — the
/// primary label is git-derived. Lifted from claude-depot's `TranscriptScanner`
/// (the directory-scanning `scan()` is dropped; we join by session id directly).
///
/// The on-disk transcript format is not a stable public API — isolate all
/// knowledge of it here, and stay tolerant of drift.
public enum TranscriptPrefix {
    /// Location of a session's transcript: `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`.
    /// Claude encodes the project directory by replacing `/` with `-`.
    public static func transcriptURL(sessionId: String, cwd: String,
                                     projectsRoot: URL? = nil) -> URL {
        let root = projectsRoot ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        let encoded = cwd.replacingOccurrences(of: "/", with: "-")
        return root.appendingPathComponent(encoded)
            .appendingPathComponent("\(sessionId).jsonl")
    }

    /// Wrappers Claude Code emits as a synthetic first user record (slash
    /// commands, IDE file-open notices, caveats) that aren't a human prompt and
    /// make for a useless title.
    static let syntheticPrefixes = [
        "<command-name>", "<command-message>", "<local-command-",
        "<system-reminder>", "<ide_opened_file>", "<teammate-message",
    ]

    static func isSyntheticPrefix(_ text: String) -> Bool {
        syntheticPrefixes.contains { text.hasPrefix($0) }
    }

    /// Soft target for how far into a transcript we scan for the first user
    /// message. The first prompt sits near the top, so there's no need to read
    /// multi-MB files in full.
    static let prefixReadBytes = 64 * 1024
    /// Hard ceiling while still *hunting* for the first user message, so a
    /// transcript that buries it (or never contains one) can't pull the whole
    /// multi-MB file into memory.
    static let maxHuntBytes = 1024 * 1024
    /// Once the first user message is found, keep reading this much further to
    /// catch the `ai-title` record Claude writes just after it.
    static let aiTitleGraceBytes = 32 * 1024
    static let chunkReadBytes = 64 * 1024

    /// First user message text + working directory + Claude's auto title, pulled
    /// from a bounded prefix scan. Reads *complete lines* via chunked streaming
    /// rather than a fixed byte blob — a single early record can be hundreds of
    /// KB (inline images/pasted files), and a fixed read would truncate it
    /// mid-JSON and lose the title.
    public static func parse(_ file: URL) -> (firstUserText: String?, cwd: String?, aiTitle: String?) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return (nil, nil, nil) }
        defer { try? handle.close() }

        var firstUserText: String?
        var cwd: String?
        var aiTitle: String?
        var userFoundAtBytes: Int?
        var bytesRead = 0
        var pending = Data()
        let newline = UInt8(ascii: "\n")

        func process(_ lineData: Data) {
            guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { return }

            if cwd == nil, let c = obj["cwd"] as? String, !c.isEmpty { cwd = c }

            // Last-wins: Claude appends a new record when it revises the title.
            if obj["type"] as? String == "ai-title",
               let t = (obj["aiTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !t.isEmpty {
                aiTitle = t
            }

            if firstUserText == nil, obj["type"] as? String == "user",
               // Newer Claude Code prepends injected user records (system
               // reminders, named-session notes, command caveats) flagged
               // `isMeta` before the human's first prompt. Skip them.
               obj["isMeta"] as? Bool != true,
               let message = obj["message"] as? [String: Any] {
                if let text = message["content"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !Self.isSyntheticPrefix(trimmed) { firstUserText = trimmed }
                } else if let parts = message["content"] as? [[String: Any]] {
                    let text = parts.compactMap { $0["text"] as? String }
                        .joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty && !Self.isSyntheticPrefix(text) { firstUserText = text }
                }
            }
            if firstUserText != nil, userFoundAtBytes == nil { userFoundAtBytes = bytesRead }
        }

        while true {
            let chunk = handle.readData(ofLength: chunkReadBytes)
            if chunk.isEmpty {
                if !pending.isEmpty { process(pending) }   // trailing line, no newline
                break
            }
            bytesRead += chunk.count
            pending.append(chunk)
            while let idx = pending.firstIndex(of: newline) {
                let lineData = pending.subdata(in: pending.startIndex..<idx)
                pending = pending.subdata(in: pending.index(after: idx)..<pending.endIndex)
                if !lineData.isEmpty { process(lineData) }
            }
            if firstUserText != nil {
                let target = max(prefixReadBytes, (userFoundAtBytes ?? 0) + aiTitleGraceBytes)
                if bytesRead >= target { break }
            } else if bytesRead >= maxHuntBytes {
                break
            }
        }
        return (firstUserText, cwd, aiTitle)
    }
}
