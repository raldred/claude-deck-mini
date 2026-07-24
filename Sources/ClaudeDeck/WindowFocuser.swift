import DeckCore
import Foundation

/// Brings the iTerm2 session running a given Claude pid to the front. Best-effort:
/// resolve the pid's controlling tty, then ask iTerm2 (via osascript) to select
/// the session whose tty matches and activate. Any failure — dead pid, no tty,
/// no match, Automation permission denied — is a silent no-op; a key press must
/// never error.
final class WindowFocuser {
    private let runProcess: (_ launchPath: String, _ args: [String]) -> String?

    init(runProcess: @escaping (_ launchPath: String, _ args: [String]) -> String?
         = WindowFocuser.shell) {
        self.runProcess = runProcess
    }

    /// Runs the `ps`/`osascript` shell-outs off the main thread: the first call
    /// blocks until the user answers the macOS Automation permission dialog, and
    /// a key press must never freeze the menu bar UI.
    func focus(pid: Int?) {
        guard let pid else { return }
        DispatchQueue.global(qos: .userInitiated).async { [runProcess] in
            guard let psOut = runProcess("/bin/ps", ["-o", "tty=", "-p", String(pid)]),
                  let tty = TtyResolver.ttyPath(fromPS: psOut) else { return }
            _ = runProcess("/usr/bin/osascript", ["-e", ITermScript.focus(tty: tty)])
        }
    }

    private static func shell(_ launchPath: String, _ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
