//
//  PatternModelTests.swift
//  PatternVaultTests
//

import XCTest
@testable import CorvidCraft

final class PatternModelTests: XCTestCase {

    func testDecodedParsedSteps_nil_returnsNil() {
        let pattern = makePattern(parsedSteps: nil)
        XCTAssertNil(pattern.decodedParsedSteps)
    }

    func testDecodedParsedSteps_emptyString_returnsNil() {
        let pattern = makePattern(parsedSteps: "")
        let steps = pattern.decodedParsedSteps
        XCTAssertNil(steps, "Empty string is invalid JSON so decode returns nil")
    }

    func testDecodedParsedSteps_invalidJSON_returnsNil() {
        let pattern = makePattern(parsedSteps: "not json at all")
        XCTAssertNil(pattern.decodedParsedSteps)
    }

    func testDecodedParsedSteps_validArray_returnsParsedSteps() {
        let json = #"[{"title":"Step 1","body":"Cast on."},{"title":"Step 2","body":"Knit."}]"#
        let pattern = makePattern(parsedSteps: json)
        let steps = pattern.decodedParsedSteps
        XCTAssertNotNil(steps)
        XCTAssertEqual(steps?.count, 2)
        XCTAssertEqual(steps?[0].title, "Step 1")
        XCTAssertEqual(steps?[0].body, "Cast on.")
        XCTAssertEqual(steps?[1].title, "Step 2")
        XCTAssertEqual(steps?[1].body, "Knit.")
    }

    func testDecodedParsedSteps_emptyArray_returnsEmptyArray() {
        let json = "[]"
        let pattern = makePattern(parsedSteps: json)
        let steps = pattern.decodedParsedSteps
        XCTAssertNotNil(steps)
        XCTAssertEqual(steps?.count, 0)
    }

    func testDecodedParsedSteps_malformedArray_returnsNil() {
        let pattern = makePattern(parsedSteps: "[{]")
        XCTAssertNil(pattern.decodedParsedSteps)
    }

    func testPatternStatus_displayNames() {
        XCTAssertEqual(PatternStatus.wantToMake.displayName, "Want to Make")
        XCTAssertEqual(PatternStatus.inProgress.displayName, "In Progress")
        XCTAssertEqual(PatternStatus.completed.displayName, "Completed")
    }

    func testPatternStatus_rawValues() {
        XCTAssertEqual(PatternStatus.wantToMake.rawValue, "want_to_make")
        XCTAssertEqual(PatternStatus.inProgress.rawValue, "in_progress")
        XCTAssertEqual(PatternStatus.completed.rawValue, "completed")
    }

    // MARK: - Edge cases (decodedParsedSteps)

    func testDecodedParsedSteps_jsonObjectNotArray_returnsNil() {
        let pattern = makePattern(parsedSteps: "{\"title\":\"Step 1\",\"body\":\"x\"}")
        XCTAssertNil(pattern.decodedParsedSteps)
    }

    func testDecodedParsedSteps_stepMissingTitle_returnsNil() {
        let json = #"[{"body":"Cast on."}]"#
        let pattern = makePattern(parsedSteps: json)
        XCTAssertNil(pattern.decodedParsedSteps)
    }

    func testDecodedParsedSteps_stepMissingBody_returnsNil() {
        let json = #"[{"title":"Step 1"}]"#
        let pattern = makePattern(parsedSteps: json)
        XCTAssertNil(pattern.decodedParsedSteps)
    }

    func testDecodedParsedSteps_emptyTitleAndBody_decodeSucceeds() {
        let json = #"[{"title":"","body":""}]"#
        let pattern = makePattern(parsedSteps: json)
        let steps = pattern.decodedParsedSteps
        XCTAssertNotNil(steps)
        XCTAssertEqual(steps?.count, 1)
        XCTAssertEqual(steps?[0].title, "")
        XCTAssertEqual(steps?[0].body, "")
    }

    func testDecodedParsedSteps_extraKeys_decodeSucceeds() {
        let json = #"[{"title":"Step 1","body":"Knit.","extra":"ignored"}]"#
        let pattern = makePattern(parsedSteps: json)
        let steps = pattern.decodedParsedSteps
        XCTAssertNotNil(steps)
        XCTAssertEqual(steps?.count, 1)
        XCTAssertEqual(steps?[0].title, "Step 1")
        XCTAssertEqual(steps?[0].body, "Knit.")
    }

    func testDecodedParsedSteps_unicodeInStep_decodeSucceeds() {
        // JSON escape \u00E4 so decoding is independent of source file encoding
        let json = "[{\"title\":\"Runde 1\",\"body\":\"Maschen \\u00E4hnlich.\"}]"
        let pattern = makePattern(parsedSteps: json)
        let steps = pattern.decodedParsedSteps
        XCTAssertNotNil(steps)
        XCTAssertEqual(steps?.count, 1)
        XCTAssertEqual(steps?[0].title, "Runde 1")
        XCTAssertTrue(steps?[0].body.contains("ähnlich") ?? false)
    }

    func testPattern_pdfUrl_roundTripsThroughJson() throws {
        let url = "https://example.com/pattern.pdf"
        let pattern = makePattern(parsedSteps: nil, pdfUrl: url)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(pattern)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(Pattern.self, from: data)
        XCTAssertEqual(decoded.pdfUrl, url)
    }

    // MARK: - Helpers

    private func makePattern(parsedSteps: String?, pdfUrl: String? = nil) -> Pattern {
        Pattern(
            id: UUID(),
            title: "Test",
            patternDescription: nil,
            sourceUrl: "https://example.com",
            sourcePlatform: nil,
            status: .wantToMake,
            thumbnailUrl: nil,
            difficulty: nil,
            materials: nil,
            craftType: nil,
            sourceContent: nil,
            pdfUrl: pdfUrl,
            videoUrl: nil,
            gauge: nil,
            needleHookSizes: nil,
            yarnWeightYardage: nil,
            techniques: nil,
            parsedSteps: parsedSteps,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
