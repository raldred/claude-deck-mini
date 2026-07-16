import XCTest
@testable import DeckCore

private struct StubGitRunner: GitRunner {
    var isRepo: Bool
    func run(_ args: [String], cwd: URL) -> String? {
        guard isRepo else { return nil }
        if args.contains("--git-common-dir") { return "\(cwd.path)/.git" }
        if args.contains("symbolic-ref") { return "main" }
        return nil
    }
}

final class NameResolverTests: XCTestCase {
    func testGitRepoYieldsRepoBranchLabel() {
        let resolver = NameResolver(gitRunner: StubGitRunner(isRepo: true))
        let label = resolver.label(sessionId: "s1",
                                   cwd: URL(fileURLWithPath: "/Users/rob/Code/residently"))
        XCTAssertEqual(label, .repoBranch(repo: "residently", branch: "main"))
        XCTAssertEqual(label.text, "residently · main")
    }

    func testNonGitCwdFallsBackToBasename() {
        let resolver = NameResolver(gitRunner: StubGitRunner(isRepo: false))
        let label = resolver.label(sessionId: "s1",
                                   cwd: URL(fileURLWithPath: "/Users/rob/Documents/notes"))
        XCTAssertEqual(label, .plain("notes"))
    }

    func testNilCwdYieldsSessionIdPlaceholder() {
        let resolver = NameResolver(gitRunner: StubGitRunner(isRepo: false))
        let label = resolver.label(sessionId: "abcdef123456", cwd: nil)
        XCTAssertEqual(label, .plain("abcdef12"))
    }

    func testLabelIsCachedAfterFirstResolve() {
        // First call resolves as a git repo; if we then flip the runner to
        // non-git and call again, the cached git label must still be returned.
        final class Flip: GitRunner {
            var repo = true
            func run(_ args: [String], cwd: URL) -> String? {
                guard repo else { return nil }
                if args.contains("--git-common-dir") { return "\(cwd.path)/.git" }
                if args.contains("symbolic-ref") { return "main" }
                return nil
            }
        }
        let flip = Flip()
        let resolver = NameResolver(gitRunner: flip)
        let cwd = URL(fileURLWithPath: "/Users/rob/Code/foo")

        let first = resolver.label(sessionId: "s1", cwd: cwd)
        flip.repo = false
        let second = resolver.label(sessionId: "s1", cwd: cwd)

        XCTAssertEqual(first, second)
        XCTAssertEqual(second, .repoBranch(repo: "foo", branch: "main"))
    }

    func testRefreshRecomputesLabel() {
        final class Flip: GitRunner {
            var repo = true
            func run(_ args: [String], cwd: URL) -> String? {
                guard repo else { return nil }
                if args.contains("--git-common-dir") { return "\(cwd.path)/.git" }
                if args.contains("symbolic-ref") { return "main" }
                return nil
            }
        }
        let flip = Flip()
        let resolver = NameResolver(gitRunner: flip)
        let cwd = URL(fileURLWithPath: "/Users/rob/Code/foo")

        _ = resolver.label(sessionId: "s1", cwd: cwd)
        flip.repo = false
        let refreshed = resolver.refresh(sessionId: "s1", cwd: cwd)

        XCTAssertEqual(refreshed, .plain("foo"))
    }
}
