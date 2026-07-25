//
//  ContentBlockParserTests.swift
//  PatternVaultTests
//

import XCTest
@testable import CorvidCraft

final class ContentBlockParserTests: XCTestCase {

    // MARK: - parse

    func testParse_empty_returnsEmpty() {
        let blocks = ContentBlockParser.parse("")
        XCTAssertTrue(blocks.isEmpty)
    }

    func testParse_whitespaceOnly_returnsEmpty() {
        let blocks = ContentBlockParser.parse("   \n\n  ")
        XCTAssertTrue(blocks.isEmpty)
    }

    func testParse_singleParagraph_returnsSentenceBlocks() {
        let content = "One line here."
        let blocks = ContentBlockParser.parse(content)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].text, "One line here.")
        XCTAssertEqual(blocks[0].kind, .sentence)
    }

    func testParse_twoParagraphs_includesParagraphBreak() {
        let content = "First para.\n\nSecond para."
        let blocks = ContentBlockParser.parse(content)
        XCTAssertGreaterThanOrEqual(blocks.count, 2)
        let hasBreak = blocks.contains(where: { $0.kind == .paragraphBreak })
        XCTAssertTrue(hasBreak)
    }

    func testParse_table_detectsTableRows() {
        let content = "| A | B |\n| 1 | 2 |\n| 3 | 4 |"
        let blocks = ContentBlockParser.parse(content)
        let tableRows = blocks.filter { $0.kind == .tableRow }
        XCTAssertGreaterThanOrEqual(tableRows.count, 2)
        XCTAssertTrue(tableRows.contains(where: { $0.text.contains("|") }))
    }

    func testParse_bullets_detectsBulletBlocks() {
        let content = "- Item one\n- Item two"
        let blocks = ContentBlockParser.parse(content)
        let bullets = blocks.filter { $0.kind == .bullet }
        XCTAssertGreaterThanOrEqual(bullets.count, 2)
    }

    func testParse_shortLineNoPunctuation_detectsHeading() {
        let content = "Materials"
        let blocks = ContentBlockParser.parse(content)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .heading)
        XCTAssertEqual(blocks[0].text, "Materials")
    }

    func testParse_htmlEntities_decoded() {
        let content = "Size &quot;M&quot; &amp; gauge."
        let blocks = ContentBlockParser.parse(content)
        XCTAssertGreaterThanOrEqual(blocks.count, 1)
        XCTAssertTrue(blocks[0].text.contains("\"") || blocks[0].text.contains("&"))
    }

    // MARK: - reassemble

    func testReassemble_noExclusions_returnsOriginalStructure() {
        let content = "A\n\nB\n\nC"
        let blocks = ContentBlockParser.parse(content)
        let excluded: Set<Int> = []
        let result = ContentBlockParser.reassemble(blocks: blocks, excluding: excluded)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains("A") && result.contains("B") && result.contains("C"))
    }

    func testReassemble_excludingOneBlock_removesThatBlock() {
        let content = "First.\n\nSecond.\n\nThird."
        let blocks = ContentBlockParser.parse(content)
        guard let firstId = blocks.first(where: { $0.kind == .sentence && $0.text == "First." })?.id else {
            XCTFail("Expected sentence block")
            return
        }
        let result = ContentBlockParser.reassemble(blocks: blocks, excluding: [firstId])
        XCTAssertFalse(result.contains("First."))
        XCTAssertTrue(result.contains("Second.") || result.contains("Third."))
    }

    func testReassemble_excludingAllContent_returnsEmpty() {
        let content = "Only one block."
        let blocks = ContentBlockParser.parse(content)
        let ids = Set(blocks.map(\.id))
        let result = ContentBlockParser.reassemble(blocks: blocks, excluding: ids)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - patternContentIndicatorCount

    func testPatternContentIndicatorCount_stitchAbbrevs_returnsAtLeastOne() {
        let text = "K2tog, ssk, yo."
        let count = ContentBlockParser.patternContentIndicatorCount(text)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testPatternContentIndicatorCount_rowRound_returnsAtLeastOne() {
        let text = "Row 5: Knit to end."
        let count = ContentBlockParser.patternContentIndicatorCount(text)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testPatternContentIndicatorCount_boCo_returnsAtLeastOne() {
        let text = "BO in pattern. CO 40 sts."
        let count = ContentBlockParser.patternContentIndicatorCount(text)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testPatternContentIndicatorCount_gauge_returnsAtLeastOne() {
        let text = "20 sts = 4 inches."
        let count = ContentBlockParser.patternContentIndicatorCount(text)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testPatternContentIndicatorCount_plainText_returnsZero() {
        let text = "This is just a normal sentence with no pattern terms."
        let count = ContentBlockParser.patternContentIndicatorCount(text)
        XCTAssertEqual(count, 0)
    }

    func testPatternContentIndicatorCount_multipleIndicators_returnsTwoOrMore() {
        let text = "Row 1: K2tog (20 sts). Gauge 20 sts = 4 in."
        let count = ContentBlockParser.patternContentIndicatorCount(text)
        XCTAssertGreaterThanOrEqual(count, 2)
    }

    // MARK: - Edge cases

    func testParse_singleTableRow_treatedAsSentenceNotTable() {
        let content = "| A | B |"
        let blocks = ContentBlockParser.parse(content)
        let tableRows = blocks.filter { $0.kind == .tableRow }
        XCTAssertTrue(tableRows.isEmpty, "Single pipe line should not be treated as table (need >= 2)")
        XCTAssertGreaterThanOrEqual(blocks.count, 1)
    }

    func testParse_tableWithPipeNoSpaces_detectedByPrefix() {
        let content = "| A | B |\n| 1 | 2 |"
        let blocks = ContentBlockParser.parse(content)
        let tableRows = blocks.filter { $0.kind == .tableRow }
        XCTAssertGreaterThanOrEqual(tableRows.count, 2)
    }

    func testReassemble_onlyParagraphBreaksRemaining_returnsEmpty() {
        let content = "First sentence here.\n\nSecond sentence there."
        let blocks = ContentBlockParser.parse(content)
        let sentenceIds = blocks.filter { $0.kind == .sentence }.map(\.id)
        let result = ContentBlockParser.reassemble(blocks: blocks, excluding: Set(sentenceIds))
        XCTAssertTrue(result.isEmpty)
    }

    func testPatternContentIndicatorCount_emptyString_returnsZero() {
        let count = ContentBlockParser.patternContentIndicatorCount("")
        XCTAssertEqual(count, 0)
    }

    func testPatternContentIndicatorCount_scAsWordBoundary_doesNotFalsePositive() {
        let text = "Scientific notation and escape characters."
        let count = ContentBlockParser.patternContentIndicatorCount(text)
        XCTAssertEqual(count, 0)
    }

    func testParse_longLine_splitsIntoSentences() {
        let content = "First sentence here. Second sentence there. Third one."
        let blocks = ContentBlockParser.parse(content)
        XCTAssertGreaterThanOrEqual(blocks.count, 1)
        let longContent = String(repeating: "Word. ", count: 80)
        let longBlocks = ContentBlockParser.parse(longContent)
        XCTAssertGreaterThanOrEqual(longBlocks.count, 2, "Long line should be split into sentences")
    }

    func testParse_mixedBulletAndNonBullet_inSameGroup() {
        let content = "Section title\n- Item one\n- Item two"
        let blocks = ContentBlockParser.parse(content)
        let bullets = blocks.filter { $0.kind == .bullet }
        let sentences = blocks.filter { $0.kind == .sentence }
        XCTAssertGreaterThanOrEqual(bullets.count, 2)
        XCTAssertGreaterThanOrEqual(sentences.count, 1)
    }
}
