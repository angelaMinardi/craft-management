//
//  RavelryPatternExtractor.swift
//  SaveToPatternVault
//
//  For Ravelry pattern URLs: fetches the page, finds the pattern PDF link,
//  downloads the PDF, and extracts its text so the app uses the actual pattern
//  content instead of the Ravelry listing page.
//

import Foundation
import PDFKit

enum RavelryPatternExtractor {

    private static let pageTextLimit = 10_000

    /// Returns true if the URL is a Ravelry pattern page (e.g. ravelry.com/patterns/library/...).
    static func isRavelryPatternURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased(),
              host.contains("ravelry") else { return false }
        return url.path.contains("/patterns/")
    }

    /// Returns true if the text is clearly Ravelry nav/sidebar/footer rather than pattern content.
    static func looksLikeRavelryChrome(_ text: String?) -> Bool {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
        let lower = t.lowercased()
        let navPhrases = ["my notebook", "sign in", "create an account"]
        let navItems = ["patterns", "yarns", "people", "groups", "forums"]
        let navCount = navPhrases.filter { lower.contains($0) }.count
        let itemCount = navItems.filter { lower.contains($0) }.count
        if navCount >= 1 && itemCount >= 2 { return true }
        if lower.contains("visits in the last 24 hours") && lower.contains("visitors right now") { return true }
        if lower.contains("more from") && lower.contains("see them all") { return true }
        return false
    }

    /// Strips Ravelry nav/sidebar/footer from page text. Returns nil if nothing useful remains.
    static func filterRavelryChrome(from pageText: String?) -> String? {
        guard let text = pageText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let chromeLinePatterns = [
            "ravelry", "patterns", "yarns", "people", "groups", "forums",
            "my notebook", "sign in", "create an account",
            "more from ", "see them all", "visits in the last 24 hours", "visitors right now",
            "first published:", "page created:", "last updated:"
        ]
        let footerWords = ["home", "about", "advert", "purchase", "cancel"]
        let lines = text.components(separatedBy: .newlines)
        let kept = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            let lower = trimmed.lowercased()
            if chromeLinePatterns.contains(where: { lower.contains($0) }) { return false }
            if footerWords.contains(lower) && trimmed.count < 15 { return false }
            if lower == "patterns" || lower == "yarns" || lower == "people" || lower == "groups" || lower == "forums" { return false }
            return true
        }
        let result = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty || result.count < 80 { return nil }
        return result
    }

    /// Fetches the Ravelry page, finds the pattern PDF, downloads it and extracts text.
    /// Tries Ravelry API first (when credentials are set), then HTML link scraping with PDF verification.
    /// Returns ExtractedContent with pageText from the PDF and patternPdfUrl set; OG metadata from the page.
    /// Returns nil if URL is not Ravelry, or no PDF link found, or PDF fetch/text extraction fails (caller should fall back to WebContentExtractor).
    static func extract(from urlString: String) async -> ExtractedContent? {
        guard isRavelryPatternURL(urlString),
              let pageURL = URL(string: urlString) else { return nil }

        // 1) Fetch Ravelry page HTML (needed for OG metadata and for HTML fallback)
        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let html: String
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                return nil
            }
            html = raw
        } catch {
            return nil
        }

        // 2) Prefer Ravelry API pdf_url when credentials are available
        if let pdfURLString = await pdfUrlFromRavelryAPI(pageURL: pageURL),
           let result = await downloadPdfAndExtractContent(pdfURLString: pdfURLString, urlString: urlString, html: html) {
            return result
        }

        // 3) Fallback: find PDF link in HTML. Ravelry flow: "Download" → intermediate page → "download PDF" → actual PDF (often on ravelrycache.com).
        var candidates = findPatternPdfUrlCandidates(in: html, baseUrl: pageURL)
        var tried = Set<String>()

        while let candidate = candidates.popLast() {
            guard tried.insert(candidate).inserted else { continue }

            let (pdfDataOpt, pdfURLUsed, intermediateHtml) = await fetchUrlAndResolvePdf(candidateURLString: candidate, baseUrl: pageURL)
            if let data = pdfDataOpt, let urlUsed = pdfURLUsed,
               let pageText = extractTextFromPdf(data: data) {
                let ogTitle = extractMetaContent(from: html, property: "og:title")
                    ?? extractMetaContent(from: html, name: "title")
                    ?? firstMatch(in: html, pattern: "<title[^>]*>([^<]+)</title>").map { decodeHTMLEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                let ogDescription = extractMetaContent(from: html, property: "og:description")
                    ?? extractMetaContent(from: html, name: "description")
                let ogImageUrl = extractMetaContent(from: html, property: "og:image")
                return ExtractedContent(
                    ogTitle: ogTitle,
                    ogDescription: ogDescription,
                    ogImageUrl: ogImageUrl,
                    additionalImageUrls: [],
                    pageText: pageText,
                    sourceUrl: urlString,
                    videoUrls: [],
                    patternPdfUrl: urlUsed
                )
            }
            // If we got the intermediate page (HTML), collect PDF links from it (e.g. "download PDF" → ravelrycache.com) and try them next
            if let nextHtml = intermediateHtml, let nextBase = URL(string: candidate) {
                let fromIntermediate = findPatternPdfUrlCandidates(in: nextHtml, baseUrl: nextBase).filter { !tried.contains($0) }
                candidates.append(contentsOf: fromIntermediate)
            }
        }

        return nil
    }

    /// Fetches URL; if response is PDF returns (data, url, nil). If response is HTML (e.g. Ravelry's "Pattern Purchase" page), returns (nil, nil, html) so caller can parse for "download PDF" link.
    private static func fetchUrlAndResolvePdf(candidateURLString: String, baseUrl: URL) async -> (pdfData: Data?, pdfURLString: String?, intermediateHtml: String?) {
        guard let url = URL(string: candidateURLString) else { return (nil, nil, nil) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return (nil, nil, nil) }

            let isPdf = (http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("pdf") == true)
                || (data.count >= 5 && String(data: data.prefix(5), encoding: .ascii) == "%PDF-")

            if isPdf {
                let maxPdfBytes = 5_000_000
                let dataToUse = data.count > maxPdfBytes ? data.prefix(maxPdfBytes) : data
                return (Data(dataToUse), candidateURLString, nil)
            }

            // HTML (e.g. Pattern Purchase page with "download PDF" button)
            if let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                return (nil, nil, html)
            }
        } catch {}
        return (nil, nil, nil)
    }

    /// Download PDF at urlString; if response is PDF, extract text and return ExtractedContent. Otherwise nil.
    private static func downloadPdfAndExtractContent(pdfURLString: String, urlString: String, html: String) async -> ExtractedContent? {
        guard let pdfURL = URL(string: pdfURLString) else { return nil }
        var pdfRequest = URLRequest(url: pdfURL)
        pdfRequest.timeoutInterval = 20
        pdfRequest.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let pdfData: Data
        do {
            let (data, resp) = try await URLSession.shared.data(for: pdfRequest)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            // Require PDF: Content-Type or magic bytes
            let isPdf = (http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("pdf") == true)
                || (data.count >= 5 && String(data: data.prefix(5), encoding: .ascii) == "%PDF-")
            guard isPdf else { return nil }
            pdfData = data
        } catch {
            return nil
        }

        let maxPdfBytes = 5_000_000
        let dataToUse = pdfData.count > maxPdfBytes ? pdfData.prefix(maxPdfBytes) : pdfData
        guard let pageText = extractTextFromPdf(data: Data(dataToUse)) else {
            return nil
        }

        let ogTitle = extractMetaContent(from: html, property: "og:title")
            ?? extractMetaContent(from: html, name: "title")
            ?? firstMatch(in: html, pattern: "<title[^>]*>([^<]+)</title>").map { decodeHTMLEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let ogDescription = extractMetaContent(from: html, property: "og:description")
            ?? extractMetaContent(from: html, name: "description")
        let ogImageUrl = extractMetaContent(from: html, property: "og:image")

        return ExtractedContent(
            ogTitle: ogTitle,
            ogDescription: ogDescription,
            ogImageUrl: ogImageUrl,
            additionalImageUrls: [],
            pageText: pageText,
            sourceUrl: urlString,
            videoUrls: [],
            patternPdfUrl: pdfURLString
        )
    }

    // MARK: - Ravelry API (pattern pdf_url)

    private static func pdfUrlFromRavelryAPI(pageURL: URL) async -> String? {
        guard let permalink = extractPermalink(from: pageURL),
              let (accessKey, personalKey) = ravelryCredentials() else { return nil }

        // Search by permalink
        guard let encodedPermalink = permalink.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let finalSearchUrl = URL(string: "https://api.ravelry.com/patterns/search.json?query=\(encodedPermalink)") else { return nil }

        var searchRequest = URLRequest(url: finalSearchUrl)
        searchRequest.timeoutInterval = 10
        let authString = "\(accessKey):\(personalKey)"
        if let authData = authString.data(using: .utf8) {
            searchRequest.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        guard let (searchData, searchResp) = try? await URLSession.shared.data(for: searchRequest),
              let http = searchResp as? HTTPURLResponse, http.statusCode == 200,
              let searchJson = try? JSONSerialization.jsonObject(with: searchData) as? [String: Any],
              let patterns = searchJson["patterns"] as? [[String: Any]],
              let first = patterns.first(where: { ($0["permalink"] as? String) == permalink }),
              let patternId = first["id"] as? Int else { return nil }

        // Full pattern detail
        guard let detailUrl = URL(string: "https://api.ravelry.com/patterns/\(patternId).json") else { return nil }
        var detailRequest = URLRequest(url: detailUrl)
        detailRequest.timeoutInterval = 10
        if let authData = authString.data(using: .utf8) {
            detailRequest.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }

        guard let (detailData, detailResp) = try? await URLSession.shared.data(for: detailRequest),
              let detailHttp = detailResp as? HTTPURLResponse, detailHttp.statusCode == 200,
              let detailJson = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
              let pattern = detailJson["pattern"] as? [String: Any] else { return nil }

        // API returns pdf_url for the pattern file (free or purchased)
        if let url = pattern["pdf_url"] as? String, !url.isEmpty { return url }
        if let url = pattern["free_pdf_url"] as? String, !url.isEmpty { return url }
        return nil
    }

    private static func extractPermalink(from url: URL) -> String? {
        let components = url.pathComponents
        guard let libraryIndex = components.firstIndex(of: "library"),
              libraryIndex + 1 < components.count else { return nil }
        return components[libraryIndex + 1]
    }

    private static func ravelryCredentials() -> (accessKey: String, personalKey: String)? {
        guard let accessKey = Bundle.main.object(forInfoDictionaryKey: "RAVELRY_ACCESS_KEY") as? String,
              let personalKey = Bundle.main.object(forInfoDictionaryKey: "RAVELRY_PERSONAL_KEY") as? String,
              !accessKey.isEmpty, accessKey != "placeholder",
              !personalKey.isEmpty, personalKey != "placeholder" else {
            return nil
        }
        return (accessKey, personalKey)
    }

    // MARK: - PDF link detection (Ravelry page HTML) — collect candidates, caller tries each until one is a PDF

    private static func findPatternPdfUrlCandidates(in html: String, baseUrl: URL) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        func add(_ href: String) {
            let decoded = decodeHTMLEntities(href).trimmingCharacters(in: .whitespaces)
            guard !decoded.isEmpty,
                  !decoded.contains("javascript:"),
                  let absolute = absolutize(urlString: decoded, baseUrl: baseUrl),
                  seen.insert(absolute).inserted else { return }
            candidates.append(absolute)
        }

        // 1) Direct .pdf links
        for match in allMatches(in: html, pattern: #"href=["']([^"']+\.pdf[^"']*)["']"#) {
            add(match)
        }

        // 2) Ravelry pattern_files or /download paths (no .pdf in URL)
        for match in allMatches(in: html, pattern: #"href=["']([^"']*pattern_files[^"']*)["']"#) {
            add(match)
        }
        for match in allMatches(in: html, pattern: #"href=["']([^"']*/download[^"']*)["']"#) {
            guard match.contains("ravelry") || match.contains("pattern") else { continue }
            add(match)
        }

        // 3) data-href / data-url / data-download for download buttons
        for match in allMatches(in: html, pattern: #"data-(?:href|url|download)=["']([^"']+)["']"#) {
            if match.contains("pdf") || match.contains("download") || match.contains("pattern_file") {
                add(match)
            }
        }

        // 4) Ravelry CDN: intermediate "Pattern Purchase" page links to PDF on ravelrycache.com
        for match in allMatches(in: html, pattern: #"href=["']([^"']*ravelrycache\.com[^"']*)["']"#) {
            add(match)
        }

        // 5) Pattern purchase / download pages (e.g. /pattern_purchase/ or purchase in path)
        for match in allMatches(in: html, pattern: #"href=["']([^"']*(?:pattern_purchase|/purchase/|/download)[^"']*)["']"#) {
            if match.contains("ravelry") || match.hasPrefix("/") { add(match) }
        }

        return candidates
    }

    private static func allMatches(in string: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        let matches = regex.matches(in: string, range: range)
        return matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1, let captureRange = Range(match.range(at: 1), in: string) else { return nil }
            return String(string[captureRange])
        }
    }

    private static func extractTextFromPdf(data: Data) -> String? {
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

    // MARK: - HTML helpers (minimal duplicate of WebContentExtractor for OG + link parsing)

    private static func extractMetaContent(from html: String, property: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            "<meta[^>]+property=[\"']\(escaped)[\"'][^>]+content=[\"']([^\"']*)[\"']",
            "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+property=[\"']\(escaped)[\"']"
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
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "<meta[^>]+name=[\"']\(escaped)[\"'][^>]+content=[\"']([^\"']*)[\"']"
        if let match = firstMatch(in: html, pattern: pattern) {
            let decoded = decodeHTMLEntities(match)
            if !decoded.isEmpty { return decoded }
        }
        return nil
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
            ("&nbsp;", " "), ("&#8211;", "–"), ("&#8212;", "—")
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
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
