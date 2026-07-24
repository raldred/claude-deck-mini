import Foundation

/// Builds the AppleScript that brings an iTerm2 session to the front by its tty.
/// iTerm2 exposes each session's `tty` as a `/dev/ttys…` path, so we walk every
/// window/tab/session and select the first match, then activate the app.
public enum ITermScript {
    public static func focus(tty: String) -> String {
        """
        tell application "iTerm2"
          repeat with theWindow in windows
            repeat with theTab in tabs of theWindow
              repeat with theSession in sessions of theTab
                if tty of theSession is "\(tty)" then
                  select theWindow
                  select theTab
                  select theSession
                  activate
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
    }
}
