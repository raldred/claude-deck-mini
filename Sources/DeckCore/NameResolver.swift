import Foundation

/// The label shown for a session, either a git `repo · branch` pair (rendered as
/// two lines on a key) or a single plain string.
public enum DeckLabel: Equatable {
    case repoBranch(repo: String, branch: String)
    case plain(String)

    /// Single-line form for the menu bar and logs.
    public var text: String {
        switch self {
        case let .repoBranch(repo, branch): return "\(repo) · \(branch)"
        case let .plain(s): return s
        }
    }
}

/// Resolves a session's display label, fixing depot's "mobile-app-5e" problem by
/// keying off the accurate `cwd` the hook always supplies. Priority:
///   1. `<repo> · <branch>` from git (worktree-aware)
///   2. cwd basename (not a git repo)
///   3. transcript aiTitle / first prompt (only when cwd is unavailable)
///
/// Results are cached by session id so key rendering never blocks on git IO.
/// (`/name-session` override is a documented future addition — see the plan.)
public final class NameResolver {
    private let gitRunner: GitRunner
    private let projectsRoot: URL?
    private var cache: [String: DeckLabel] = [:]

    public init(gitRunner: GitRunner = ProcessGitRunner(), projectsRoot: URL? = nil) {
        self.gitRunner = gitRunner
        self.projectsRoot = projectsRoot
    }

    /// Cached label for a session. Computes and stores on first request.
    public func label(sessionId: String, cwd: URL?) -> DeckLabel {
        if let cached = cache[sessionId] { return cached }
        let resolved = compute(sessionId: sessionId, cwd: cwd)
        cache[sessionId] = resolved
        return resolved
    }

    /// Recompute one session's label (e.g. its branch changed). Overwrites cache.
    @discardableResult
    public func refresh(sessionId: String, cwd: URL?) -> DeckLabel {
        let resolved = compute(sessionId: sessionId, cwd: cwd)
        cache[sessionId] = resolved
        return resolved
    }

    public func forget(sessionId: String) { cache[sessionId] = nil }

    private func compute(sessionId: String, cwd: URL?) -> DeckLabel {
        if let cwd {
            if let git = GitContext.resolve(cwd: cwd, runner: gitRunner) {
                return .repoBranch(repo: git.repo, branch: git.branch)
            }
            return .plain(cwd.lastPathComponent)
        }
        // No cwd from the hook — last resort, read the transcript. Without cwd we
        // can't locate the transcript by the normal path, so this only yields a
        // label if a caller later supplies one; return a stable placeholder.
        return .plain(String(sessionId.prefix(8)))
    }

    /// Fallback label from a transcript file directly (used when cwd is known but
    /// a caller wants the aiTitle/first-prompt instead of the git label).
    public func transcriptLabel(for file: URL) -> DeckLabel? {
        let parsed = TranscriptPrefix.parse(file)
        if let title = parsed.aiTitle ?? parsed.firstUserText {
            return .plain(String(title.prefix(60)))
        }
        return nil
    }
}
