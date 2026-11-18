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

// Mo, 2026-11-17: orange chats that are only waiting on a go-ahead get one button too.
@Suite struct GoAheadButtonTests {
    private func row(goAhead: Any? = "merge the branch", isDone: Bool = false, at: Double = 20, extra: [String: Any] = [:]) -> [String: Any] {
        var verdict: [String: Any] = ["isDone": isDone, "left": "Mo to OK the merge.", "purpose": "p", "at": at]
        if let goAhead { verdict["goAhead"] = goAhead }
        return ["phase": "idle", "userAt": 10, "verdict": verdict].merging(extra) { $1 }
    }

    @Test func anOrangeChatWithAGoAheadShowsOneButton() {
        let made = rowButtons(row(), now: 30)
        #expect(made == [AnswerButton(label: "Go ahead: merge the branch", reply: "Go ahead: merge the branch", since: 20)])
    }

    @Test func noGoAheadShowsNone() {
        #expect(rowButtons(row(goAhead: nil), now: 30).isEmpty)
        #expect(rowButtons(row(goAhead: "  "), now: 30).isEmpty)
        #expect(rowButtons(row(goAhead: 5), now: 30).isEmpty)
    }

    @Test func aDoneOrOldReportShowsNone() {
        #expect(rowButtons(row(isDone: true), now: 30).isEmpty)
        #expect(rowButtons(row(extra: ["userAt": 25]), now: 30).isEmpty)
    }

    @Test func aQuestionWorkOrACardWinsOverTheGoAhead() {
        #expect(rowButtons(row(extra: ["phase": "working"]), now: 30).isEmpty)
        #expect(rowButtons(row(extra: ["pending": ["tool": "Bash", "at": 25, "asked": true]]), now: 30).isEmpty)
        #expect(rowButtons(row(extra: ["textQuestion": ["text": "Want me to?", "at": 20]]), now: 30).isEmpty)
        let asked = row(extra: ["turnEnd": ["ask": "Fix it?", "recap": "r", "actions": [["label": "Yes"]], "at": 20]])
        #expect(rowButtons(asked, now: 30) == [AnswerButton(label: "Yes")])
        let askedNoButtons = row(extra: ["turnEnd": ["ask": "Fix it?", "recap": "r", "at": 20]])
        #expect(rowButtons(askedNoButtons, now: 30).isEmpty)
    }

    @Test func theChatCarriesItsGoAhead() throws {
        let record: [String: Any] = ["cliSessionId": "s1", "sessionId": "local_1", "title": "[x] p - t"]
        let made = try #require(chat(record: record, row: row(), privateFolders: [], now: 30))
        #expect(made.kind == .yourMove)
        #expect(made.buttons.map(\.reply) == ["Go ahead: merge the branch"])
    }
}

@Suite struct ReplyGateTests {
    private let records: [[String: Any]] = [["sessionId": "local_a", "lastFocusedAt": 100.0], ["sessionId": "local_b", "lastFocusedAt": 300.0]]

    @Test func onlyTheMostRecentlyFocusedChatIsOpen() {
        #expect(isFrontChat("local_b", records: records))
        #expect(!isFrontChat("local_a", records: records))
        #expect(!isFrontChat("local_missing", records: records))
        #expect(!isFrontChat("local_a", records: []))
    }

    @Test func aButtonIsStillGoodOnlyWhileTheChatSaysTheSame() {
        let verdict: [String: Any] = ["isDone": false, "left": "l", "purpose": "p", "at": 20.0, "goAhead": "merge it"]
        let row: [String: Any] = ["phase": "idle", "userAt": 10.0, "verdict": verdict]
        let button = goAheadButtons(row, now: 30)[0]
        #expect(stillOffered(button, row: row, now: 30))
        #expect(!stillOffered(button, row: row.merging(["userAt": 25.0]) { $1 }, now: 30))
        #expect(!stillOffered(button, row: row.merging(["phase": "working"]) { $1 }, now: 30))
        var newer = verdict; newer["at"] = 22.0
        #expect(!stillOffered(button, row: row.merging(["verdict": newer]) { $1 }, now: 30))
        #expect(!stillOffered(button, row: nil, now: 30))
    }
}
