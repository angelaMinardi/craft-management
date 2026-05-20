//
//  StitchAbbreviationLinkBuilder.swift
//  PatternVault
//

import Foundation
import SwiftUI

enum StitchCraftKind {
    case knitting
    case crochet
}

enum StitchAbbreviationLinkBuilder {
    private static let abbreviationPattern =
        #"\b(?:kfb|pfb|k2tog|p2tog|ssk|ssp|sssk|yo|m1l|m1r|m1p|m1|sl1k|sl1p|sl1|psso|p2sso|cdd|s2kp2|sk2p|skp|tbl|w&t|wyif|wyib|k1b|k\d+|p\d+|c\d+[fb]|t\d+[fb]|rt|lt|sc2tog|dc2tog|hdc2tog|invdec|sc|dc|hdc|tr|dtr|inc|dec|ch|slst|fpdc|bpdc|fptr|bptr|fphdc|bphdc|blo|flo|bo|co|pm|sm|cn|pc|cl|sh|mr|tss|tks|tps|mc|cc)\b"#
    private static let urlPattern = #"(?:https?://|www\.)\S+"#
    private static let crochetSignalPattern = #"\b(?:dc|sc|hdc|tr|dtr|ch|slst|fpdc|bpdc|blo|flo|mr|invdec)\b"#

    static func inferCraftKind(explicitCraftType: String?, text: String) -> StitchCraftKind {
        if let explicit = explicitCraftType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !explicit.isEmpty {
            if explicit.contains("crochet") { return .crochet }
            if explicit.contains("knit") { return .knitting }
        }

        if text.range(of: crochetSignalPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return .crochet
        }
        return .knitting
    }

    static func tutorialURL(for abbreviation: String, craftKind: StitchCraftKind) -> URL? {
        let normalized = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        // Use in-app glossary URL if we have a definition
        if StitchGlossary.lookup(normalized) != nil {
            return URL(string: "corvidcraft://glossary/\(normalized)")
        }

        // Fall back to web search for unknown abbreviations
        let prefix = craftKind == .crochet ? "crochet how to" : "knitting how to"
        let query = "\(prefix) \(normalized)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }

    static func linkedAttributedString(
        from text: String,
        explicitCraftType: String?,
        contextText: String? = nil
    ) -> AttributedString {
        var attributed = AttributedString(text)
        guard
            let abbrRegex = try? NSRegularExpression(pattern: abbreviationPattern, options: [.caseInsensitive]),
            let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: [.caseInsensitive])
        else {
            return attributed
        }

        let nsText = text as NSString
        let wholeRange = NSRange(location: 0, length: nsText.length)
        let urlRanges = urlRegex.matches(in: text, range: wholeRange).map(\.range)
        let craftKind = inferCraftKind(explicitCraftType: explicitCraftType, text: contextText ?? text)

        for match in abbrRegex.matches(in: text, range: wholeRange) {
            let matchRange = match.range
            guard !urlRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) else {
                continue
            }
            guard let stringRange = Range(matchRange, in: text) else { continue }
            let abbreviation = String(text[stringRange])
            guard let url = tutorialURL(for: abbreviation, craftKind: craftKind) else { continue }

            guard
                let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
                let upper = AttributedString.Index(stringRange.upperBound, within: attributed)
            else {
                continue
            }

            attributed[lower..<upper].link = url
            attributed[lower..<upper].underlineStyle = .single
        }

        return attributed
    }
}
