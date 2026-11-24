import Foundation
import Testing
@testable import ChatBoardCore

private func record(_ extra: [String: Any] = [:]) -> [String: Any] {
    var base: [String: Any] = ["sessionId": "local_1", "cliSessionId": "cli-1", "title": "A chat",
                               "cwd": "/Users/someone/projects/site", "lastActivityAt": 100, "lastFocusedAt": 50]
    base.merge(extra) { $1 }
    return base
}

@Suite struct RecordFilterTests {
    @Test func anOrdinaryChatIsListed() throws {
        let listed = try #require(chat(record: record(), row: nil, privateFolders: []))
        #expect(listed.id == "cli-1")
        #expect(listed.localId == "local_1")
        #expect(listed.title == "A chat")
    }

    @Test func aNameTypedInClaudesSidebarIsMarked() throws {
        #expect(try #require(chat(record: record(["titleSource": "user"]), row: nil, privateFolders: [])).nameIsPersons)
        #expect(try #require(chat(record: record(["titleSource": "tool"]), row: nil, privateFolders: [])).nameIsPersons == false)
        #expect(try #require(chat(record: record(), row: nil, privateFolders: [])).nameIsPersons == false)
    }

    @Test func archivedIsHidden() {
        #expect(chat(record: record(["isArchived": true]), row: nil, privateFolders: []) == nil)
    }

    @Test func scheduledRoutineRunIsListedAndMarked() throws {
        let run = try #require(chat(record: record(["scheduledTaskId": "task-1"]), row: nil, privateFolders: []))
        #expect(run.routineId == "task-1")
        #expect(try #require(chat(record: record(), row: nil, privateFolders: [])).routineId == nil)
    }

    @Test func anArchivedRoutineRunIsStillHidden() {
        #expect(chat(record: record(["scheduledTaskId": "task-1", "isArchived": true]), row: nil, privateFolders: []) == nil)
    }

    @Test func switchedOffRowIsHidden() {
        #expect(chat(record: record(), row: ["isOff": true], privateFolders: []) == nil)
        #expect(chat(record: record(), row: ["isOff": false], privateFolders: []) != nil)
    }

    @Test func missingIdsAreSkipped() {
        var broken = record()
        broken["cliSessionId"] = nil
        #expect(chat(record: broken, row: nil, privateFolders: []) == nil)
    }

    @Test func untitledGetsAName() {
        #expect(chat(record: record(["title": ""]), row: nil, privateFolders: [])?.title == "Untitled chat")
    }

    @Test func sideSessionKeepsItsParent() {
        let side = chat(record: record(["spawnedFrom": ["sessionId": "local_0"]]), row: nil, privateFolders: [])
        #expect(side?.parentLocalId == "local_0")
    }

    @Test func aChatDetachedToTopLevelHasNoParent() {
        let detached = chat(record: record(["spawnedFrom": ["sessionId": "local_0"], "lineageDetached": true]), row: nil, privateFolders: [])
        #expect(detached?.parentLocalId == nil)
    }

    @Test func privateFolderAndAnythingInsideItIsHidden() {
        let folders = ["/Users/someone/private"]
        #expect(chat(record: record(["cwd": "/Users/someone/private"]), row: nil, privateFolders: folders) == nil)
        #expect(chat(record: record(["cwd": "/Users/someone/private/deep/er"]), row: nil, privateFolders: folders) == nil)
    }

    @Test func aSiblingSharingThePrefixIsNotPrivate() {
        let folders = ["/Users/someone/private"]
        #expect(chat(record: record(["cwd": "/Users/someone/private-notes"]), row: nil, privateFolders: folders) != nil)
        #expect(!isPrivate(cwd: "/Users/someone/privately", privateFolders: folders))
    }
}

@Suite struct ConfigTests {
    private let home = "/Users/someone"

    @Test func tildeIsExpanded() {
        let data = Data(#"{"privateFolders": ["~/private", "~", "/abs/path/", "~/private-notes/"]}"#.utf8)
        #expect(Config.privateFolders(from: data, home: home)
                == .list(["/Users/someone/private", "/Users/someone", "/abs/path", "/Users/someone/private-notes"]))
    }

    @Test func expandedTildeHidesTheFolderButNotItsSibling() throws {
        let data = Data(#"{"privateFolders": ["~/private"]}"#.utf8)
        guard case .list(let folders) = Config.privateFolders(from: data, home: home) else { Issue.record("unreadable"); return }
        #expect(isPrivate(cwd: "/Users/someone/private/x", privateFolders: folders))
        #expect(!isPrivate(cwd: "/Users/someone/private-notes", privateFolders: folders))
    }

    @Test func noFileMeansNoPrivateFolders() {
        #expect(Config.privateFolders(from: nil, home: home) == .list([]))
        #expect(Config.privateFolders(from: Data("{}".utf8), home: home) == .list([]))
    }

    @Test func aRootOrEmptyEntryIsIgnored() {
        #expect(Config.privateFolders(from: Data(#"{"privateFolders": ["", "/"]}"#.utf8), home: home) == .list([]))
    }

    @Test func brokenJsonIsUnreadableNotEmpty() {
        #expect(Config.privateFolders(from: Data("{privateFolders: [".utf8), home: home) == .unreadable)
        #expect(Config.privateFolders(from: Data(#"{"privateFolders": "~/x"}"#.utf8), home: home) == .unreadable)
    }

    @Test func readsAFileFromDisk() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("chat-board-config-\(UUID().uuidString).json").path
        try Data(#"{"privateFolders": ["~/a"]}"#.utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(Config.privateFolders(atPath: path, home: home) == .list(["/Users/someone/a"]))
    }
}

@Suite struct ArchiveRequestTests {
    @Test func aDetachRequestNamesTheChatAndItsParent() throws {
        let request = DetachRequest(localId: "local_kid", parentLocalId: "local_mom", title: "Side", at: 5)
        #expect(request.fileName == "detach-local_kid.json")
        let data = try #require(request.data())
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(parsed["type"] as? String == "detach")
        #expect(parsed["localId"] as? String == "local_kid")
        #expect(parsed["parentLocalId"] as? String == "local_mom")
        #expect(parsed["sessionId"] == nil)
    }

