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

    // The capture hook marks a chat by putting "cap " in front of its title (2026-11-24). The tag and project still count.
    @Test func aMarkerWordBeforeTheTagIsSkipped() {
        #expect(TitleParse.parse("cap [BBM] ankur - games: kid playtest fixes")
                == ParsedTitle(tag: "BBM", project: "ankur", task: "games: kid playtest fixes"))
        #expect(TitleParse.parse("cap gc-82").project == nil)
    }

    // A sentence that only mentions brackets later on is not a tagged title.
    @Test func bracketsDeepInASentenceAreNotATag() {
        #expect(TitleParse.parse("please look at the [draft] - today").tag == nil)
    }

    @Test func keysIgnoreCaseAndSpacing() {
        #expect(TitleParse.key("  Orchard   Games ") == "orchard games")
    }
}
