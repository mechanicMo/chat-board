import Testing
@testable import ChatBoardCore

@Suite struct TitleParseTests {
    @Test func readsTagProjectAndTask() {
        #expect(TitleParse.parse("[work] orchard - pick characters")
                == ParsedTitle(tag: "work", project: "orchard", task: "pick characters"))
    }

    @Test func aDoubleDashAlsoSeparates() {
        #expect(TitleParse.parse("[work] orchard games -- memory match").project == "orchard games")
    }

    @Test func onlyTheFirstDashSplitsSoTheTaskKeepsItsOwn() {
        let parsed = TitleParse.parse("[work] orchard - step 1 - then 2")
        #expect(parsed.project == "orchard")
        #expect(parsed.task == "step 1 - then 2")
    }

    @Test func theColonFormHasAProjectButNoTag() {
        #expect(TitleParse.parse("Orchard: write parent guides")
                == ParsedTitle(tag: nil, project: "Orchard", task: "write parent guides"))
    }

    @Test func aTagWithoutASeparatorHasNoProject() {
        #expect(TitleParse.parse("[work] just a note") == ParsedTitle(tag: "work", project: nil, task: "just a note"))
    }

    @Test func aPlainTitleHasNothing() {
        #expect(TitleParse.parse("Untitled chat") == ParsedTitle(tag: nil, project: nil, task: "Untitled chat"))
    }

    @Test func aLongSentenceWithAColonIsNotAProject() {
        #expect(TitleParse.parse("Why does the build fail on the second run: a note").project == nil)
    }

    @Test func keysIgnoreCaseAndSpacing() {
        #expect(TitleParse.key("  Orchard   Games ") == "orchard games")
    }
}
