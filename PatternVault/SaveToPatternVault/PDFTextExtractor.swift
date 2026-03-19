//
//  PDFTextExtractor.swift
//  SaveToPatternVault
//
//  Extracts plain text from PDF data for AI pattern analysis.
//  Used by ShareViewController for shared PDFs and by RavelryPatternExtractor.
//

import Foundation
import PDFKit

enum PDFTextExtractor {
    /// Maximum characters to pass to AI (truncate at paragraph break when possible).
    private static let pageTextLimit = 10_000

    /// Extracts text from PDF data. Returns nil if not a valid PDF or text is empty.
    /// Truncates to pageTextLimit characters at a paragraph boundary when needed.
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
