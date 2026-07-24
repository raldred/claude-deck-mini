import Foundation

/// Resolves a process's controlling terminal from `ps` output, so the app can
/// match a Claude session's pid to the iTerm2 session driving that tty.
public enum TtyResolver {
    /// Parse `ps -o tty= -p <pid>` output into a `/dev/<tty>` device path.
    /// `ps` prints the tty without the `/dev/` prefix (e.g. `ttys003`), or `??`
    /// when the process has no controlling terminal. Returns nil when there's no
    /// usable tty.
    public static func ttyPath(fromPS output: String) -> String? {
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line != "??", line != "?" else { return nil }
        return line.hasPrefix("/dev/") ? line : "/dev/\(line)"
    }
}
