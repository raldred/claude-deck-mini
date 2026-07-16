import XCTest
@testable import DeckCore

final class TranscriptPrefixTests: XCTestCase {
    private func writeTranscript(_ lines: [String]) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-transcript-\(UUID().uuidString).jsonl")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testTranscriptURLEncodesCwd() {
        let root = URL(fileURLWithPath: "/root")
        let url = TranscriptPrefix.transcriptURL(
            sessionId: "abc", cwd: "/Users/rob/Code/foo", projectsRoot: root)
        XCTAssertEqual(url.path, "/root/-Users-rob-Code-foo/abc.jsonl")
    }

    func testExtractsFirstUserPromptAndCwd() {
        let file = writeTranscript([
            #"{"type":"user","cwd":"/work/foo","message":{"content":"Fix the login bug"}}"#,
        ])
        let parsed = TranscriptPrefix.parse(file)
        XCTAssertEqual(parsed.firstUserText, "Fix the login bug")
        XCTAssertEqual(parsed.cwd, "/work/foo")
    }

    func testAiTitleWinsAndIsLastWins() {
        let file = writeTranscript([
            #"{"type":"user","message":{"content":"do a thing"}}"#,
            #"{"type":"ai-title","aiTitle":"First guess"}"#,
            #"{"type":"ai-title","aiTitle":"Refined title"}"#,
        ])
        let parsed = TranscriptPrefix.parse(file)
        XCTAssertEqual(parsed.aiTitle, "Refined title")
        XCTAssertEqual(parsed.firstUserText, "do a thing")
    }

    func testSkipsMetaAndSyntheticRecordsForFirstPrompt() {
        let file = writeTranscript([
            #"{"type":"user","isMeta":true,"message":{"content":"<system-reminder>ignore me"}}"#,
            #"{"type":"user","message":{"content":"<command-name>/foo"}}"#,
            #"{"type":"user","message":{"content":"the real prompt"}}"#,
        ])
        let parsed = TranscriptPrefix.parse(file)
        XCTAssertEqual(parsed.firstUserText, "the real prompt")
    }

    func testHandlesArrayContentParts() {
        let file = writeTranscript([
            #"{"type":"user","message":{"content":[{"type":"text","text":"hello"},{"type":"text","text":"world"}]}}"#,
        ])
        let parsed = TranscriptPrefix.parse(file)
        XCTAssertEqual(parsed.firstUserText, "hello world")
    }

    func testMissingFileReturnsNils() {
        let parsed = TranscriptPrefix.parse(URL(fileURLWithPath: "/nope/missing.jsonl"))
        XCTAssertNil(parsed.firstUserText)
        XCTAssertNil(parsed.cwd)
        XCTAssertNil(parsed.aiTitle)
    }
}
