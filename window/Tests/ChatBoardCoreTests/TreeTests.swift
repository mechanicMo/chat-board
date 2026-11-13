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

    @Test func theProjectPageGroupsByStatusAndKeepsTheOrder() throws {
        let tree = Tree.build(Self.layout, chats: Self.chats + [chat("d", .yourMove)])
        _ = tree
        let card = try #require(Tree.card(ProjectGroup(id: "g", name: "x", chats: ["a", "d", "b", "c"]),
                                          chats: Dictionary(uniqueKeysWithValues: (Self.chats + [chat("d", .yourMove)]).map { ($0.id, $0) }),
                                          children: ["local_a": [chat("kid", .working, parent: "a")]]))
        let page = Tree.page(card)
        #expect(page.map(\.title) == ["Needs you", "Ready to close", "Working"])
        #expect(page[0].chats.map(\.id) == ["d", "b"])
        #expect(page[2].chats.map(\.id) == ["a", "kid"])
    }
}
