//
//  TikTokContentExtractor.swift
//  SaveToPatternVault
//
//  Fetches TikTok page and extracts caption/description for AI pattern extraction.
//

import Foundation

struct TikTokContentExtractor {

    static func extract(from urlString: String) async -> ExtractedContent? {
        guard let url = URL(string: urlString),
              urlString.contains("tiktok.com") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                return nil
            }

            let ogTitle = extractMetaContent(from: html, property: "og:title")
                ?? extractMetaContent(from: html, name: "title")
            let ogDescription = extractMetaContent(from: html, property: "og:description")
                ?? extractMetaContent(from: html, name: "description")
            let ogImage = extractMetaContent(from: html, property: "og:image")

            let caption = ogDescription ?? extractCaptionFromScript(in: html) ?? ogTitle ?? ""
            let pageText = caption.isEmpty ? nil : "Caption / description:\n\(caption)"

            return ExtractedContent(
                ogTitle: ogTitle ?? "TikTok pattern",
                ogDescription: ogDescription,
                ogImageUrl: ogImage,
                additionalImageUrls: [],
                pageText: pageText,
                sourceUrl: urlString,
                videoUrls: [urlString]
            )
        } catch {
            return nil
        }
    }

    private static func extractMetaContent(from html: String, property: String) -> String? {
        let pattern = "<meta[^>]+property=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"'][^>]+content=[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: html) else { return nil }
        return decodeHTMLEntities(String(html[r]))
    }

    private static func extractMetaContent(from html: String, name: String) -> String? {
        let pattern = "<meta[^>]+name=[\"']\(NSRegularExpression.escapedPattern(for: name))[\"'][^>]+content=[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: html) else { return nil }
        return decodeHTMLEntities(String(html[r]))
    }

    private static func extractCaptionFromScript(in html: String) -> String? {
        if let sigiMatch = html.range(of: "\"description\":\"") {
            let after = html[sigiMatch.upperBound...]
            if let end = after.range(of: "\"") {
                var cap = String(after[..<end.lowerBound])
                cap = cap.replacingOccurrences(of: "\\u0026", with: "&")
                cap = cap.replacingOccurrences(of: "\\n", with: "\n")
                if !cap.isEmpty { return cap }
            }
        }
        return nil
    }

    private static func decodeHTMLEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}
