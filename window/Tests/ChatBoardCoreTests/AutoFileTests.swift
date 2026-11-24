import Foundation
import Testing
@testable import ChatBoardCore

private func chat(_ id: String, _ title: String, activeAt: Double = 0, parent: String? = nil, folder: String = "") -> Chat {
    Chat(id: id, localId: "local_" + id, title: title, kind: .yourMove, line: "", activeAt: activeAt, focusedAt: 0,
         parentLocalId: parent.map { "local_" + $0 }, folder: folder)
}

private func groupNamed(_ layout: BoardLayout, _ name: String) -> ProjectGroup? {
    layout.groups.values.first { $0.name == name }
}

@Suite struct AutoFileTests {
    @Test func aTaggedChatGoesToTheTopOfTheBoardWithNoSection() {
        let layout = AutoFile.update(BoardLayout(top: [.chat("old")]), chats: [chat("old", "Untitled"), chat("a", "[Work] orchard - pick")])
        #expect(layout.top == [.chat("a"), .chat("old")])
        #expect(layout.sections.isEmpty)
    }

    @Test func savedSectionsFoldOntoTheBoardInPlace() {
        let start = BoardLayout(top: [.chat("x"), .section("work"), .chat("y")],
                                sections: ["work": TagSection(id: "work", name: "work", items: [.group("g"), .chat("solo")])],
                                groups: ["g": ProjectGroup(id: "g", name: "mine", chats: ["a", "b"], isManual: true)],
                                manual: ["a", "b", "x", "y", "solo"])
        let chats = [chat("x", "x"), chat("y", "y"), chat("solo", "[work] mill - s"), chat("a", "a"), chat("b", "b")]
        let layout = AutoFile.update(start, chats: chats)
        #expect(layout.top == [.chat("x"), .group("g"), .chat("solo"), .chat("y")])
        #expect(layout.sections.isEmpty)
    }

    @Test func oneProjectUnderTwoTagsIsOneCard() throws {
        let layout = AutoFile.update(BoardLayout(), chats: [chat("a", "[client] orchard - a"), chat("b", "[home] orchard - b")])
        #expect(try #require(groupNamed(layout, "orchard")).chats.count == 2)
        #expect(layout.top.count == 1)
    }

    @Test func anUntaggedChatGoesToTheTopOfTheBoard() {
        let layout = AutoFile.update(BoardLayout(top: [.chat("old")]), chats: [chat("old", "x"), chat("new", "Untitled chat")])
        #expect(layout.top == [.chat("new"), .chat("old")])
    }

    @Test func twoChatsSharingAProjectFormAGroupWhereTheUpperOneWas() throws {
        let start = BoardLayout(top: [.chat("solo"), .chat("a")],
                                filedAs: ["solo": "[work] mill - x", "a": "[work] Orchard - pick"])
        let chats = [chat("solo", "[work] mill - x"), chat("a", "[work] Orchard - pick"), chat("b", "[work] orchard - paint")]
        let layout = AutoFile.update(start, chats: chats)
        let group = try #require(groupNamed(layout, "orchard"))
        #expect(layout.top == [.group(group.id), .chat("solo")])
        #expect(group.chats == ["b", "a"])
        #expect(!group.isManual)
    }

    @Test func oneChatAloneStaysLoose() {
        let layout = AutoFile.update(BoardLayout(), chats: [chat("a", "[work] orchard - pick")])
        #expect(layout.groups.isEmpty)
        #expect(layout.top == [.chat("a")])
    }

