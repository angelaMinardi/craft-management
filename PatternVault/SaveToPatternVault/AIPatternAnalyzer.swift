//
//  AIPatternAnalyzer.swift
//  SaveToPatternVault
//
//  Calls Claude API to extract structured pattern metadata from webpage content.
//

import Foundation

struct AIPatternResult: Sendable {
    let title: String
    let summary: String
    let tags: [String]
    let craftType: String?
    let difficulty: String?
    let materials: String?
    let cleanedContent: String?
    let videoUrl: String?
    let gauge: String?
    let needleHookSizes: String?
    let yarnWeightYardage: String?
    let techniques: String?
    /// Yarn brands mentioned with optional official and store URLs (for linking in UI).
    let yarnLinks: [YarnLinkEntry]
}

struct YarnLinkEntry: Sendable {
    let brandName: String
    let officialUrl: String?
    let storeUrl: String?
}

enum AIPatternAnalyzer {

    private static var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String
    }

    static func analyze(content: ExtractedContent) async -> AIPatternResult? {
        guard let apiKey, !apiKey.isEmpty, apiKey != "placeholder" else {
            return fallbackResult(from: content)
        }

        var contextParts: [String] = []
        if let t = content.ogTitle { contextParts.append("Page title: \(t)") }
        if let d = content.ogDescription { contextParts.append("Page description: \(d)") }
        if !content.videoUrls.isEmpty {
            contextParts.append("Video URLs found on page: \(content.videoUrls.joined(separator: ", "))")
        }
        if let p = content.pageText { contextParts.append("Page content: \(p)") }
        let pageContext = contextParts.joined(separator: "\n\n")

        guard !pageContext.isEmpty else {
            return fallbackResult(from: content)
        }

        let systemPrompt = """
        You are a craft pattern analyzer. Given webpage content about a craft pattern (knitting, crochet, sewing, etc.), extract structured information. Respond ONLY with valid JSON, no markdown fences. Output the short metadata fields first (title, summary, tags, craft_type, difficulty, materials, video_url, gauge, needle_hook_sizes, yarn_weight_yardage, techniques, yarn_links), then cleaned_content LAST so that if the response is truncated, the metadata is still captured.
        """

        let userPrompt = """
        Analyze this craft pattern webpage and extract the following as JSON.
        IMPORTANT: Output fields in EXACTLY this order (metadata first, cleaned_content LAST):
        {
          "title": "a short, catchy, friendly name for this pattern",
          "summary": "2-3 sentence description of the pattern",
          "tags": ["tag1", "tag2", "tag3"],
          "craft_type": "knitting/crochet/sewing/etc or null",
          "difficulty": "beginner/intermediate/advanced/expert or null",
          "materials": "brief materials summary or null",
          "video_url": "single best tutorial or pattern walkthrough URL from the page, or null",
          "gauge": "e.g. 22 sts x 30 rows = 4 in stockinette, or null",
          "needle_hook_sizes": "e.g. US 7 (4.5 mm), US 8 (5 mm), or null",
          "yarn_weight_yardage": "e.g. Worsted; 800-1200 yd or DK, 400 yd, or null",
          "techniques": "comma-separated skills e.g. cables, k2tog, short rows, or null",
          "yarn_links": [{"brand_name": "Brand Name", "official_url": "https://... or null", "store_url": "https://... or null"}],
          "cleaned_content": "the relevant pattern content only (see rules below) — OUTPUT THIS FIELD LAST"
        }
        YARN_LINKS: From materials or page content, identify specific yarn BRAND names (e.g. Malabrigo, Lion Brand, Cascade). For each brand return brand_name and when possible official_url (brand website) and store_url (e.g. Ravelry, LoveCrafts, or main retailer). Use null when URL unknown. Do not link generic terms like worsted or DK. Max 8 entries.

        TITLE RULES: Create a cute, memorable name — NOT the webpage title. Keep it short (2-5 words). Use the garment/item type and a descriptive or whimsical word. Examples: "Chunky Poncho Sweater", "Cozy Cable Beanie", "Lacy Summer Top", "Patchwork Baby Blanket". Never include "FREE", "pattern", website names, colons, or ellipses.

        Tags should include: craft type, garment type, technique, season/occasion if applicable. Max 6 tags.

        VIDEO_URL: If "Video URLs found on page" is provided, pick the one that is clearly a pattern tutorial or walkthrough. Otherwise leave null.

        CLEANED_CONTENT RULES: Extract ONLY the useful pattern information from the page content. Keep:
        - Pattern description and overview
        - Materials/yarn requirements
        - Gauge information
        - Sizing charts and measurement tables (preserve ALL rows and columns using pipe | separators)
        - Construction notes and techniques
        - Skills needed
        - Key pattern details (stitch counts, needle sizes, etc.)
        - Abbreviations and glossary
        IMPORTANT: Sizing/measurement tables are critical — always include the FULL table with every row and column. Format tables with | separators like: Size | Height | Width | Length
        Remove ALL of the following (do not include in cleaned_content):
        - Navigation links, menus, "skip to content"
        - Ads, affiliate disclosures, cookie notices
        - Social sharing prompts, comment sections
        - "Get the PDF", "Buy now", promotional CTAs
        - SEO filler text, author bios, unrelated blog content
        - Duplicate content
        - "You may also like" / related patterns, newsletter signups
        - Full blog narrative not about the pattern itself, unrelated product carousels
        - Promotional paragraphs that do not describe materials or construction
        Use \\n\\n for paragraph breaks and \\n- for bullet items. Be THOROUGH — include ALL useful pattern information. It is better to include too much useful content than to leave out important details like sizing tables, stitch counts, or construction notes. Do NOT summarize or abbreviate pattern instructions.

        Webpage content:
        \(pageContext)
        """

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": userPrompt]
            ],
            "system": systemPrompt
        ]

        guard let url = URL(string: "https://api.anthropic.com/v1/messages"),
              let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return fallbackResult(from: content)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return fallbackResult(from: content)
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let contentArray = json?["content"] as? [[String: Any]],
                  let textBlock = contentArray.first(where: { ($0["type"] as? String) == "text" }),
                  let text = textBlock["text"] as? String else {
                return fallbackResult(from: content)
            }

            let stopReason = json?["stop_reason"] as? String
            let wasTruncated = (stopReason == "max_tokens")

            return parseAIResponse(text, fallbackContent: content, wasTruncated: wasTruncated)
        } catch {
            return fallbackResult(from: content)
        }
    }

    private static func parseAIResponse(_ text: String, fallbackContent: ExtractedContent, wasTruncated: Bool = false) -> AIPatternResult {
        // Strip markdown code fences if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to parse as-is first
        var json: [String: Any]?
        if let data = cleaned.data(using: .utf8) {
            json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }

        // If parsing failed (likely truncated JSON), try to repair it
        if json == nil {
            json = repairTruncatedJSON(cleaned)
        }

        guard let json else {
            return fallbackResult(from: fallbackContent) ?? AIPatternResult(
                title: fallbackContent.ogTitle ?? "Untitled Pattern",
                summary: fallbackContent.ogDescription ?? "",
                tags: [], craftType: nil, difficulty: nil, materials: nil,
                cleanedContent: nil, videoUrl: nil, gauge: nil, needleHookSizes: nil, yarnWeightYardage: nil, techniques: nil,
                yarnLinks: []
            )
        }

        let title = json["title"] as? String ?? fallbackContent.ogTitle ?? "Untitled Pattern"
        let summary = json["summary"] as? String ?? fallbackContent.ogDescription ?? ""
        let tags = json["tags"] as? [String] ?? []
        let craftType = json["craft_type"] as? String
        let difficulty = json["difficulty"] as? String
        let materials = json["materials"] as? String
        let videoUrl = json["video_url"] as? String
        let gauge = json["gauge"] as? String
        let needleHookSizes = json["needle_hook_sizes"] as? String
        let yarnWeightYardage = json["yarn_weight_yardage"] as? String
        let techniques = json["techniques"] as? String
        let yarnLinks = parseYarnLinks(json["yarn_links"])

        // If the response was truncated, cleaned_content is likely cut off or missing.
        // Use the AI-extracted value only if it looks complete; otherwise fall back to pageText.
        let aiCleanedContent = json["cleaned_content"] as? String
        let cleanedContent: String?
        if wasTruncated && (aiCleanedContent == nil || (aiCleanedContent?.count ?? 0) < 50) {
            // Truncation cut off cleaned_content — use raw pageText as fallback
            cleanedContent = fallbackContent.pageText
        } else {
            cleanedContent = aiCleanedContent
        }

        return AIPatternResult(
            title: title, summary: summary, tags: tags,
            craftType: craftType, difficulty: difficulty, materials: materials,
            cleanedContent: cleanedContent,
            videoUrl: videoUrl, gauge: gauge, needleHookSizes: needleHookSizes,
            yarnWeightYardage: yarnWeightYardage, techniques: techniques,
            yarnLinks: yarnLinks
        )
    }

    /// Attempts to repair truncated JSON by finding the last complete key-value pair
    /// and closing the object. This lets us salvage metadata fields (title, tags, gauge, etc.)
    /// even when cleaned_content was cut off mid-string.
    private static func repairTruncatedJSON(_ text: String) -> [String: Any]? {
        let repaired = text

        // Strategy: find the last complete "key": value pair, trim everything after it, close the object.
        // Look for the last complete string value ending with a quote followed by comma or nothing.
        // Try progressively more aggressive truncation until we get valid JSON.

        // First, try just closing open strings/arrays/objects
        let closers: [String] = [
            "\"]}",   // close string + array + object (inside yarn_links)
            "\"}",    // close string + object
            "}",      // close object
            "]}",     // close array + object
            "\"]}"    // close string + array + object
        ]

        for closer in closers {
            // Find last comma before any incomplete value and truncate there
            let candidate = repaired + closer
            if let data = candidate.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        }

        // More aggressive: find the last `", "` or `",\n` (end of a complete key-value pair)
        // and truncate everything after it, then close the object.
        let lastCommaPatterns = ["\",", "null,", "true,", "false,", "],"]
        for pattern in lastCommaPatterns {
            if let lastRange = repaired.range(of: pattern, options: .backwards) {
                let truncated = String(repaired[..<lastRange.upperBound])
                // Remove the trailing comma and close
                let withoutTrailingComma = truncated.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ",$", with: "", options: .regularExpression)

                // Count open braces/brackets and close them
                var openBraces = 0
                var openBrackets = 0
                for char in withoutTrailingComma {
                    if char == "{" { openBraces += 1 }
                    else if char == "}" { openBraces -= 1 }
                    else if char == "[" { openBrackets += 1 }
                    else if char == "]" { openBrackets -= 1 }
                }

                var closed = withoutTrailingComma
                for _ in 0..<max(0, openBrackets) { closed += "]" }
                for _ in 0..<max(0, openBraces) { closed += "}" }

                if let data = closed.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return json
                }
            }
        }

        return nil
    }

    private static func parseYarnLinks(_ value: Any?) -> [YarnLinkEntry] {
        guard let arr = value as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard let name = item["brand_name"] as? String, !name.isEmpty else { return nil }
            return YarnLinkEntry(
                brandName: name,
                officialUrl: item["official_url"] as? String,
                storeUrl: item["store_url"] as? String
            )
        }
    }

    private static func fallbackResult(from content: ExtractedContent) -> AIPatternResult? {
        guard content.ogTitle != nil || content.ogDescription != nil else { return nil }
        return AIPatternResult(
            title: content.ogTitle ?? "Untitled Pattern",
            summary: content.ogDescription ?? "",
            tags: [],
            craftType: nil,
            difficulty: nil,
            materials: nil,
            cleanedContent: content.pageText,
            videoUrl: content.videoUrls.first,
            gauge: nil,
            needleHookSizes: nil,
            yarnWeightYardage: nil,
            techniques: nil,
            yarnLinks: []
        )
    }
}
