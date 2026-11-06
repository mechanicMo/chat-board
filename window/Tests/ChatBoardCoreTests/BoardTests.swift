import Foundation
import Testing
@testable import ChatBoardCore

private func make(_ id: String, activeAt: Double = 0, parent: String? = nil, kind: Kind = .yourMove,
                  focusedAt: Double = 0, finishedAt: Double = 0, viewedAt: Double = 0) -> Chat {
    Chat(id: id, localId: "local_" + id, title: id, kind: kind, line: "", activeAt: activeAt,
         focusedAt: focusedAt, parentLocalId: parent.map { "local_" + $0 }, finishedAt: finishedAt, viewedAt: viewedAt)
}

@Suite struct ArrangeTests {
    @Test func childSitsUnderItsParentIndented() {
        let list = [make("kid", activeAt: 50, parent: "mom"), make("other", activeAt: 40), make("mom", activeAt: 10)]
        let arranged = Board.arrange(list, order: ["other", "mom"])
        #expect(arranged.map(\.id) == ["other", "mom", "kid"])
        #expect(arranged.map(\.depth) == [0, 0, 1])
    }

    @Test func orphanChildStandsAlone() {
        let arranged = Board.arrange([make("kid", parent: "gone"), make("a")], order: ["a", "kid"])
        #expect(arranged.map(\.id) == ["a", "kid"])
        #expect(arranged.allSatisfy { $0.depth == 0 })
    }

    @Test func aChatNamingItselfAsParentIsNotAChild() {
        let arranged = Board.arrange([make("self", parent: "self")], order: [])
        #expect(arranged.map(\.depth) == [0])
    }

    @Test func thePersonsOrderWinsOverActivity() {
        let list = [make("a", activeAt: 300), make("b", activeAt: 200), make("c", activeAt: 100)]
        #expect(Board.arrange(list, order: ["c", "a", "b"]).map(\.id) == ["c", "a", "b"])
    }

    @Test func newChatsGoOnTopNewestFirst() {
        let list = [make("placed", activeAt: 999), make("old", activeAt: 10), make("new", activeAt: 20)]
        #expect(Board.arrange(list, order: ["placed"]).map(\.id) == ["new", "old", "placed"])
    }

    @Test func aNewMessageDoesNotMoveAChatOnceTheBoardHasShownIt() throws {
        let first = Board.arrange([make("a", activeAt: 20), make("b", activeAt: 10)], order: [])
        let saved = try #require(Board.settledOrder(first, saved: []))
        #expect(saved == ["a", "b"])
        // b gets a new message and is now the most recent
        let later = Board.arrange([make("a", activeAt: 20), make("b", activeAt: 99)], order: saved)
        #expect(later.map(\.id) == ["a", "b"])
        #expect(Board.settledOrder(later, saved: saved) == nil)
    }

    @Test func aBrandNewChatGoesOnTopOnceAndGoneChatsKeepTheirSpot() throws {
        let list = [make("new", activeAt: 5), make("a"), make("b")]
        let arranged = Board.arrange(list, order: ["a", "gone", "b"])
        #expect(arranged.map(\.id) == ["new", "a", "b"])
        #expect(try #require(Board.settledOrder(arranged, saved: ["a", "gone", "b"])) == ["new", "a", "b", "gone"])
    }

    @Test func childrenFollowTheOrderToo() {
        let list = [make("mom"), make("k1", activeAt: 5, parent: "mom"), make("k2", activeAt: 1, parent: "mom")]
        #expect(Board.arrange(list, order: ["mom", "k2", "k1"]).map(\.id) == ["mom", "k2", "k1"])
    }
}

@Suite struct MoveGroupTests {
    // a, b (with child b1), c
    private let chats = Board.arrange([make("a"), make("b"), make("b1", parent: "b"), make("c")], order: ["a", "b", "b1", "c"])

    @Test func groupMovesWithItsSideSessions() {
        let moved = Board.moveGroup(chats, "b", before: "a")
        #expect(moved?.map(\.id) == ["b", "b1", "a", "c"])
    }

    @Test func noTargetMovesToTheEnd() {
        #expect(Board.moveGroup(chats, "a", before: nil)?.map(\.id) == ["b", "b1", "c", "a"])
    }

    @Test func theWrittenOrderReadsBackTheSame() throws {
        let moved = try #require(Board.moveGroup(chats, "c", before: "b"))
        let written = moved.map(\.id)
        #expect(written == ["a", "c", "b", "b1"])
        #expect(Board.arrange(chats, order: written).map(\.id) == written)
    }

    @Test func droppingOnItselfOrAChildIdDoesNothing() {
        #expect(Board.moveGroup(chats, "b", before: "b") == nil)
        #expect(Board.moveGroup(chats, "b1", before: "a") == nil)
    }
}

@Suite struct UnreadTests {
    @Test func finishedAfterLastViewedIsUnread() {
        let chat = make("a", finishedAt: 200, viewedAt: 100)
        #expect(Board.isUnread(chat, currentId: nil, seenAt: nil))
    }

    @Test func viewedAfterFinishingIsRead() {
        #expect(!Board.isUnread(make("a", finishedAt: 100, viewedAt: 200), currentId: nil, seenAt: nil))
    }

    @Test func clickedHereCountsAsViewed() {
        #expect(!Board.isUnread(make("a", finishedAt: 200, viewedAt: 100), currentId: nil, seenAt: 300))
    }

    @Test func theCurrentChatIsNeverUnread() {
        #expect(!Board.isUnread(make("a", finishedAt: 200, viewedAt: 100), currentId: "a", seenAt: nil))
    }

    @Test func aWorkingChatIsNeverUnread() {
        #expect(!Board.isUnread(make("a", kind: .working, finishedAt: 200, viewedAt: 100), currentId: nil, seenAt: nil))
    }

    @Test func currentIsTheMostRecentlyFocusedUnlessJustClicked() {
        let chats = [make("a", focusedAt: 10), make("b", focusedAt: 20)]
        let now = Date()
        #expect(Board.currentId(chats, clicked: nil, now: now) == "b")
        #expect(Board.currentId(chats, clicked: ("a", now.addingTimeInterval(-5)), now: now) == "a")
        #expect(Board.currentId(chats, clicked: ("a", now.addingTimeInterval(-20)), now: now) == "b")
    }
}
