import Foundation

/// Resolves the git context of a working directory: the *main* repository name
/// (worktree-aware) and the checked-out branch. This is the primary source for a
/// session's label — a worktree at `residently/.worktrees/feature-foo` resolves
/// to repo `residently`, branch `feature/foo`, not the worktree leaf.
public struct GitContext: Equatable {
    public let repo: String
    public let branch: String

    public init(repo: String, branch: String) {
        self.repo = repo
        self.branch = branch
    }

    /// Runs git against `cwd`. Returns nil when `cwd` isn't inside a repo (or git
    /// is unavailable). Injectable `runner` for testing without a real process.
    public static func resolve(cwd: URL, runner: GitRunner = ProcessGitRunner()) -> GitContext? {
        guard let commonDir = runner.run(
            ["-C", cwd.path, "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd: cwd)
        else { return nil }

        // The common dir is the main repo's `.git`; its parent is the main
        // working tree, whose basename is the repo name. (For a plain checkout
        // this is just `<repo>/.git` → `<repo>`.)
        let mainWorkTree = URL(fileURLWithPath: commonDir).deletingLastPathComponent()
        let repo = mainWorkTree.lastPathComponent
        guard !repo.isEmpty else { return nil }

        let branch = runner.run(["-C", cwd.path, "symbolic-ref", "--quiet", "--short", "HEAD"], cwd: cwd)
            ?? runner.run(["-C", cwd.path, "rev-parse", "--short", "HEAD"], cwd: cwd)
            ?? "detached"

        return GitContext(repo: repo, branch: branch)
    }
}

/// Runs a git invocation and returns its trimmed stdout, or nil on non-zero exit.
public protocol GitRunner {
    func run(_ args: [String], cwd: URL) -> String?
}

public struct ProcessGitRunner: GitRunner {
    public init() {}

    public func run(_ args: [String], cwd: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
