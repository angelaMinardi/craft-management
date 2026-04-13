//
//  WebContentExtractor.swift
//  SaveToPatternVault
//
//  Fetches webpage HTML and extracts OpenGraph metadata + page text.
//

import Foundation

struct ExtractedContent: Sendable {
    let ogTitle: String?
    let ogDescription: String?
    let ogImageUrl: String?
    let additionalImageUrls: [String]
    let pageText: String?
    let sourceUrl: String
    /// Video URLs found on the page (og:video, YouTube/Vimeo links) for tutorial/walkthrough detection.
    let videoUrls: [String]
    /// When content was derived from a pattern PDF (e.g. Ravelry), the PDF download URL to store as pattern.pdf_url.
    let patternPdfUrl: String?
}

enum WebContentExtractor {

    static func extract(from urlString: String) async -> ExtractedContent {
        guard let url = URL(string: urlString) else {
            return ExtractedContent(ogTitle: nil, ogDescription: nil, ogImageUrl: nil, additionalImageUrls: [], pageText: nil, sourceUrl: urlString, videoUrls: [], patternPdfUrl: nil)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Some sites block non-browser user agents
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                return ExtractedContent(ogTitle: nil, ogDescription: nil, ogImageUrl: nil, additionalImageUrls: [], pageText: nil, sourceUrl: urlString, videoUrls: [], patternPdfUrl: nil)
            }

            let ogTitle = extractMetaContent(from: html, property: "og:title")
                ?? extractMetaContent(from: html, name: "title")
                ?? extractHTMLTitle(from: html)
            let ogDescription = extractMetaContent(from: html, property: "og:description")
                ?? extractMetaContent(from: html, name: "description")
            let ogImageUrl = extractMetaContent(from: html, property: "og:image")
            let pageText = extractVisibleText(from: html)
            let additionalImageUrls = extractAdditionalImageUrls(from: html, baseUrl: url)
            let videoUrls = extractVideoUrls(from: html, baseUrl: url)

            return ExtractedContent(
                ogTitle: ogTitle,
                ogDescription: ogDescription,
                ogImageUrl: ogImageUrl,
                additionalImageUrls: additionalImageUrls,
                pageText: pageText,
                sourceUrl: urlString,
                videoUrls: videoUrls,
                patternPdfUrl: nil
            )
        } catch {
            return ExtractedContent(ogTitle: nil, ogDescription: nil, ogImageUrl: nil, additionalImageUrls: [], pageText: nil, sourceUrl: urlString, videoUrls: [], patternPdfUrl: nil)
        }
    }

    // MARK: - HTML Parsing Helpers

    private static func extractMetaContent(from html: String, property: String) -> String? {
        // Match <meta property="og:title" content="...">
        let patterns = [
            "<meta[^>]+property=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"'][^>]+content=[\"']([^\"']*)[\"']",
            "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+property=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"']"
        ]
        for pattern in patterns {
            if let match = firstMatch(in: html, pattern: pattern) {
                let decoded = decodeHTMLEntities(match)
                if !decoded.isEmpty { return decoded }
            }
        }
        return nil
    }

    private static func extractMetaContent(from html: String, name: String) -> String? {
        let patterns = [
            "<meta[^>]+name=[\"']\(NSRegularExpression.escapedPattern(for: name))[\"'][^>]+content=[\"']([^\"']*)[\"']",
            "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+name=[\"']\(NSRegularExpression.escapedPattern(for: name))[\"']"
        ]
        for pattern in patterns {
            if let match = firstMatch(in: html, pattern: pattern) {
                let decoded = decodeHTMLEntities(match)
                if !decoded.isEmpty { return decoded }
            }
        }
        return nil
    }

    private static func extractHTMLTitle(from html: String) -> String? {
        if let match = firstMatch(in: html, pattern: "<title[^>]*>([^<]+)</title>") {
            let decoded = decodeHTMLEntities(match).trimmingCharacters(in: .whitespacesAndNewlines)
            if !decoded.isEmpty { return decoded }
        }
        return nil
    }

    private static func extractVisibleText(from html: String) -> String? {
        // Remove script, style, and nav elements
        var cleaned = html
        let stripPatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<nav[^>]*>[\\s\\S]*?</nav>",
            "<footer[^>]*>[\\s\\S]*?</footer>",
            "<header[^>]*>[\\s\\S]*?</header>",
            "<aside[^>]*>[\\s\\S]*?</aside>",
            "<noscript[^>]*>[\\s\\S]*?</noscript>",
            "<form[^>]*>[\\s\\S]*?</form>",
            // Common craft blog sidebar/widget classes
            "<div[^>]+class=[\"'][^\"']*(sidebar|widget|comment|related-post|newsletter|popup|modal|cookie|consent|social-share|share-button|ad-container|advertisement)[^\"']*[\"'][^>]*>[\\s\\S]*?</div>"
        ]
        for pattern in stripPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ")
            }
        }

        // Convert structural HTML to newlines BEFORE stripping tags
        let structuralReplacements: [(String, String)] = [
            ("<li[^>]*>", "\n- "),                           // list items → bullets
            ("</(p|div|li|h[1-6]|blockquote)>", "\n\n"),     // block closers → paragraph breaks
            ("</tr>", "\n"),                                  // table rows → line breaks
            ("<t[dh][^>]*>", " | "),                          // table cells → pipe-separated
            ("<br\\s*/?>", "\n"),                             // line breaks
            ("<h[1-6][^>]*>", "\n\n"),                        // heading openers → separation
        ]
        for (pattern, replacement) in structuralReplacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: replacement)
            }
        }

        // Remove all remaining HTML tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            cleaned = tagRegex.stringByReplacingMatches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: " ")
        }

        // Decode entities
        cleaned = decodeHTMLEntities(cleaned)

        // Normalize whitespace per-line while preserving newlines
        let lines = cleaned.components(separatedBy: "\n")
        let normalizedLines = lines.map { line in
            line.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
        }

        // Filter out junk lines (empty bullets, nav items, common boilerplate, craft blog clutter)
        let junkPatterns: [String] = [
            "^-\\s*$",                                          // empty bullet "- "
            "^skip to \\w+$",                                   // "Skip to content"
            "^(menu|search|close|toggle)$",                      // single nav words
            "^share (this|on)\\b",                               // social sharing
            "^(previous|next) (post|article)$",                  // post navigation
            "^leave a (comment|reply)$",                         // comment CTAs
            "^\\d+ comments?$",                                  // comment counts
            "^this post may contain affiliate",                  // affiliate disclaimers
            "^please read my disclosure",                        // disclosure policy
            "^this post contains affiliate",                     // affiliate variant
            "^disclosure:",                                      // disclosure header
            "^jump to (the )?pattern",                           // CTA: skip to pattern
            "^get the (ad[- ]free )?pdf",                        // CTA: PDF upsell
            "^click here to (get|download|purchase)",            // CTA: download
            "^(buy|purchase|shop|order) (now|the|this)",         // purchase CTAs
            "^add to cart",                                      // shopping CTA
            "^save (this|to|for later)",                         // save CTA
            "^pin (this|it) (for|to)",                           // Pinterest CTA
            "^what'?s to love",                                  // marketing section header
            "^you may also (like|enjoy)",                        // related content
            "^more patterns? (from|by|you)",                     // related patterns
            "^(sign up|subscribe|join).*(newsletter|email|list)", // newsletter CTAs
            "^(follow|connect with) (me|us) on",                // social follow CTAs
            "^\\| filed under",                                  // category filing
            "^posted (in|on|by)\\b",                             // post metadata
            "^tagged (with|in)\\b",                              // tag metadata
            "^\\d+ (shares?|pins?|likes?)$",                     // social counts
            "^(copyright|©|all rights reserved)",                // copyright
            "^(advertisement|sponsored|ad)$",                    // ads
        ]
        let junkRegexes = junkPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

        let filteredLines = normalizedLines.filter { line in
            if line.isEmpty { return true }  // keep blank lines for paragraph breaks
            if line == "-" { return false }   // bare dash
            if line.count < 2 { return false } // single-char junk
            for regex in junkRegexes {
                if regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    return false
                }
            }
            return true
        }

        // Collapse runs of empty lines to max 1 empty line (paragraph break)
        var result: [String] = []
        var consecutiveEmpty = 0
        for line in filteredLines {
            if line.isEmpty {
                consecutiveEmpty += 1
                if consecutiveEmpty <= 1 {
                    result.append("")
                }
            } else {
                consecutiveEmpty = 0
                result.append(line)
            }
        }

        let text = result.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Limit to ~100k chars, truncating at last paragraph break.
        // Gemini 2.5 Flash supports ~1M tokens; 100k chars is well within budget.
        if text.count > 100_000 {
            let truncated = String(text.prefix(100_000))
            if let lastBreak = truncated.range(of: "\n\n", options: .backwards) {
                return String(truncated[..<lastBreak.lowerBound])
            }
            return truncated
        }
        return text.isEmpty ? nil : text
    }

    private static func firstMatch(in string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: string) else { return nil }
        return String(string[captureRange])
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&#x27;", "'"), ("&nbsp;", " "), ("&#8211;", "–"),
            ("&#8212;", "—"), ("&#8216;", "'"), ("&#8217;", "'"),
            ("&#8220;", "\u{201C}"), ("&#8221;", "\u{201D}"),
            ("&hellip;", "…"), ("&mdash;", "—"), ("&ndash;", "–")
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Handle numeric entities like &#123;
        if let numRegex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let nsResult = result as NSString
            let matches = numRegex.matches(in: result, range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                if let codeRange = Range(match.range(at: 1), in: result),
                   let code = Int(result[codeRange]),
                   let scalar = Unicode.Scalar(code) {
                    let fullRange = Range(match.range, in: result)!
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        return result
    }

    private static func extractAdditionalImageUrls(from html: String, baseUrl: URL) -> [String] {
        var urls: [String] = []

        // Collect og:image (can appear multiple times)
        let ogImagePattern = "<meta[^>]+property=[\"']og:image[\"'][^>]+content=[\"']([^\"']*)[\"']"
        if let regex = try? NSRegularExpression(pattern: ogImagePattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, range: range)
            for match in matches {
                if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) {
                    let value = decodeHTMLEntities(String(html[r]))
                    if let absolute = absolutize(urlString: value, baseUrl: baseUrl) {
                        urls.append(absolute)
                    }
                }
            }
        }

        // Collect <img src="...">
        let imgPattern = "<img[^>]+src=[\"']([^\"']+)[\"']"
        if let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, range: range)
            for match in matches {
                if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) {
                    let value = decodeHTMLEntities(String(html[r]))
                    if let absolute = absolutize(urlString: value, baseUrl: baseUrl) {
                        urls.append(absolute)
                    }
                }
            }
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        let deduped = urls.filter { seen.insert($0).inserted }

        return deduped
    }

    private static func extractVideoUrls(from html: String, baseUrl: URL) -> [String] {
        var urls: [String] = []

        // og:video
        if let ogVideo = extractMetaContent(from: html, property: "og:video"),
           let absolute = absolutize(urlString: ogVideo, baseUrl: baseUrl) {
            urls.append(absolute)
        }

        // YouTube / Vimeo / common video host links: <a href="...">
        let videoHostPattern = #"<a[^>]+href=["']([^"']*(?:youtube\.com|youtu\.be|vimeo\.com)[^"']*)["']"#
        if let regex = try? NSRegularExpression(pattern: videoHostPattern, options: .caseInsensitive) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, range: range)
            for match in matches {
                guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) else { continue }
                let value = decodeHTMLEntities(String(html[r]))
                if let absolute = absolutize(urlString: value, baseUrl: baseUrl) {
                    urls.append(absolute)
                }
            }
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    private static func absolutize(urlString: String, baseUrl: URL) -> String? {
        guard !urlString.isEmpty else { return nil }
        if let absolute = URL(string: urlString), absolute.scheme != nil {
            return absolute.absoluteString
        }
        if let resolved = URL(string: urlString, relativeTo: baseUrl)?.absoluteURL {
            return resolved.absoluteString
        }
        return nil
    }

}
