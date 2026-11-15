import Foundation
import Testing
@testable import ChatBoardCore

@Suite struct PriorityTests {
    @Test func lowIsSmallerAndHighIsBigger() {
        #expect(Priority.low.scale == 0.85)
        #expect(Priority.medium.scale == 1)
        #expect(Priority.high.scale == 1.3)
    }

    @Test func everythingStartsMedium() {
        let layout = BoardLayout()
        #expect(layout.priority(of: .chat("a")) == .medium)
        #expect(layout.priority(of: .group("g")) == .medium)
    }

    @Test func settingAndClearingAPriority() {
        let high = Moves.setPriority(BoardLayout(), .chat("a"), to: .high)
        #expect(high.priority(of: .chat("a")) == .high)
        // A chat and a group with the same id never share a size.
        #expect(high.priority(of: .group("a")) == .medium)
        let back = Moves.setPriority(high, .chat("a"), to: .medium)
        #expect(back == BoardLayout())
    }

    @Test func survivesASaveAndLoad() throws {
        let layout = Moves.setPriority(BoardLayout(), .group("g"), to: .low)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(BoardLayout.self, from: data) == layout)
    }

    // layout.json files saved before priorities existed have no "priorities" key and must still load.
    @Test func loadsALayoutSavedBeforePriorities() throws {
        let old = #"{"top":[],"sections":{},"groups":{},"manual":[],"filedAs":{}}"#
        let layout = try JSONDecoder().decode(BoardLayout.self, from: Data(old.utf8))
        #expect(layout == BoardLayout())
    }
}
