import Testing
@testable import ChatBoardCore

private func chat(_ id: String, _ kind: Kind = .yourMove, parent: String? = nil) -> Chat {
    Chat(id: id, localId: "local_" + id, title: id, kind: kind, line: "", activeAt: 0, focusedAt: 0,
         parentLocalId: parent.map { "local_" + $0 })
}

@Suite struct TreeTests {
    static let layout = BoardLayout(
        top: [.chat("loose"), .section("work"), .section("empty"), .chat("gone")],
        sections: ["work": TagSection(id: "work", name: "Work", items: [.group("g"), .chat("solo")]),
                   "empty": TagSection(id: "empty", name: "empty", items: [.chat("gone2")])],
        groups: ["g": ProjectGroup(id: "g", name: "orchard", chats: ["a", "b", "c", "absent"])])

    static let chats = [chat("loose"), chat("solo", .ready), chat("a", .working), chat("b", .question),
                        chat("c", .ready), chat("kid", .working, parent: "a")]

    // A side session started from a side session used to vanish: it was filed under its own parent, which is
    // itself drawn as a child, so nothing ever drew it.
    @Test func aGrandchildIsDrawnUnderItsTopChat() {
        let layout = BoardLayout(top: [.chat("top")], sections: [:], groups: [:])
        let chats = [chat("top"), chat("kid", parent: "top"), chat("grandkid", parent: "kid")]
        let tree = Tree.build(layout, chats: chats)
        guard tree.count == 1, case .entry(.chat(let top, let children)) = tree[0] else {
            Issue.record("unexpected shape: \(tree)")
            return
        }
        #expect(top.id == "top")
        #expect(children.map(\.id) == ["kid", "grandkid"])
        #expect(children.map(\.depth) == [1, 1])
    }

    @Test func skipsClosedChatsAndEmptySections() {
        let tree = Tree.build(Self.layout, chats: Self.chats)
        #expect(tree.count == 2)
        guard case .entry(.chat(let loose, _)) = tree[0], case .section(let work) = tree[1] else {
            Issue.record("unexpected shape: \(tree)")
            return
        }
        #expect(loose.id == "loose")
        #expect(work.name == "Work")
        #expect(work.entries.count == 2)
    }

    @Test func aCardRollsUpItsChats() throws {
        let tree = Tree.build(Self.layout, chats: Self.chats)
        guard case .section(let work) = tree[1], case .group(let card) = work.entries[0] else {
            Issue.record("no card")
            return
        }
        #expect(card.chats.map(\.id) == ["a", "kid", "b", "c"])
        #expect(card.chats.map(\.depth) == [0, 1, 0, 0])
        #expect(card.counts[.question] == 1)
        #expect(card.counts[.working] == 2)
        #expect(card.lead?.id == "b")
        #expect(work.counts[.ready] == 2)
    }

    @Test func aCardWithOnlyWorkingChatsHasNoLead() {
        let card = Tree.card(ProjectGroup(id: "g", name: "x", chats: ["a"]), chats: ["a": chat("a", .working)], children: [:])
        #expect(card?.lead == nil)
    }

    @Test func theProjectPageKeepsThePersonsOrderWhateverTheStatus() throws {
        let card = try #require(Tree.card(ProjectGroup(id: "g", name: "x", chats: ["a", "d", "b", "c"]),
                                          chats: Dictionary(uniqueKeysWithValues: (Self.chats + [chat("d", .yourMove)]).map { ($0.id, $0) }),
                                          children: ["local_a": [chat("kid", .working, parent: "a")]]))
        #expect(card.chats.map(\.id) == ["a", "kid", "d", "b", "c"])
    }
}
