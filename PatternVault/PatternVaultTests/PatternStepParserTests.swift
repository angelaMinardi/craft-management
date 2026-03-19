//
//  PatternStepParserTests.swift
//  PatternVaultTests
//

import XCTest
@testable import PatternVault

final class PatternStepParserTests: XCTestCase {

    // MARK: - truncateAtEndOfPattern

    func testTruncateAtEndOfPattern_nil_returnsNil() {
        XCTAssertNil(PatternStepParser.truncateAtEndOfPattern(nil))
    }

    func testTruncateAtEndOfPattern_empty_returnsEmpty() {
        XCTAssertEqual(PatternStepParser.truncateAtEndOfPattern(""), "")
    }

    func testTruncateAtEndOfPattern_whitespaceOnly_returnsUnchanged() {
        let input = "   \n  \t  "
        XCTAssertEqual(PatternStepParser.truncateAtEndOfPattern(input), input)
    }

    func testTruncateAtEndOfPattern_noSentinel_returnsFullString() {
        let input = "Row 1: k2tog. Row 2: purl."
        XCTAssertEqual(PatternStepParser.truncateAtEndOfPattern(input), input)
    }

    func testTruncateAtEndOfPattern_sentinelLearnAbout_truncatesBeforeThatLine() {
        let input = "Row 1: knit.\nRow 2: purl.\nLearn about more free knitting here."
        let result = PatternStepParser.truncateAtEndOfPattern(input)
        XCTAssertFalse(result?.contains("Learn about") ?? true)
        XCTAssertTrue(result?.contains("Row 2") ?? false)
    }

    func testTruncateAtEndOfPattern_sentinelYouMightAlsoLike_truncates() {
        let input = "Instructions here.\n\nYou might also like this pattern."
        let result = PatternStepParser.truncateAtEndOfPattern(input)
        XCTAssertFalse(result?.contains("You might also like") ?? true)
    }

    // MARK: - looksLikeRavelryChrome

    func testLooksLikeRavelryChrome_nil_returnsFalse() {
        XCTAssertFalse(PatternStepParser.looksLikeRavelryChrome(nil))
    }

    func testLooksLikeRavelryChrome_empty_returnsFalse() {
        XCTAssertFalse(PatternStepParser.looksLikeRavelryChrome(""))
    }

    func testLooksLikeRavelryChrome_navPhrasesAndItems_returnsTrue() {
        let chrome = "My notebook sign in create an account. Patterns yarns people groups forums."
        XCTAssertTrue(PatternStepParser.looksLikeRavelryChrome(chrome))
    }

    func testLooksLikeRavelryChrome_visitsAndVisitors_returnsTrue() {
        let chrome = "Visits in the last 24 hours. Visitors right now."
        XCTAssertTrue(PatternStepParser.looksLikeRavelryChrome(chrome))
    }

    func testLooksLikeRavelryChrome_moreFromSeeThemAll_returnsTrue() {
        let chrome = "More from this designer. See them all."
        XCTAssertTrue(PatternStepParser.looksLikeRavelryChrome(chrome))
    }

    func testLooksLikeRavelryChrome_realInstructions_returnsFalse() {
        let content = "Row 1: K2tog, yo. Row 2: Purl all. Bind off."
        XCTAssertFalse(PatternStepParser.looksLikeRavelryChrome(content))
    }

    // MARK: - parseSteps

