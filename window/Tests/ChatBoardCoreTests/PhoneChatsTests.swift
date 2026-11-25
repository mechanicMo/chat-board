import Foundation
import Testing
@testable import ChatBoardCore

// A transcript line in the shape Claude writes: a tool result whose text is the rename tool's JSON answer.
private func renameLine(id: String, title: String, cwd: String = "/Users/me/work") -> Substring {
    let ccr: [String: Any] = ["ccr": ["id": id, "title": title, "session_status": "SESSION_STATUS_RUNNING"]]
    let answer = String(decoding: try! JSONSerialization.data(withJSONObject: ccr), as: UTF8.self)
    let object: [String: Any] = [
        "type": "user", "cwd": cwd,
        "message": ["role": "user", "content": [["tool_use_id": "toolu_1", "type": "tool_result",
                                                  "content": [["type": "text", "text": answer]]]]],
    ]
    let data = try! JSONSerialization.data(withJSONObject: object)
    return Substring(String(decoding: data, as: UTF8.self))
}

private func errorLine() -> Substring {
    let object: [String: Any] = [
        "type": "user", "cwd": "/Users/me/work",
        "message": ["role": "user", "content": [["tool_use_id": "toolu_2", "type": "tool_result", "is_error": true,
                                                  "content": [["type": "text", "text": "The person declined the rename."]]]]],
    ]
    return Substring(String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self))
}

private let ps = """
COMMAND
/Applications/Claude.app/Contents/MacOS/Claude
/Users/me/.local/share/claude/versions/2.1.326 --print --sdk-url https://api.anthropic.com/v1/code/sessions/cse_01AbC --session-id cse_01AbC --input-format stream-json
/Users/me/.local/share/claude/versions/2.1.326 --print --session-id 4b0c2f1e-0000-4000-8000-000000000000
"""

@Suite struct PhoneChatsTests {
    @Test func liveSessionsComeFromSdkProcessesOnly() {
        #expect(PhoneChats.liveSessions(ps: ps) == ["session_01AbC"])
    }

    @Test func titleIsTheLatestRenameTheServerConfirmed() {
        var seen = PhoneChats.Seen()
        PhoneChats.read(lines: [renameLine(id: "session_01AbC", title: "[BBM] demo - first"),
                                renameLine(id: "session_01AbC", title: "[BBM] demo - \"second\" name", cwd: "/Users/me/work/app"),
                                errorLine()], into: &seen)
        #expect(seen == PhoneChats.Seen(sessionId: "session_01AbC", title: "[BBM] demo - \"second\" name", cwd: "/Users/me/work"))
    }

    @Test func aChatShowsOnlyWhileItsProcessRuns() {
        var seen = PhoneChats.Seen()
        PhoneChats.read(lines: [renameLine(id: "session_01AbC", title: "[life] demo - phone chat")], into: &seen)
        let record = PhoneChats.record(cliSessionId: "cli-1", seen: seen, live: ["session_01AbC"], lastActivityAt: 5)
        #expect(record?["sessionId"] as? String == "session_01AbC")
        #expect(record?["title"] as? String == "[life] demo - phone chat")
        #expect(PhoneChats.record(cliSessionId: "cli-1", seen: seen, live: ["session_other"], lastActivityAt: 5) == nil)
        // Fed through the same path as the app's own records, it becomes a chat that opens by its session_ id
        // and renames through Claude's menu.
        let made = chat(record: record!, row: ["phase": "idle"], privateFolders: [])
        #expect(made?.localId == "session_01AbC")
        #expect(made?.nameIsPersons == true)
    }

    @Test func anUnnamedChatHasNoRecord() {
        var seen = PhoneChats.Seen()
        PhoneChats.read(lines: [errorLine()], into: &seen)
        #expect(PhoneChats.record(cliSessionId: "cli-1", seen: seen, live: ["session_01AbC"], lastActivityAt: 5) == nil)
    }
}
