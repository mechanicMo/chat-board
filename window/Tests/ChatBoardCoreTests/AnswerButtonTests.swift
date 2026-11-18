import Foundation
import Testing
@testable import ChatBoardCore

// Mo, 2026-11-17: a question with only one or two buttons shows them on the board; anything else stays as it was.
@Suite struct AnswerButtonTests {
    private func row(_ actions: [[String: Any]]?, ask: String? = "Fix it here?", extra: [String: Any] = [:]) -> [String: Any] {
        var end: [String: Any] = ["ask": ask as Any, "recap": "r", "at": 20]
        if let actions { end["actions"] = actions }
        return ["phase": "idle", "userAt": 10, "turnEnd": end].merging(extra) { $1 }
    }

    @Test func twoReplyButtons() {
        #expect(answerButtons(row([["label": "Yes, fix it"], ["label": "Not now"]]), now: 30)
            == [AnswerButton(label: "Yes, fix it"), AnswerButton(label: "Not now")])
    }

    @Test func oneAppButtonUsesTheBoardsWord() {
        #expect(answerButtons(row([["action": "commit", "label": ""]]), now: 30) == [AnswerButton(label: "Commit", action: "commit")])
    }

    @Test func threeButtonsShowNone() {
        #expect(answerButtons(row([["label": "A"], ["label": "B"], ["label": "C"]]), now: 30).isEmpty)
    }

    @Test func noActionsOrNoQuestionShowNone() {
        #expect(answerButtons(row(nil), now: 30).isEmpty)
        #expect(answerButtons(row([]), now: 30).isEmpty)
        #expect(answerButtons(row([["label": "Yes"]], ask: nil), now: 30).isEmpty)
        #expect(answerButtons(nil, now: 30).isEmpty)
    }

    @Test func aButtonWithNothingOnItShowsNone() {
        #expect(answerButtons(row([["label": "Yes"], ["label": " "]]), now: 30).isEmpty)
    }

    @Test func aQuestionOlderThanYourLastMessageShowsNone() {
        #expect(answerButtons(row([["label": "Yes"]], extra: ["userAt": 25]), now: 30).isEmpty)
    }

    @Test func aWorkingChatOrAWaitingCardShowsNone() {
        #expect(answerButtons(row([["label": "Yes"]], extra: ["phase": "working"]), now: 30).isEmpty)
        let card: [String: Any] = ["tool": "Bash", "at": 25, "asked": true]
        #expect(answerButtons(row([["label": "Yes"]], extra: ["pending": card]), now: 30).isEmpty)
    }

    @Test func aQuestionWrittenInTheReplyShowsNone() {
        let written: [String: Any] = ["phase": "idle", "userAt": 10, "textQuestion": ["text": "Want me to?", "at": 20]]
        #expect(answerButtons(written, now: 30).isEmpty)
    }

    @Test func theChatCarriesItsButtons() throws {
        let record: [String: Any] = ["cliSessionId": "s1", "sessionId": "local_1", "title": "[x] p - t"]
        let made = try #require(chat(record: record, row: row([["label": "Yes"]]), privateFolders: [], now: 30))
        #expect(made.buttons == [AnswerButton(label: "Yes")])
    }

    @Test func pressesOnlyTheMatchingButton() {
        #expect(buttonMatches("Yes, fix it", AnswerButton(label: "Yes, fix it")))
        #expect(!buttonMatches("Yes, fix it later", AnswerButton(label: "Yes, fix it")))
        #expect(buttonMatches("Commit changes", AnswerButton(label: "Commit", action: "commit")))
        #expect(!buttonMatches("More options for Commit", AnswerButton(label: "Commit", action: "commit")))
        #expect(!buttonMatches("", AnswerButton(label: "Yes")))
    }
}
