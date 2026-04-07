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
    /// Maximum characters to pass to AI. Gemini 2.5 Flash supports ~1M tokens;
    /// 100k chars ≈ 25k tokens — plenty of headroom for even long patterns.
    private static let pageTextLimit = 100_000

    /// Extracts text from PDF data. Returns nil if not a valid PDF or text is empty.
    /// Truncates to pageTextLimit characters at a paragraph boundary when needed.
    static func extractText(from data: Data) -> String? {
        guard let doc = PDFDocument(data: data) else { return nil }
        guard let text = doc.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let cleaned = stripPdfArtifacts(text)
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > pageTextLimit {
            let end = trimmed.index(trimmed.startIndex, offsetBy: pageTextLimit)
            if let lastBreak = trimmed[..<end].range(of: "\n\n", options: .backwards) {
                return String(trimmed[..<lastBreak.lowerBound])
            }
            return String(trimmed[..<end])
        }
        return trimmed
    }

    /// Removes PDF artifacts that confuse both AI and heuristic parsers:
    /// standalone page numbers, page separators ("-- 1 of 6 --"), and form feeds.
    private static func stripPdfArtifacts(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let cleaned = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return true }
            if t.allSatisfy({ $0.isNumber }) && t.count <= 4 { return false }
            if t.range(of: #"^-{2,}\s*\d+\s*(of|/)\s*\d+\s*-{2,}$"#, options: .regularExpression) != nil { return false }
            if t == "\u{0C}" { return false }
            return true
        }
        return cleaned.joined(separator: "\n")
    }
}
