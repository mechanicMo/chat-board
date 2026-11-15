import Foundation
import Testing
@testable import ChatBoardCore

// A project card on the board is open in place (its chats showing) unless the person folds it (Mo, 2026-11-14).
@Suite struct ExpandTests {
    private var withGroup: BoardLayout {
        BoardLayout(top: [.group("g")], groups: ["g": ProjectGroup(id: "g", name: "ankur", chats: ["a", "b"])])
    }

    @Test func startsOpenAndFoldsAndReopens() {
        #expect(withGroup.folded.isEmpty)
        let folded = Moves.toggleExpanded(withGroup, group: "g")
        #expect(folded.folded == ["g"])
        #expect(Moves.toggleExpanded(folded, group: "g") == withGroup)
    }

    @Test func ignoresAGroupThatIsGone() {
        #expect(Moves.toggleExpanded(withGroup, group: "nope") == withGroup)
    }

    @Test func ungroupingForgetsIt() {
        let folded = Moves.toggleExpanded(withGroup, group: "g")
        #expect(Moves.ungroup(folded, "g").folded.isEmpty)
    }

    @Test func survivesASaveAndLoad() throws {
        let folded = Moves.toggleExpanded(withGroup, group: "g")
        let data = try JSONEncoder().encode(folded)
        #expect(try JSONDecoder().decode(BoardLayout.self, from: data) == folded)
    }

    // layout.json files saved before this existed have no "folded" key and must still load, every card open.
    @Test func loadsALayoutSavedBeforeFolding() throws {
        let old = #"{"top":[],"sections":{},"groups":{},"manual":[],"filedAs":{},"priorities":{},"expanded":["g"]}"#
        #expect(try JSONDecoder().decode(BoardLayout.self, from: Data(old.utf8)).folded.isEmpty)
    }
}
