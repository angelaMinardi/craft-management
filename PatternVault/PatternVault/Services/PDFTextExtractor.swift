//
//  PDFTextExtractor.swift
//  PatternVault
//
//  Extracts plain text from PDF data for step parsing. Used when analyzing steps from a pattern's PDF (e.g. Ravelry pdf_url).
//

import Foundation
import PDFKit

enum PDFTextExtractor {
    /// Max characters to pass to AI (truncate at paragraph break when possible).
    private static let pageTextLimit = 10_000

    /// Extracts text from PDF data. Returns nil if not a valid PDF or text is empty.
    static func extractText(from data: Data) -> String? {
        guard let doc = PDFDocument(data: data) else { return nil }
        guard let text = doc.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > pageTextLimit {
            let end = trimmed.index(trimmed.startIndex, offsetBy: pageTextLimit)
            if let lastBreak = trimmed[..<end].range(of: "\n\n", options: .backwards) {
                return String(trimmed[..<lastBreak.lowerBound])
            }
            return String(trimmed[..<end])
        }
        return trimmed
    }
}
