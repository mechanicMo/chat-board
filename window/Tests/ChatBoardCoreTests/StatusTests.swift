import Foundation
import Testing
@testable import ChatBoardCore

// The cases the mod's tests also run, so the band in a chat and the board never disagree.
// The file is TypeScript for the mod's runner; everything after `export default` is plain JSON.
private func sharedCases() throws -> (now: Double, cases: [[String: Any]]) {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("../fixtures/describe-cases.ts").standardized
    let text = try String(contentsOf: url, encoding: .utf8)
    let marker = try #require(text.range(of: "export default "))
    var body = String(text[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    if body.hasSuffix(";") { body.removeLast() }
    let object = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
    let cases = try #require(object["cases"] as? [[String: Any]])
    return ((object["now"] as? NSNumber)?.doubleValue ?? 0, cases)
}

@Suite struct DescribeTests {
    @Test func everySharedCase() throws {
        let (now, cases) = try sharedCases()
        #expect(cases.count >= 14)
        for item in cases {
            let name = item["name"] as? String ?? "?"
            let (kind, line) = describe(item["row"] as? [String: Any], now: now)
            #expect(kind.rawValue == item["kind"] as? String, "\(name)")
            #expect(line == item["line"] as? String, "\(name)")
        }
    }

    @Test func kindNamesMatchTheMod() {
        #expect(Kind.allCases.map(\.rawValue) == ["question", "your_move", "ready", "working"])
    }

    @Test func noRowIsYourMoveWithNothingToSay() {
        let (kind, line) = describe(nil, now: 0)
        #expect(kind == .yourMove)
        #expect(line == "")
    }

    @Test func summaryReadyToClose() {
        let row: [String: Any] = ["phase": "idle", "userAt": 10,
                                  "summary": ["status": "ready_to_close", "next": "Nothing left.", "updatedAt": 20]]
        #expect(describe(row, now: 30) == (.ready, "Nothing left."))
    }
}

@Suite struct WaitingLabelTests {
    @Test func cardToolUsesItsOwnWords() {
        #expect(toolLabel("mcp__ccd_session_mgmt__set_session_title") == "rename this chat")
        #expect(toolLabel("AskUserQuestion") == "answer a question")
    }

    @Test func mcpToolDropsTheServerAndUnderscores() {
        #expect(toolLabel("mcp__notes__save_note") == "save note")
        #expect(toolLabel("mcp__computer-use__app_click") == "app click")
    }

    @Test func plainToolAsItIs() {
        #expect(toolLabel("Bash") == "Bash")
        #expect(toolLabel("mcp__broken") == "mcp__broken")
    }

    @Test func askedIsWaitingAtOnce() {
        #expect(waitingOn(["tool": "Bash", "at": 1000, "asked": true], now: 1000) == "Bash")
    }

    @Test func noPendingIsNotWaiting() {
        #expect(waitingOn(nil, now: 0) == nil)
        #expect(waitingOn(["at": 0], now: 100_000) == nil)
    }
}
