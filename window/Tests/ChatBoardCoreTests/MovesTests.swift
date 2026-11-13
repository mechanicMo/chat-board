import Testing
@testable import ChatBoardCore

@Suite struct MovesTests {
    static let start = BoardLayout(
        top: [.chat("loose"), .section("work"), .section("home")],
        sections: ["work": TagSection(id: "work", name: "work", items: [.group("g"), .chat("solo")]),
                   "home": TagSection(id: "home", name: "home", items: [.chat("dog")])],
        groups: ["g": ProjectGroup(id: "g", name: "orchard", chats: ["a", "b"])])

    @Test func reordersWithinAContainerAndMarksTheChatAsPlacedByHand() {
        let layout = Moves.move(Self.start, .chat("solo"), to: .section("work"), before: .group("g"))
        #expect(layout.sections["work"]?.items == [.chat("solo"), .group("g")])
        #expect(layout.manual.contains("solo"))
    }

    @Test func movingIntoAGroupMarksTheGroupManual() {
        let layout = Moves.move(Self.start, .chat("dog"), to: .group("g"), before: nil)
        #expect(layout.groups["g"]?.chats == ["a", "b", "dog"])
        #expect(layout.groups["g"]?.isManual == true)
        #expect(layout.sections["home"]?.items == [])
    }

    @Test func sectionsOnlyMoveAtTheTopLevel() {
        #expect(Moves.move(Self.start, .section("home"), to: .section("work"), before: nil) == Self.start)
        let layout = Moves.move(Self.start, .section("home"), to: .top, before: .chat("loose"))
        #expect(layout.top == [.section("home"), .chat("loose"), .section("work")])
    }

    @Test func aGroupNeverGoesInsideAGroup() {
        #expect(Moves.move(Self.start, .group("g"), to: .group("g"), before: nil) == Self.start)
    }

    @Test func aGroupCanLeaveItsSection() {
        let layout = Moves.move(Self.start, .group("g"), to: .top, before: nil)
        #expect(layout.top.last == .group("g"))
        #expect(layout.groups["g"]?.isManual == true)
    }

    @Test func droppingAChatOnAnotherMakesAGroupInItsPlace() throws {
        let layout = Moves.makeGroup(Self.start, dropping: "dog", onto: "solo", name: "chores")
        let group = try #require(layout.groups.values.first { $0.name == "chores" })
        #expect(group.chats == ["solo", "dog"])
        #expect(group.isManual)
        #expect(layout.sections["work"]?.items == [.group("g"), .group(group.id)])
        #expect(layout.manual.isSuperset(of: ["solo", "dog"]))
    }

    @Test func ungroupLeavesTheChatsWhereTheGroupWas() {
        let layout = Moves.ungroup(Self.start, "g")
        #expect(layout.sections["work"]?.items == [.chat("a"), .chat("b"), .chat("solo")])
        #expect(layout.groups["g"] == nil)
        #expect(layout.manual.isSuperset(of: ["a", "b"]))
    }

    @Test func renamingMarksTheGroupManual() {
        let layout = Moves.rename(Self.start, group: "g", to: "Orchard app")
        #expect(layout.groups["g"]?.name == "Orchard app")
        #expect(layout.groups["g"]?.isManual == true)
    }

    @Test func togglesASectionOpenAndShut() {
        let shut = Moves.toggleCollapsed(Self.start, section: "work")
        #expect(shut.sections["work"]?.collapsed == true)
        #expect(Moves.toggleCollapsed(shut, section: "work").sections["work"]?.collapsed == false)
    }
}