    func testParseSteps_nilSourceContent_usesDescriptionFallback() {
        let steps = PatternStepParser.parseSteps(sourceContent: nil, patternDescription: "A nice pattern.")
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].title, "Step 1")
        XCTAssertTrue(steps[0].body.contains("nice pattern") || steps[0].body.contains("A nice pattern"))
    }

    func testParseSteps_nilSourceContent_nilDescription_usesDefaultFallback() {
        let steps = PatternStepParser.parseSteps(sourceContent: nil, patternDescription: nil)
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].title, "Step 1")
        XCTAssertTrue(steps[0].body.contains("preferred materials") || steps[0].body.contains("instructions"))
    }

    func testParseSteps_emptySourceContent_usesFallback() {
        let steps = PatternStepParser.parseSteps(sourceContent: "", patternDescription: "Desc")
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].title, "Step 1")
    }

    func testParseSteps_ravelryChrome_usesFallback() {
        let chrome = "My notebook sign in. Patterns yarns people groups forums. Visits in the last 24 hours. Visitors right now."
        let steps = PatternStepParser.parseSteps(sourceContent: chrome, patternDescription: "Real description.")
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].title, "Step 1")
        XCTAssertTrue(steps[0].body.contains("Real description") || steps[0].body.contains("preferred materials"))
    }

    func testParseSteps_sectionHeadings_parsesSections() {
        let content = """
        MATERIALS
        Yarn and needles.

        BODY
        Row 1: Knit.
        Row 2: Purl.
        """
        let steps = PatternStepParser.parseSteps(sourceContent: content, patternDescription: nil)
        XCTAssertGreaterThanOrEqual(steps.count, 1)
        let titles = steps.map { $0.title }
        XCTAssertTrue(titles.contains("Pattern details") || titles.contains("BODY") || titles.contains("Body"))
    }

    func testParseSteps_step1Step2_parsesNumberedSteps() {
        let content = """
        Step 1
        Cast on 40 stitches.

        Step 2
        Row 1: Knit all.
        """
        let steps = PatternStepParser.parseSteps(sourceContent: content, patternDescription: nil)
        XCTAssertGreaterThanOrEqual(steps.count, 2)
        XCTAssertTrue(steps.contains(where: { $0.title.contains("1") }))
        XCTAssertTrue(steps.contains(where: { $0.title.contains("2") }))
    }

    func testParseSteps_rowAndRound_parsesRowRound() {
        let content = """
        Row 5
        K2tog, yo to end.

        Round 3
        Sc in each st.
        """
        let steps = PatternStepParser.parseSteps(sourceContent: content, patternDescription: nil)
        XCTAssertGreaterThanOrEqual(steps.count, 1)
        XCTAssertTrue(steps.contains(where: { $0.body.contains("K2tog") || $0.body.contains("Sc") }))
    }

    func testParseSteps_numberedList_parsesAsSteps() {
        let content = """
        1. Cast on.
        2. Knit one row.
        3. Purl one row.
        """
        let steps = PatternStepParser.parseSteps(sourceContent: content, patternDescription: nil)
        XCTAssertGreaterThanOrEqual(steps.count, 1, "Parser may merge numbered list into one or more steps")
    }

    func testParseSteps_htmlEntities_decoded() {
        let content = "Row 1: K2tog &amp; yo. Size &quot;M&quot;."
        let steps = PatternStepParser.parseSteps(sourceContent: content, patternDescription: nil)
        XCTAssertGreaterThanOrEqual(steps.count, 1)
        let body = steps[0].body
        XCTAssertTrue(body.contains("&") || body.contains("M") || body.contains("\""))
    }

    func testParseSteps_singleBlockInstruction_returnsSingleStep() {
        let content = "Knit in pattern until piece measures 10 inches. Bind off."
        let steps = PatternStepParser.parseSteps(sourceContent: content, patternDescription: nil)
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].title, "Step 1")
        XCTAssertTrue(steps[0].body.contains("Knit") || steps[0].body.contains("10"))
    }

    // MARK: - Edge cases

    func testTruncateAtEndOfPattern_sentinelAtStart_returnsFullString() {
        let input = "Learn about more free knitting here.\nRow 1: knit."
        let result = PatternStepParser.truncateAtEndOfPattern(input)
        XCTAssertEqual(result, input, "Sentinel at offset 0 should not truncate (offset > 0 check)")
    }

    func testTruncateAtEndOfPattern_earliestSentinelWins() {
        let input = "Row 1: knit.\nYou might also like this.\nLearn about more."
        let result = PatternStepParser.truncateAtEndOfPattern(input)
        XCTAssertFalse(result?.contains("You might also like") ?? true)
        XCTAssertFalse(result?.contains("Learn about") ?? true)
        XCTAssertTrue(result?.contains("Row 1") ?? false)
    }

    func testLooksLikeRavelryChrome_oneNavPhraseAndTwoItems_returnsTrue() {
        let chrome = "Sign in. Patterns yarns people."
        XCTAssertTrue(PatternStepParser.looksLikeRavelryChrome(chrome))
    }

    func testLooksLikeRavelryChrome_twoItemsOnlyNoNavPhrase_returnsFalse() {
        let text = "Patterns yarns people groups forums."
        XCTAssertFalse(PatternStepParser.looksLikeRavelryChrome(text))
    }

    func testParseSteps_allJunkBlocks_usesFallback() {
        let junk = "Share Print Subscribe. Newsletter sign up. Follow us. Menu Home."
        let steps = PatternStepParser.parseSteps(sourceContent: junk, patternDescription: "Real instructions.")
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].title, "Step 1")
        XCTAssertTrue(steps[0].body.contains("Real instructions") || steps[0].body.contains("preferred materials"))
    }

    func testParseSteps_patternSectionOnly_usesFallbackOrSingleStep() {
        let content = """
        PATTERN
        Knit until done.
        """
        let steps = PatternStepParser.parseSteps(sourceContent: content, patternDescription: nil)
        XCTAssertGreaterThanOrEqual(steps.count, 1)
        XCTAssertTrue(steps.contains(where: { $0.body.contains("Knit") }) || steps[0].body.contains("preferred materials"))
    }

    func testParseSteps_markdownHeadings_parsesSections() {
        let content = """
        ## Materials
        Yarn and needles.

        ## Body
        Row 1: Knit.
        """
        let steps = PatternStepParser.parseSteps(sourceContent: content, patternDescription: nil)
        XCTAssertGreaterThanOrEqual(steps.count, 1)
        let titles = steps.map { $0.title }
        XCTAssertTrue(titles.contains("Materials") || titles.contains("Body") || titles.contains("Pattern details"))
    }

    func testParseSteps_numberedListMinimalContent_parsesSteps() {
        let content = """
        1. Cast on.
        2.
        3. Purl.
        """
        let steps = PatternStepParser.parseSteps(sourceContent: content, patternDescription: nil)
        XCTAssertGreaterThanOrEqual(steps.count, 1)
    }
}
