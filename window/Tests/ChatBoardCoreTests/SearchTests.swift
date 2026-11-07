import Testing
@testable import ChatBoardCore

private func make(_ title: String, line: String = "", depth: Int = 0) -> Chat {
    Chat(id: title, localId: "local_" + title, title: title, kind: .yourMove, line: line, activeAt: 0, focusedAt: 0,
         depth: depth)
}

@Suite struct SearchTests {
    let board = [
        make("[client] bakery site - fix the menu", line: "Waiting on the owner's reply"),
        make("[BBM] chat board - add cmd+f search", line: "Working"),
        make("[life] groceries - plan the week", line: "Café list done", depth: 1),
    ]

    @Test func aBlankQueryKeepsTheBoard() {
        #expect(Search.filter(board, query: "") == board)
        #expect(Search.filter(board, query: "   ") == board)
    }

    @Test func matchesThroughBracketsAndCase() {
        #expect(Search.filter(board, query: "CLIENT").map(\.title) == ["[client] bakery site - fix the menu"])
    }

    @Test func everyWordHasToMatch() {
        #expect(Search.filter(board, query: "chat search").map(\.title) == ["[BBM] chat board - add cmd+f search"])
        #expect(Search.filter(board, query: "chat menu").isEmpty)
    }

    @Test func aWordCanBeTheStartOfALongerOne() {
        #expect(Search.filter(board, query: "bak").map(\.title) == ["[client] bakery site - fix the menu"])
    }

    @Test func aWordInsideAnotherWordDoesNotMatch() {
        // "ery" sits inside "bakery" but starts no word.
        #expect(Search.filter(board, query: "ery").isEmpty)
    }

    @Test func theStatusLineCountsAndAccentsAreIgnored() {
        #expect(Search.filter(board, query: "owner").map(\.title) == ["[client] bakery site - fix the menu"])
        #expect(Search.filter(board, query: "cafe").map(\.title) == ["[life] groceries - plan the week"])
    }

    @Test func aMatchingSideSessionIsShownFlat() {
        #expect(Search.filter(board, query: "groceries").map(\.depth) == [0])
    }

    @Test func nothingMatches() {
        #expect(Search.filter(board, query: "zzz").isEmpty)
    }
}
