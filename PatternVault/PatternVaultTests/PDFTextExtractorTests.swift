//
//  PDFTextExtractorTests.swift
//  PatternVaultTests
//
//  Unit tests for PDF text extraction (main app). Valid PDF flow is covered by manual/Share Extension.
//

import XCTest
@testable import PatternVault

final class PDFTextExtractorTests: XCTestCase {

    func testExtractText_nonPdfData_returnsNil() {
        let data = Data("not a pdf".utf8)
        XCTAssertNil(PDFTextExtractor.extractText(from: data))
    }

    func testExtractText_emptyData_returnsNil() {
        XCTAssertNil(PDFTextExtractor.extractText(from: Data()))
    }
}
