import XCTest
@testable import DeckCore

/// Fake runner returning canned output per git subcommand (matched loosely by a
/// keyword in the args), so we can test resolution logic without a real repo.
private struct FakeGitRunner: GitRunner {
    var responses: [String: String?]
    func run(_ args: [String], cwd: URL) -> String? {
        if args.contains("--git-common-dir") { return responses["common"] ?? nil }
        if args.contains("symbolic-ref") { return responses["branch"] ?? nil }
        if args.contains("rev-parse") { return responses["sha"] ?? nil }
        return nil
    }
}

final class GitContextTests: XCTestCase {
    func testPlainCheckoutUsesRepoNameAndBranch() {
        let runner = FakeGitRunner(responses: [
            "common": "/Users/rob/Code/residently/.git",
            "branch": "main",
        ])
        let ctx = GitContext.resolve(cwd: URL(fileURLWithPath: "/Users/rob/Code/residently"),
                                     runner: runner)
        XCTAssertEqual(ctx, GitContext(repo: "residently", branch: "main"))
    }

    func testWorktreeFoldsToMainRepoName() {
        // A linked worktree's common dir points back at the MAIN repo's .git, so
        // the repo name is the main repo, not the worktree leaf.
        let runner = FakeGitRunner(responses: [
            "common": "/Users/rob/Code/residently/.git",
            "branch": "feature/foo",
        ])
        let ctx = GitContext.resolve(
            cwd: URL(fileURLWithPath: "/Users/rob/Code/residently/.worktrees/feature-foo"),
            runner: runner)
        XCTAssertEqual(ctx, GitContext(repo: "residently", branch: "feature/foo"))
    }

    func testDetachedHeadFallsBackToShortSha() {
        let runner = FakeGitRunner(responses: [
            "common": "/Users/rob/Code/foo/.git",
            "branch": nil,       // symbolic-ref fails when detached
            "sha": "a1b2c3d",
        ])
        let ctx = GitContext.resolve(cwd: URL(fileURLWithPath: "/Users/rob/Code/foo"),
                                     runner: runner)
        XCTAssertEqual(ctx, GitContext(repo: "foo", branch: "a1b2c3d"))
    }

    func testNilWhenNotARepo() {
        let runner = FakeGitRunner(responses: ["common": nil])
        XCTAssertNil(GitContext.resolve(cwd: URL(fileURLWithPath: "/tmp"), runner: runner))
    }

    // Integration: exercise the real ProcessGitRunner against a temp repo + a
    // real linked worktree, proving the worktree folds to the main repo name.
    func testRealRepoAndWorktreeResolution() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-git-\(UUID().uuidString)")
        let repo = base.appendingPathComponent("myrepo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        func git(_ args: [String], in dir: URL) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["git", "-C", dir.path] + args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run(); p.waitUntilExit()
        }

        try git(["init", "-b", "main"], in: repo)
        try git(["config", "user.email", "t@t.com"], in: repo)
        try git(["config", "user.name", "t"], in: repo)
        try git(["commit", "--allow-empty", "-m", "init"], in: repo)

        let ctx = GitContext.resolve(cwd: repo)
        XCTAssertEqual(ctx?.repo, "myrepo")
        XCTAssertEqual(ctx?.branch, "main")

        // Add a linked worktree on a new branch, resolve from inside it.
        let wt = base.appendingPathComponent("wt-feature")
        try git(["worktree", "add", "-b", "feature/x", wt.path], in: repo)

        let wtCtx = GitContext.resolve(cwd: wt)
        XCTAssertEqual(wtCtx?.repo, "myrepo", "worktree should fold to main repo name")
        XCTAssertEqual(wtCtx?.branch, "feature/x")

        try? FileManager.default.removeItem(at: base)
    }
}
