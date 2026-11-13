import Foundation
import Testing
@testable import ChatBoardCore

@Suite struct LayoutTests {
    static let sample = BoardLayout(
        top: [.chat("loose"), .section("work")],
        sections: ["work": TagSection(id: "work", name: "work", items: [.group("g1"), .chat("solo")], collapsed: false)],
        groups: ["g1": ProjectGroup(id: "g1", name: "orchard", chats: ["a", "b"], isManual: false)],
        manual: ["solo"], filedAs: ["a": "[work] orchard - a"])

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(Self.sample)
        #expect(try JSONDecoder().decode(BoardLayout.self, from: data) == Self.sample)
    }

    @Test func findsWhereEachThingSits() {
        let layout = Self.sample
        #expect(layout.container(of: .chat("loose")) == .top)
        #expect(layout.container(of: .chat("solo")) == .section("work"))
        #expect(layout.container(of: .chat("a")) == .group("g1"))
        #expect(layout.container(of: .group("g1")) == .section("work"))
        #expect(layout.container(of: .section("work")) == .top)
        #expect(layout.container(of: .chat("nowhere")) == nil)
    }

    @Test func aChatRecordKnowsItsFolder() {
        let chat = ChatBoardCore.chat(record: ["cliSessionId": "x", "sessionId": "local_x", "cwd": "/Users/demo/Code/orchard"],
                                      row: nil, privateFolders: [])
        #expect(chat?.folder == "orchard")
    }
}