    @Test func aDetachRequestAlsoNamesBothChatsBySessionId() throws {
        let request = DetachRequest(localId: "local_kid", parentLocalId: "local_mom", title: "Side",
                                    sessionId: "kid-cli", parentSessionId: "mom-cli", at: 5)
        let data = try #require(request.data())
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(parsed["sessionId"] as? String == "kid-cli")
        #expect(parsed["parentSessionId"] as? String == "mom-cli")
    }

    @Test func boardMessagesAreLoggedWithTheirTime() throws {
        let path = NSTemporaryDirectory() + "board-log-\(UUID().uuidString).log"
        defer { try? FileManager.default.removeItem(atPath: path) }
        Notice.append("Moving Side to top level...", to: path, at: Date(timeIntervalSince1970: 0))
        Notice.append("Couldn't move Side:\nopen it", to: path, at: Date(timeIntervalSince1970: 60))
        let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("  Moving Side to top level..."))
        #expect(lines[1].hasSuffix("  Couldn't move Side: open it"))
    }

    @Test func requestCarriesAFreshLongTokenAndTheRightFileName() throws {
        let request = ArchiveRequest(localId: "local_abc", title: "Old chat", at: 123)
        #expect(request.fileName == "archive-local_abc.json")
        #expect(request.token.count >= 16)
        #expect(ArchiveRequest(localId: "local_abc", title: "Old chat").token != request.token)

        let data = try #require(request.data())
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["type"] as? String == "archive")
        #expect(decoded["localId"] as? String == "local_abc")
        #expect(decoded["title"] as? String == "Old chat")
        #expect(decoded["token"] as? String == request.token)
        #expect((decoded["at"] as? NSNumber)?.doubleValue == 123)
    }

    @Test func everyLeftoverFileIsCleared() {
        #expect(ArchiveRequest.fileNames("local_abc")
                == ["archive-local_abc.json", "archive-local_abc.claimed", "archive-local_abc.result.json"])
        #expect(ArchiveRequest.resultFileName("local_abc") == "archive-local_abc.result.json")
    }
}

@Suite struct RenameRequestTests {
    @Test func aRenameRequestCarriesTheOldTitleAndTheNewName() throws {
        let request = RenameRequest(localId: "local_abc", title: "Old chat", name: "[x] demo - new task", at: 123)
        #expect(request.fileName == "rename-local_abc.json")
        let data = try #require(request.data())
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["type"] as? String == "rename")
        #expect(decoded["localId"] as? String == "local_abc")
        #expect(decoded["title"] as? String == "Old chat")
        #expect(decoded["name"] as? String == "[x] demo - new task")
        #expect(RenameRequest.fileNames("local_abc")
                == ["rename-local_abc.json", "rename-local_abc.claimed", "rename-local_abc.result.json"])
    }

    @Test func aNameIsTrimmedAndEmptyTooLongOrUnchangedIsRefused() {
        #expect(RenameRequest.cleanName("  New name \n", current: "Old") == "New name")
        #expect(RenameRequest.cleanName("   ", current: "Old") == nil)
        #expect(RenameRequest.cleanName(" Old ", current: "Old") == nil)
        #expect(RenameRequest.cleanName(String(repeating: "a", count: 201), current: "Old") == nil)
        #expect(RenameRequest.cleanName(String(repeating: "a", count: 200), current: "Old") != nil)
    }
}

// Archiving a chat makes Claude jump to another chat by itself, which stamps that chat's lastFocusedAt
// without the person looking at it (measured 2026-11-24: 64 ms after archiveSetAtMs).
@Suite struct ArchiveJumpTests {
    @Test func aFocusRightAfterAnArchiveIsNotAView() throws {
        let listed = try #require(chat(record: record(["lastFocusedAt": 10_064, "lastTurnEdgeAt": 9_000]), row: nil,
                                       privateFolders: [], archives: [10_000]))
        #expect(listed.viewedAt == 0)
        #expect(Board.isUnread(listed, currentId: nil, seenAt: nil))
    }

    @Test func theJumpKeepsTheLastRealView() throws {
        let listed = try #require(chat(record: record(["lastFocusedAt": 10_064, "lastTurnEdgeAt": 9_000]), row: nil,
                                       privateFolders: [], archives: [10_000], remembered: 9_500))
        #expect(listed.viewedAt == 9_500)
        #expect(!Board.isUnread(listed, currentId: nil, seenAt: nil))
    }

    @Test func aFocusWellAfterAnArchiveStillCounts() throws {
        let listed = try #require(chat(record: record(["lastFocusedAt": 20_000, "lastTurnEdgeAt": 9_000]), row: nil,
                                       privateFolders: [], archives: [10_000]))
        #expect(listed.viewedAt == 20_000)
    }

    @Test func archiveTimesComeFromArchivedRecordsOnly() {
        let times = archiveTimes([record(["isArchived": true, "archiveSetAtMs": 7]), record(["archiveSetAtMs": 8]),
                                  record(["isArchived": true])])
        #expect(times == [7])
    }
}