    @Test func aProjectThatExtendsAGroupNameJoinsIt() throws {
        let start = AutoFile.update(BoardLayout(), chats: [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b")])
        let layout = AutoFile.update(start, chats: [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b"),
                                                   chat("c", "[work] orchard games - memory match")])
        #expect(try #require(groupNamed(layout, "orchard")).chats.first == "c")
    }

    @Test func theColonFormJoinsAMatchingGroup() throws {
        let start = AutoFile.update(BoardLayout(), chats: [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b")])
        let layout = AutoFile.update(start, chats: [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b"),
                                                   chat("c", "Orchard: write guides")])
        #expect(try #require(groupNamed(layout, "orchard")).chats.contains("c"))
    }

    @Test func aFolderMatchingAGroupJoinsIt() throws {
        let start = AutoFile.update(BoardLayout(), chats: [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b")])
        let layout = AutoFile.update(start, chats: [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b"),
                                                   chat("c", "Untitled chat", folder: "Orchard")])
        #expect(try #require(groupNamed(layout, "orchard")).chats.contains("c"))
    }

    @Test func aChatMovedByHandNeverMovesOrJoinsAGroup() {
        let start = BoardLayout(top: [.chat("a"), .chat("b")], manual: ["a"], filedAs: ["a": "old", "b": "[work] orchard - b"])
        let layout = AutoFile.update(start, chats: [chat("a", "[work] orchard - renamed"), chat("b", "[work] orchard - b")])
        #expect(layout.top.contains(.chat("a")))
        #expect(layout.groups.isEmpty)
    }

    @Test func aRenameReFilesAChatThatWasAutoFiled() {
        let start = AutoFile.update(BoardLayout(), chats: [chat("a", "Untitled chat")])
        #expect(start.top == [.chat("a")])
        let layout = AutoFile.update(start, chats: [chat("a", "[home] garage - shelves")])
        #expect(layout.filedAs["a"] == "[home] garage - shelves")
        #expect(layout.top == [.chat("a")])
    }

    @Test func aNewTaskInTheSameProjectKeepsTheChatsSpot() throws {
        let chats = [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b"), chat("c", "[work] orchard - c"),
                     chat("x", "[work] mill - x"), chat("y", "[work] barn - y")]
        let start = AutoFile.update(BoardLayout(), chats: chats)
        let renamed = chats.map { $0.id == "c" ? chat("c", "[work] orchard - new task") : $0.id == "y" ? chat("y", "[work] barn - next") : $0 }
        let layout = AutoFile.update(start, chats: renamed)
        #expect(try #require(groupNamed(layout, "orchard")).chats == groupNamed(start, "orchard")?.chats)
        #expect(layout.top == start.top)
        #expect(layout.filedAs["c"] == "[work] orchard - new task")
    }

    // Capture renames a chat "cap [tag] project - task"; it must stay in its project's group (Mo, 2026-11-24).
    @Test func aCaptureMarkerKeepsTheChatInItsGroup() throws {
        let start = AutoFile.update(BoardLayout(), chats: [chat("a", "[BBM] ankur - one"), chat("b", "[BBM] ankur - two")])
        let renamed = AutoFile.update(start, chats: [chat("a", "cap [BBM] ankur - one"), chat("b", "[BBM] ankur - two")])
        #expect(try #require(groupNamed(renamed, "ankur")).chats == ["a", "b"])
    }

    @Test func anAutoGroupBelowTwoChatsDissolvesInPlace() throws {
        let start = AutoFile.update(BoardLayout(), chats: [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b")])
        #expect(start.groups.count == 1)
        let layout = AutoFile.update(start, chats: [chat("a", "[work] orchard - a")])
        #expect(layout.groups.isEmpty)
        #expect(layout.top.contains(.chat("a")))
    }

    @Test func aManualGroupWithOneChatStaysAndWithNoneGoes() {
        let group = ProjectGroup(id: "g", name: "mine", chats: ["a", "b"], isManual: true)
        let start = BoardLayout(top: [.group("g")], groups: ["g": group], manual: ["a", "b"])
        let one = AutoFile.update(start, chats: [chat("a", "x")])
        #expect(one.groups["g"] != nil)
        let none = AutoFile.update(start, chats: [chat("z", "Untitled")])
        #expect(none.groups["g"] == nil)
        #expect(!none.top.contains(.group("g")))
    }

    @Test func sideSessionsAreNeverPlaced() {
        let layout = AutoFile.update(BoardLayout(), chats: [chat("mom", "[work] orchard - a"), chat("kid", "[work] orchard - b", parent: "mom")])
        #expect(!layout.placedChats.contains("kid"))
        #expect(layout.groups.isEmpty)
    }

    @Test func migratingKeepsTheOldFlatOrder() {
        let chats = [chat("a", "one", activeAt: 1), chat("b", "two", activeAt: 2), chat("c", "three", activeAt: 3)]
        let layout = AutoFile.update(BoardLayout(), chats: chats, priorOrder: ["b", "a", "c"])
        #expect(layout.top == [.chat("b"), .chat("a"), .chat("c")])
    }

    @Test func runningTwiceChangesNothing() {
        let chats = [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b"), chat("c", "[home] dog - walk"), chat("d", "x")]
        let once = AutoFile.update(BoardLayout(), chats: chats)
        #expect(AutoFile.update(once, chats: chats) == once)
    }
}
