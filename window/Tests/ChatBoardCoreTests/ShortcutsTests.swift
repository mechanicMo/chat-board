import Testing
@testable import ChatBoardCore

private func make(_ id: String) -> Chat {
    Chat(id: id, localId: "local_" + id, title: id, kind: .yourMove, line: "", activeAt: 0, focusedAt: 0, depth: 0)
}

@Suite struct ShortcutsTests {
    let visible = (1...11).map { make("c\($0)") }

    @Test func theNumberKeysReadAsOneToNine() {
        #expect([18, 19, 20, 21, 23, 22, 26, 28, 25].map { Shortcuts.number(forKeyCode: $0) } == Array(1...9))
        #expect(Shortcuts.number(forKeyCode: 29) == nil)   // 0
        #expect(Shortcuts.number(forKeyCode: 2) == nil)    // D
    }

    @Test func onlyTheFirstNineChatsGetANumber() {
        let numbers = Shortcuts.numbers(visible)
        #expect(numbers.count == 9)
        #expect(numbers["c1"] == 1)
        #expect(numbers["c9"] == 9)
        #expect(numbers["c10"] == nil)
    }

    @Test func aNumberOpensTheChatAtThatSpot() {
        #expect(Shortcuts.chat(1, in: visible)?.id == "c1")
        #expect(Shortcuts.chat(9, in: visible)?.id == "c9")
        #expect(Shortcuts.chat(3, in: Array(visible.prefix(2))) == nil)
        #expect(Shortcuts.chat(0, in: visible) == nil)
    }
}
