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
    @Test func aTaggedChatGoesToTheTopOfANewSection() {
        let layout = AutoFile.update(BoardLayout(top: [.chat("old")]), chats: [chat("old", "Untitled"), chat("a", "[Work] orchard - pick")])
        #expect(layout.top == [.section("work"), .chat("old")])
        #expect(layout.sections["work"]?.name == "Work")
        #expect(layout.sections["work"]?.items == [.chat("a")])
    }

    @Test func anUntaggedChatGoesToTheTopOfTheBoard() {
        let layout = AutoFile.update(BoardLayout(top: [.chat("old")]), chats: [chat("old", "x"), chat("new", "Untitled chat")])
        #expect(layout.top == [.chat("new"), .chat("old")])
    }

    @Test func twoChatsSharingAProjectFormAGroupWhereTheUpperOneWas() throws {
        let start = BoardLayout(top: [.section("work")],
                                sections: ["work": TagSection(id: "work", name: "work", items: [.chat("solo"), .chat("a")])],
                                filedAs: ["solo": "[work] mill - x", "a": "[work] Orchard - pick"])
        let chats = [chat("solo", "[work] mill - x"), chat("a", "[work] Orchard - pick"), chat("b", "[work] orchard - paint")]
        let layout = AutoFile.update(start, chats: chats)
        let group = try #require(groupNamed(layout, "orchard"))
        #expect(layout.sections["work"]?.items == [.group(group.id), .chat("solo")])
        #expect(group.chats == ["b", "a"])
        #expect(!group.isManual)
    }

    @Test func oneChatAloneStaysLoose() {
        let layout = AutoFile.update(BoardLayout(), chats: [chat("a", "[work] orchard - pick")])
        #expect(layout.groups.isEmpty)
        #expect(layout.sections["work"]?.items == [.chat("a")])
    }

    @Test func aProjectThatExtendsAGroupNameJoinsIt() throws {
        let start = AutoFile.update(BoardLayout(), chats: [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b")])
        let layout = AutoFile.update(start, chats: [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b"),
                                                   chat("c", "[work] orchard games - memory match")])
        #expect(try #require(groupNamed(layout, "orchard")).chats.first == "c")
    }

    @Test func theColonFormJoinsAMatchingGroupInAnySection() throws {
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
        #expect(layout.sections["home"]?.items == [.chat("a")])
        #expect(!layout.top.contains(.chat("a")))
    }

    @Test func aNewTaskInTheSameProjectKeepsTheChatsSpot() throws {
        let chats = [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b"), chat("c", "[work] orchard - c"),
                     chat("x", "[work] mill - x"), chat("y", "[work] barn - y")]
        let start = AutoFile.update(BoardLayout(), chats: chats)
        let renamed = chats.map { $0.id == "c" ? chat("c", "[work] orchard - new task") : $0.id == "y" ? chat("y", "[work] barn - next") : $0 }
        let layout = AutoFile.update(start, chats: renamed)
        #expect(try #require(groupNamed(layout, "orchard")).chats == groupNamed(start, "orchard")?.chats)
        #expect(layout.sections["work"]?.items == start.sections["work"]?.items)
        #expect(layout.filedAs["c"] == "[work] orchard - new task")
    }

    @Test func anAutoGroupBelowTwoChatsDissolvesInPlace() throws {
        let start = AutoFile.update(BoardLayout(), chats: [chat("a", "[work] orchard - a"), chat("b", "[work] orchard - b")])
        #expect(start.groups.count == 1)
        let layout = AutoFile.update(start, chats: [chat("a", "[work] orchard - a")])
        #expect(layout.groups.isEmpty)
        #expect(layout.sections["work"]?.items.contains(.chat("a")) == true)
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
