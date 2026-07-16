import Foundation

/// Human-readable "time since" label for a session's last activity, matching the
/// Claude Status widget's format: `just now` (< 1 min), `Nm ago` (< 1 hour),
/// `Nh ago` (uncapped) — so a long wait reads e.g. `41h ago`.
public enum RelativeTime {
    public static func since(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else {
            return "\(Int(interval / 3600))h ago"
        }
    }
}
