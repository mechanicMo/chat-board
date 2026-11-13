import CoreGraphics
import Testing
@testable import ChatBoardCore

// A board drawn top to bottom: a loose chat, the "work" section (a card and two loose chats), then a loose chat.
private let slots: [DropSlot] = [
    DropSlot(node: .chat("top1"), container: .top, frame: CGRect(x: 0, y: 0, width: 300, height: 40)),
    DropSlot(node: .section("work"), container: .top, frame: CGRect(x: 0, y: 50, width: 300, height: 200)),
    DropSlot(node: .group("g"), container: .section("work"), frame: CGRect(x: 0, y: 80, width: 300, height: 80)),
    DropSlot(node: .chat("w1"), container: .section("work"), frame: CGRect(x: 0, y: 160, width: 300, height: 40)),
    DropSlot(node: .chat("w2"), container: .section("work"), frame: CGRect(x: 0, y: 200, width: 300, height: 40)),
    DropSlot(node: .chat("top2"), container: .top, frame: CGRect(x: 0, y: 260, width: 300, height: 40)),
]

@Suite struct DropTests {
    @Test func theSmallestThingUnderThePointerIsWhatGetsPicked() {
        #expect(Drop.pick(at: CGPoint(x: 10, y: 170), slots: slots) == .chat("w1"))
        #expect(Drop.pick(at: CGPoint(x: 10, y: 60), slots: slots) == .section("work"))
        #expect(Drop.pick(at: CGPoint(x: 10, y: 45), slots: slots) == nil)
    }

    @Test func aChatOverTheMiddleOfACardJoinsIt() {
        #expect(Drop.target(for: .chat("top1"), at: CGPoint(x: 10, y: 120), slots: slots) == .into("g"))
    }

    @Test func aChatOverTheEdgeOfACardGoesBesideIt() {
        #expect(Drop.target(for: .chat("top1"), at: CGPoint(x: 10, y: 84), slots: slots) == .place(.section("work"), before: .group("g")))
    }

    @Test func aChatOverTheMiddleOfALooseChatMakesAGroup() {
        #expect(Drop.target(for: .chat("top1"), at: CGPoint(x: 10, y: 220), slots: slots) == .combine("w2"))
    }

    @Test func aChatOverTheTopEdgeOfARowGoesBeforeIt() {
        #expect(Drop.target(for: .chat("top1"), at: CGPoint(x: 10, y: 203), slots: slots) == .place(.section("work"), before: .chat("w2")))
    }

    @Test func belowEverythingInASectionGoesToItsEnd() {
        #expect(Drop.target(for: .chat("top1"), at: CGPoint(x: 10, y: 245), slots: slots) == .place(.section("work"), before: nil))
    }

    @Test func outsideEverySectionGoesToTheTopLevel() {
        #expect(Drop.target(for: .chat("w1"), at: CGPoint(x: 10, y: 262), slots: slots) == .place(.top, before: .chat("top2")))
        #expect(Drop.target(for: .chat("w1"), at: CGPoint(x: 10, y: 400), slots: slots) == .place(.top, before: nil))
    }

    @Test func aCardNeverJoinsOrCombines() {
        #expect(Drop.target(for: .group("g"), at: CGPoint(x: 10, y: 220), slots: slots) == .place(.section("work"), before: .chat("w2")))
        #expect(Drop.target(for: .group("g"), at: CGPoint(x: 10, y: 280), slots: slots) == .place(.top, before: .chat("top2")))
    }

    @Test func aSectionOnlyMovesAmongTopLevelThings() {
        #expect(Drop.target(for: .section("work"), at: CGPoint(x: 10, y: 5), slots: slots) == .place(.top, before: .chat("top1")))
        #expect(Drop.target(for: .section("work"), at: CGPoint(x: 10, y: 290), slots: slots) == .place(.top, before: nil))
    }

    @Test func droppingAChatOnItselfDoesNothing() {
        #expect(Drop.target(for: .chat("w1"), at: CGPoint(x: 10, y: 180), slots: slots) == nil)
    }

    @Test func onAProjectPageChatsReorderWithinTheGroup() {
        let page = [DropSlot(node: .chat("a"), container: .group("g"), frame: CGRect(x: 0, y: 0, width: 300, height: 40)),
                    DropSlot(node: .chat("b"), container: .group("g"), frame: CGRect(x: 0, y: 40, width: 300, height: 40))]
        #expect(Drop.target(for: .chat("b"), at: CGPoint(x: 10, y: 10), slots: page) == .place(.group("g"), before: .chat("a")))
        #expect(Drop.target(for: .chat("a"), at: CGPoint(x: 10, y: 75), slots: page) == .place(.group("g"), before: nil))
    }

    @Test func applyingATargetMovesThroughTheSameRules() throws {
        let layout = BoardLayout(top: [.chat("top1"), .section("work")],
                                 sections: ["work": TagSection(id: "work", name: "work", items: [.group("g"), .chat("w1")])],
                                 groups: ["g": ProjectGroup(id: "g", name: "orchard", chats: ["a"])])
        let joined = Drop.apply(layout, .chat("top1"), .into("g"), name: { _ in "x" })
        #expect(joined.groups["g"]?.chats == ["a", "top1"])
        let combined = Drop.apply(layout, .chat("top1"), .combine("w1"), name: { _ in "pair" })
        #expect(try #require(combined.groups.values.first { $0.name == "pair" }).chats == ["w1", "top1"])
    }
}
