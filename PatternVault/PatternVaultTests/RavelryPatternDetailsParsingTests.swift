//
//  RavelryPatternDetailsParsingTests.swift
//  PatternVaultTests
//
//  Unit tests for parsing Ravelry batch patterns response (array/dict, flat/nested) and PDF URL extraction.
//

import XCTest
@testable import PatternVault

@MainActor
final class RavelryPatternDetailsParsingTests: XCTestCase {

    // MARK: - Array shape, pdf_url

    func testParsePatternDetailsPayload_arrayWithPdfUrl_returnsMap() {
        let payload: [[String: Any]] = [
            [
                "id": 42,
                "first_photo": ["medium_url": "https://cdn.example.com/photo.jpg"] as [String: Any],
                "pdf_url": "https://cdn.example.com/pattern.pdf"
            ] as [String: Any]
        ]
        let result = RavelryUserService.parsePatternDetailsPayload(payload)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[42]?.imageUrl, "https://cdn.example.com/photo.jpg")
        XCTAssertEqual(result[42]?.pdfUrl, "https://cdn.example.com/pattern.pdf")
    }

    // MARK: - Array shape, free_pdf_url only

    func testParsePatternDetailsPayload_arrayWithFreePdfUrlOnly_returnsPdfUrl() {
        let payload: [[String: Any]] = [
            ["id": 99, "free_pdf_url": "https://free.example.com/p.pdf"] as [String: Any]
        ]
        let result = RavelryUserService.parsePatternDetailsPayload(payload)
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[99]?.imageUrl)
        XCTAssertEqual(result[99]?.pdfUrl, "https://free.example.com/p.pdf")
    }

    // MARK: - Dictionary shape (keyed by string id)

    func testParsePatternDetailsPayload_dictionaryShape_returnsMap() {
        let payload: [String: Any] = [
            "42": [
                "id": 42,
                "pdf_url": "https://dict.example.com/pattern.pdf"
            ] as [String: Any]
        ]
        let result = RavelryUserService.parsePatternDetailsPayload(payload)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[42]?.pdfUrl, "https://dict.example.com/pattern.pdf")
    }

    // MARK: - Array with nested "pattern" wrapper

    func testParsePatternDetailsPayload_arrayWithNestedPatternWrapper_returnsPdfUrl() {
        let payload: [[String: Any]] = [
            [
                "pattern": [
                    "id": 1,
                    "pdf_url": "https://wrapped.pdf"
                ] as [String: Any]
            ] as [String: Any]
        ]
        let result = RavelryUserService.parsePatternDetailsPayload(payload)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[1]?.pdfUrl, "https://wrapped.pdf")
    }

    // MARK: - Empty / nil

    func testParsePatternDetailsPayload_emptyArray_returnsEmptyMap() {
        let payload: [[String: Any]] = []
        let result = RavelryUserService.parsePatternDetailsPayload(payload)
        XCTAssertTrue(result.isEmpty)
    }

    func testParsePatternDetailsPayload_nil_returnsEmptyMap() {
        let result = RavelryUserService.parsePatternDetailsPayload(nil)
        XCTAssertTrue(result.isEmpty)
    }

    func testParsePatternDetailsPayload_wrongType_returnsEmptyMap() {
        let result = RavelryUserService.parsePatternDetailsPayload("not array or dict")
        XCTAssertTrue(result.isEmpty)
    }
}
