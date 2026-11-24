import Foundation
import Testing
@testable import ChatBoardCore

private func chat(_ id: String, _ kind: Kind = .working, depth: Int = 0) -> Chat {
    Chat(id: id, localId: "local_" + id, title: id, kind: kind, line: "", activeAt: 0, focusedAt: 0, depth: depth)
}

// A parent chat with its side chats folds like a group (Mo, 2026-11-24).
@Suite struct FamilyTests {
    private let empty = BoardLayout()

    @Test func smallFamiliesStartOpenAndBigOnesStartFolded() {
        let two = [chat("a", depth: 1), chat("b", depth: 1)]
        let three = two + [chat("c", depth: 1)]
        #expect(!Family.block(chat("p"), children: two, layout: empty).folded)
        #expect(Family.block(chat("p"), children: three, layout: empty).folded)
    }

    @Test func aChatWithNoSideChatsIsNeverFolded() {
        let layout = BoardLayout(families: ["p": true])
        #expect(!Family.block(chat("p"), children: [], layout: layout).folded)
    }

    // The parent is always shown in full; folding hides only its side chats, and the bar counts only them.
    @Test func foldedShowsOnlyTheParentAndCountsTheSideChats() {
        let kids = [chat("w", depth: 1), chat("m", .yourMove, depth: 1), chat("q", .question, depth: 1),
                    chat("r", .ready, depth: 1)]
        let block = Family.block(chat("p", .ready), children: kids, layout: empty)
        #expect(block.folded)
        #expect(Family.rows(block).map(\.id) == ["p"])
        #expect(block.counts == [.working: 1, .question: 1, .ready: 1, .yourMove: 1])
    }

    @Test func openShowsTheParentThenEverySideChat() {
        let kids = [chat("a", depth: 1), chat("b", .ready, depth: 1)]
        #expect(Family.rows(Family.block(chat("p"), children: kids, layout: empty)).map(\.id) == ["p", "a", "b"])
    }

    @Test func toggleOverridesTheDefaultBothWays() {
        let opened = Moves.toggleFamily(empty, parent: "p", childCount: 5)
        #expect(opened.families == ["p": false])
        #expect(!Family.isFolded("p", childCount: 5, layout: opened))
        let folded = Moves.toggleFamily(empty, parent: "p", childCount: 1)
        #expect(Family.isFolded("p", childCount: 1, layout: folded))
        #expect(!Family.isFolded("p", childCount: 1, layout: Moves.toggleFamily(folded, parent: "p", childCount: 1)))
    }

    @Test func splitsACardsFlatListBackIntoFamilies() {
        let list = [chat("a"), chat("a1", depth: 1), chat("a2", depth: 1), chat("b"), chat("c"), chat("c1", depth: 1)]
        let blocks = Family.split(list, layout: empty)
        #expect(blocks.map(\.parent.id) == ["a", "b", "c"])
        #expect(blocks.map { $0.children.map(\.id) } == [["a1", "a2"], [], ["c1"]])
    }

    @Test func survivesASaveAndLoad() throws {
        let layout = Moves.toggleFamily(empty, parent: "p", childCount: 4)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(BoardLayout.self, from: data) == layout)
    }

    // layout.json files saved before families existed have no "families" key and must still load.
    @Test func loadsALayoutSavedBeforeFamilies() throws {
        let old = #"{"top":[],"sections":{},"groups":{},"manual":[],"filedAs":{},"priorities":{},"folded":["g"]}"#
        let layout = try JSONDecoder().decode(BoardLayout.self, from: Data(old.utf8))
        #expect(layout.families.isEmpty)
        #expect(layout.folded == ["g"])
    }
}
