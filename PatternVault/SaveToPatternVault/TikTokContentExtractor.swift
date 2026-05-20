//
//  TikTokContentExtractor.swift
//  SaveToPatternVault
//
//  Resolves short TikTok URLs, tries oEmbed first for caption/title, then falls back to HTML scrape.
//

import Foundation

struct TikTokContentExtractor {

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static func extract(from urlString: String) async -> ExtractedContent? {
        guard URL(string: urlString) != nil,
              urlString.lowercased().contains("tiktok") else { return nil }

        let canonical = await resolveCanonicalTikTokURL(urlString)
        if let fromOEmbed = await fetchOEmbed(canonicalUrlString: canonical) {
            return fromOEmbed
        }
        return await extractFromHTML(canonicalUrlString: canonical)
    }

    /// Follows redirects (e.g. vm.tiktok.com) and returns final tiktok.com URL, or original if not redirecting to TikTok.
    private static func resolveCanonicalTikTokURL(_ urlString: String) async -> String {
        guard let url = URL(string: urlString) else { return urlString }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let response = response as? HTTPURLResponse,
               (200...399).contains(response.statusCode),
               let finalURL = response.url?.absoluteString,
               finalURL.lowercased().contains("tiktok.com") {
                return finalURL
            }
        } catch {}
        return urlString
    }

    /// Tries TikTok oEmbed (with one retry on 400). Returns ExtractedContent or nil to fall back to HTML.
    private static func fetchOEmbed(canonicalUrlString: String) async -> ExtractedContent? {
        guard let encoded = canonicalUrlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let oembedURL = URL(string: "https://www.tiktok.com/oembed?url=\(encoded)") else { return nil }

        var request = URLRequest(url: oembedURL)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        for attempt in 0..<2 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                if http.statusCode == 400 && attempt == 0 { continue }
                guard (200...299).contains(http.statusCode),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !title.isEmpty else {
                    return nil
                }
                let authorName = json["author_name"] as? String
                let authorUrl = json["author_url"] as? String
                let thumbnailUrl = json["thumbnail_url"] as? String
                let displayTitle = authorName.map { "\($0): \(title)" } ?? title
                return ExtractedContent(
                    ogTitle: displayTitle,
                    ogDescription: authorUrl,
                    ogImageUrl: thumbnailUrl,
                    additionalImageUrls: [],
                    pageText: nil,
                    sourceUrl: canonicalUrlString,
                    videoUrls: [canonicalUrlString],
                    patternPdfUrl: nil
                )
            } catch {
                if attempt == 1 { return nil }
            }
        }
        return nil
    }

    /// Fallback: fetch HTML and parse OG meta + caption from script.
    private static func extractFromHTML(canonicalUrlString: String) async -> ExtractedContent? {
        guard let url = URL(string: canonicalUrlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                return nil
            }

            let ogTitle = extractMetaContent(from: html, property: "og:title")
                ?? extractMetaContent(from: html, name: "title")
            let ogImage = extractMetaContent(from: html, property: "og:image")

            return ExtractedContent(
                ogTitle: ogTitle ?? "TikTok pattern",
                ogDescription: nil,
                ogImageUrl: ogImage,
                additionalImageUrls: [],
                pageText: nil,
                sourceUrl: canonicalUrlString,
                videoUrls: [canonicalUrlString],
                patternPdfUrl: nil
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
