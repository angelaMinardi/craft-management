//
//  AIPatternAnalyzer.swift
//  SaveToPatternVault
//
//  Uses Gemini 2.0 Flash to extract structured pattern metadata from webpage content.
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
    /// JSON string of AI-parsed steps: [{"title":"...", "body":"..."}]
    let parsedStepsJSON: String?
}

struct YarnLinkEntry: Sendable {
    let brandName: String
    let officialUrl: String?
    let storeUrl: String?
}

enum AIPatternAnalyzer {

    private static var geminiApiKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        guard let key, !key.isEmpty, key != "placeholder" else { return nil }
        return key
    }

    static func analyze(content: ExtractedContent) async -> AIPatternResult? {
        guard let key = geminiApiKey, let result = await analyzeWithGemini(content: content, apiKey: key) else {
            return fallbackResult(from: content)
        }
        return result
    }

    private static func analyzeWithGemini(content: ExtractedContent, apiKey: String) async -> AIPatternResult? {
        var contextParts: [String] = []
        if let t = content.ogTitle { contextParts.append("Page title: \(t)") }
        if let d = content.ogDescription { contextParts.append("Page description: \(d)") }
        if !content.videoUrls.isEmpty {
            contextParts.append("Video URLs found on page: \(content.videoUrls.joined(separator: ", "))")
        }
        if let p = content.pageText { contextParts.append("Page content: \(p)") }
        let pageContext = contextParts.joined(separator: "\n\n")
        guard !pageContext.isEmpty else { return fallbackResult(from: content) }

        let systemPrompt = """
        You are a craft pattern analyzer. The pattern can be ANY craft: knitting, crochet, sewing, leatherworking, beading, jewelry, weaving, embroidery, paper craft, woodworking, etc. Extract structured information appropriate to the craft. Respond ONLY with valid JSON, no markdown fences. Output the short metadata fields first (title, summary, tags, craft_type, etc.), then steps, then cleaned_content LAST so that if the response is truncated, the metadata and steps are still captured. Steps are major construction phases (e.g. Base, Body, Handles, Finishing), not individual rows or rounds. Do NOT create steps for reference sections (Materials, Gauge, Sizes, Notes, PATTERN as a container, or technique subsections like SLIP STITCHES). Optionally emit one step titled "Pattern details" or "Materials & gauge" first with body containing materials/gauge/sizes/notes; then only construction steps (e.g. Base, Body, Divide for Handles, First Handle, Second Handle, Finishing).
        """
        let userPrompt = buildPatternExtractionUserPrompt(pageContext: pageContext)

        let fullPrompt = systemPrompt + "\n\n" + userPrompt
        let generationConfig: [String: Any] = [
            "responseMimeType": "application/json",
            "maxOutputTokens": 4096
        ]
        let textPart: [String: Any] = ["text": fullPrompt]
        let parts: [[String: Any]] = [textPart]
        let contentPart: [String: Any] = ["parts": parts]
        let contents: [[String: Any]] = [contentPart]
        let requestBody: [String: Any] = [
            "contents": contents,
            "generationConfig": generationConfig
        ]

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent") else {
            return fallbackResult(from: content)
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return fallbackResult(from: content)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return fallbackResult(from: content)
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let candidates = json?["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let contentObj = first["content"] as? [String: Any],
                  let parts = contentObj["parts"] as? [[String: Any]],
                  let textPart = parts.first,
                  let text = textPart["text"] as? String else {
                return fallbackResult(from: content)
            }
            let finishReason = first["finishReason"] as? String
            let wasTruncated = (finishReason == "MAX_TOKENS")
            return parseAIResponse(text, fallbackContent: content, wasTruncated: wasTruncated)
        } catch {
            return fallbackResult(from: content)
        }
    }

    private static func buildPatternExtractionUserPrompt(pageContext: String) -> String {
        """
        Analyze this craft pattern webpage and extract the following as JSON. The pattern may be any craft (knitting, crochet, sewing, leatherworking, beading, jewelry, etc.). Extract craft-appropriate metadata: for knitting/crochet use gauge, needle_hook_sizes, yarn_weight_yardage, yarn_links; for leather use materials (leather type, tools), yarn_links for supplier links; for beading use materials (bead size, thread), yarn_links for supplier links; for other crafts use materials and optionally yarn_links as brand/supplier + URLs. Leave gauge, needle_hook_sizes, yarn_weight_yardage null when not applicable.
        IMPORTANT: Output fields in EXACTLY this order (metadata first, cleaned_content LAST):
        {
          "title": "a short, catchy, friendly name for this pattern",
          "summary": "2-3 sentence description of the pattern",
          "tags": ["tag1", "tag2", "tag3"],
          "craft_type": "knitting/crochet/sewing/leatherworking/beading/jewelry/etc or null",
          "difficulty": "beginner/intermediate/advanced/expert or null",
          "materials": "brief materials or supplies summary (yarn, leather type, bead size, tools, etc.) or null",
          "video_url": "single best tutorial or pattern walkthrough URL from the page, or null",
          "gauge": "e.g. 22 sts x 30 rows = 4 in stockinette (fiber crafts only), or null",
          "needle_hook_sizes": "e.g. US 7 (4.5 mm) (fiber crafts only), or null",
          "yarn_weight_yardage": "e.g. Worsted; 800 yd (fiber crafts only), or null",
          "techniques": "comma-separated skills (craft-appropriate), or null",
          "yarn_links": [{"brand_name": "Brand or supplier name", "official_url": "https://... or null", "store_url": "https://... or null"}],
          "steps": [{"title": "short step name (2-5 words)", "body": "full instructions for this phase (no length limit)"}],
          "cleaned_content": "the relevant pattern content only (see rules below) — OUTPUT THIS FIELD LAST"
        }
        YARN_LINKS: For fiber crafts use yarn brand names (e.g. Malabrigo, Lion Brand). For other crafts use supplier/brand names (leather, beads, tools). For each return brand_name and when possible official_url and store_url. Use null when URL unknown. Max 8 entries.

        STEPS: Emit 3-15 steps in construction order.
        - Optional first step: One step titled "Pattern details" or "Materials & gauge" with body containing materials, gauge, sizes, and notes (full text allowed). Then only construction-phase steps.
        - The "Pattern details" step must contain ONLY materials, gauge, sizes, and notes. It must NOT include the PATTERN heading or any construction instructions (e.g. Base, Body, Cast on). If the source has a "PATTERN" section header, treat it as the start of construction steps, not part of Pattern details.
        - Do NOT create separate steps for Materials, Gauge, Sizes, Notes, PATTERN (as a section header), or technique subsections (e.g. SLIP STITCHES). Do NOT use a step titled "PATTERN".
        - title: Short section name (2-5 words), e.g. "Base", "Body", "First Handle", "Finishing". Use the pattern's own section headings when present (e.g. "Divide for Handles"); otherwise a concise label. Do not use the full first line of an instruction as the title.
        - body: May contain full instructions for that phase (no length or summary-only requirement). Keep clarity; avoid truncating critical instructions. Format the body for readability: put section labels in ALL CAPS on their own line (e.g. GAUGE, SIZES, NOTES); start callouts with NOTE:; use - for bullet points; use a blank line between sections.
        If the page has no real pattern instructions, return [] for steps. Do NOT treat individual "Row 1", "Row 2", "Round 3" lines as separate steps; group them under the section they belong to (e.g. one step "First Handle" covering all rows in that section).

        TITLE RULES: Create a cute, memorable name — NOT the webpage title. Keep it short (2-5 words). Use the garment/item type and a descriptive or whimsical word. Examples: "Chunky Poncho Sweater", "Cozy Cable Beanie", "Lacy Summer Top", "Patchwork Baby Blanket". Never include "FREE", "pattern", website names, colons, or ellipses.

        Tags should include: craft type, garment type, technique, season/occasion if applicable. Max 6 tags.

        VIDEO_URL: If "Video URLs found on page" is provided, pick the one that is clearly a pattern tutorial or walkthrough. Otherwise leave null.

        CLEANED_CONTENT RULES:
        Start of pattern: Include from the first substantive pattern section (e.g. Materials, Gauge, Sizes, Notes, or the main PATTERN / instructions heading). Omit long intro paragraphs that only describe the design or the yarn; keep a short intro only if it is the pattern's own description.
        Keep: Pattern description and overview, Materials/yarn requirements, Gauge, Sizing charts and measurement tables (preserve ALL rows and columns using pipe | separators), Construction notes and techniques, Skills needed, Key pattern details (stitch counts, needle sizes), Abbreviations and glossary. Sizing/measurement tables are critical — include the FULL table with every row and column. Format tables with | separators like: Size | Height | Width | Length.
        End of pattern: STOP cleaned_content at the last actual instruction. The last line of cleaned_content should be the last actual instruction (e.g. "Weave in all ends. Wet block as desired."). Omit everything after that. Do NOT include any of the following (treat as end-of-pattern and omit everything from that point on):
        - Lines like "Share your progress…", "Tag your pics…", "Connect with the community…", "#Hashtag", "We can't wait to see what you make!"
        - "Learn about [yarn/product]…", "Learn About [product/yarn name]", "More [X] patterns", "More Free Knitting Patterns", "More Worsted/Aran-Weight Yarns", "Similar posts", "You might also like", "Related patterns", "Similar posts you might enjoy"
        - "Shop our entire collection", "Looking for more inspiration?", "We have over … yarns"
        - Navigation: "Previous post", "Next post", "Print", "Comments", "TO TOP", repeated footers
        - Promo CTAs: "BUY [product name]", "BUY SUNSHOWER COTTON", or any "Buy [yarn/product]" line
        - Comment UI: "Looks like an excellent", "Reply", "Leave a reply", comment counts (e.g. "120 comments")
        Remove throughout: Navigation links, menus, "skip to content", Ads, affiliate disclosures, cookie notices, "Get the PDF", "Buy now", promotional CTAs, SEO filler text, author bios, unrelated blog content, duplicate content, "You may also like" / related patterns, newsletter signups, full blog narrative not about the pattern, promotional paragraphs that do not describe materials or construction.
        Use \\n\\n for paragraph breaks and \\n- for bullet items. Be THOROUGH — include ALL useful pattern information. Do NOT summarize or abbreviate pattern instructions.

        Webpage content:
        \(pageContext)
        """
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
                yarnLinks: [],
                parsedStepsJSON: nil
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
        let parsedStepsJSON = encodeStepsJSON(json["steps"])

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
            yarnLinks: yarnLinks,
            parsedStepsJSON: parsedStepsJSON
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

    /// Encodes the AI-returned steps array back to a JSON string for DB storage.
    private static func encodeStepsJSON(_ value: Any?) -> String? {
        guard let arr = value as? [[String: Any]], !arr.isEmpty else { return nil }
        let steps = arr.compactMap { item -> [String: String]? in
            guard let title = item["title"] as? String, !title.isEmpty,
                  let body = item["body"] as? String, !body.isEmpty else { return nil }
            return ["title": title, "body": body]
        }
        guard !steps.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: steps),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
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

    /// Generates 2-3 fallback tags from the source URL and any available metadata.
    static func fallbackTags(sourceUrl: String, craftType: String? = nil) -> [String] {
        var tags: [String] = []
        let host = URL(string: sourceUrl)?.host?.lowercased() ?? ""
        if host.contains("ravelry") { tags.append("Ravelry") }
        else if host.contains("tiktok") { tags.append("TikTok") }
        else if host.contains("youtube") || host.contains("youtu.be") { tags.append("YouTube") }
        else if host.contains("etsy") { tags.append("Etsy") }
        else if host.contains("lovecrafts") { tags.append("LoveCrafts") }
        else if sourceUrl.hasPrefix("file://") { tags.append("imported") }
        else { tags.append("pattern") }

        if let craft = craftType, !craft.isEmpty {
            tags.append(craft.lowercased())
        }
        if tags.count < 2 { tags.append("to-make") }
        return tags
    }

    private static func fallbackResult(from content: ExtractedContent) -> AIPatternResult? {
        guard content.ogTitle != nil || content.ogDescription != nil else { return nil }
        let tags = fallbackTags(sourceUrl: content.sourceUrl)
        return AIPatternResult(
            title: content.ogTitle ?? "Untitled Pattern",
            summary: content.ogDescription ?? "",
            tags: tags,
            craftType: nil,
            difficulty: nil,
            materials: nil,
            cleanedContent: content.pageText,
            videoUrl: content.videoUrls.first,
            gauge: nil,
            needleHookSizes: nil,
            yarnWeightYardage: nil,
            techniques: nil,
            yarnLinks: [],
            parsedStepsJSON: nil
        )
    }
}
