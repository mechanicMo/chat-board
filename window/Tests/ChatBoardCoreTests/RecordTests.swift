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

    @Test func archivedIsHidden() {
        #expect(chat(record: record(["isArchived": true]), row: nil, privateFolders: []) == nil)
    }

    @Test func scheduledRoutineRunIsHidden() {
        #expect(chat(record: record(["scheduledTaskId": "task-1"]), row: nil, privateFolders: []) == nil)
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
