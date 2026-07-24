import Foundation

/// Builds the AppleScript that brings an iTerm2 session to the front by its tty.
/// iTerm2 exposes each session's `tty` as a `/dev/ttys…` path, so we walk every
/// window/tab/session, activate the app, then select the match.
///
/// Order matters: activating iTerm2 re-fronts its previously-key window, and if
/// that happens *after* our `select` the wrong window shows (the old two-press
/// bug). Activate first so the selection is the last thing to take effect.
public enum ITermScript {
    public static func focus(tty: String) -> String {
        """
        tell application "iTerm2"
          repeat with theWindow in windows
            repeat with theTab in tabs of theWindow
              repeat with theSession in sessions of theTab
                if tty of theSession is "\(tty)" then
                  activate
                  select theWindow
                  select theTab
                  select theSession
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
    }
}
