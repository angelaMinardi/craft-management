//
//  AIPatternAnalyzer.swift
//  SaveToPatternVault
//
//  Uses Gemini 2.5 Flash to extract structured pattern metadata from webpage content.
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
    /// JSON string of AI-parsed instructions (v2): [{"section":"...", "start_row":0, ...}]
    /// Falls back to v1 format [{"title":"...", "body":"..."}] for older imports.
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

    static func analyze(content: ExtractedContent, images: [Data] = []) async -> AIPatternResult? {
        guard let key = geminiApiKey, let result = await analyzeWithGemini(content: content, images: images, apiKey: key) else {
            return fallbackResult(from: content)
        }
        return result
    }

    private static func analyzeWithGemini(content: ExtractedContent, images: [Data], apiKey: String) async -> AIPatternResult? {
        var contextParts: [String] = []
        if let t = content.ogTitle { contextParts.append("Page title: \(t)") }
        if let d = content.ogDescription { contextParts.append("Page description: \(d)") }
        if !content.videoUrls.isEmpty {
            contextParts.append("Video URLs found on page: \(content.videoUrls.joined(separator: ", "))")
        }
        if let p = content.pageText { contextParts.append("Page content: \(p)") }
        let pageContext = contextParts.joined(separator: "\n\n")
        guard !pageContext.isEmpty else { return fallbackResult(from: content) }

        let hasImages = !images.isEmpty
        let systemPrompt = """
        You are a craft pattern analyzer. The pattern can be ANY craft: knitting, crochet, sewing, leatherworking, beading, jewelry, weaving, embroidery, paper craft, woodworking, etc. Extract structured information appropriate to the craft. Respond ONLY with valid JSON, no markdown fences. Output the short metadata fields first (title, summary, tags, craft_type, etc.), then instructions, then cleaned_content LAST so that if the response is truncated, the metadata and instructions are still captured. Extract individual working instructions grouped by construction section with row/round numbers when available.
        """
        let userPrompt = buildPatternExtractionUserPrompt(pageContext: pageContext, hasImages: hasImages)
        let fullPrompt = systemPrompt + "\n\n" + userPrompt

        var parts: [[String: Any]] = [["text": fullPrompt]]
        for imageData in images {
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ])
        }

        let maxTokens = 8192
        let requestBody: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": maxTokens,
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent") else {
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
        request.timeoutInterval = hasImages ? 90 : 60

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return fallbackResult(from: content)
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let candidates = json?["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let contentObj = first["content"] as? [String: Any],
                  let parts = contentObj["parts"] as? [[String: Any]] else {
                return fallbackResult(from: content)
            }
            // Gemini 2.5+ may include thought parts; find the actual output text.
            let outputPart = parts.last(where: { ($0["thought"] as? Bool) != true && $0["text"] != nil })
            guard let text = outputPart?["text"] as? String else {
                return fallbackResult(from: content)
            }
            let finishReason = first["finishReason"] as? String
            let wasTruncated = (finishReason == "MAX_TOKENS")
            return parseAIResponse(text, fallbackContent: content, wasTruncated: wasTruncated)
        } catch {
            return fallbackResult(from: content)
        }
    }

    private static func buildPatternExtractionUserPrompt(pageContext: String, hasImages: Bool = false) -> String {
        let chartSection: String
        if hasImages {
            chartSection = """

            CHART DETECTION (images are provided):
            I have also provided images from this pattern (numbered starting at 0).
            Some may contain stitch charts, colorwork charts, or construction diagrams.
            For each instruction that references or requires a chart, include these additional fields in the instruction object:
            - "chart_image_index": the 0-based index of the image containing the chart
            - "chart_label": a short descriptive name for the chart (e.g., "Skull Sampler Toe Chart")
            - "chart_crop": {"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0} — normalized bounding box (0.0 to 1.0) of the chart region within that image. Use the full image if the chart fills it entirely.
            If an instruction does not reference a chart, omit these fields.
            """
        } else {
            chartSection = ""
        }

        return """
        Analyze this craft pattern webpage and extract the following as JSON. The pattern may be any craft (knitting, crochet, sewing, leatherworking, beading, jewelry, etc.). Extract craft-appropriate metadata. Leave gauge, needle_hook_sizes, yarn_weight_yardage null when not applicable.
        IMPORTANT: Output fields in EXACTLY this order (metadata first, cleaned_content LAST):
        {
          "title": "a short, catchy, friendly name for this pattern",
          "summary": "2-3 sentence description of the pattern",
          "tags": ["tag1", "tag2", "tag3"],
          "craft_type": "knitting/crochet/sewing/leatherworking/beading/jewelry/etc or null",
          "difficulty": "beginner/intermediate/advanced/expert or null",
          "materials": "brief materials or supplies summary or null",
          "video_url": "single best tutorial URL from the page, or null",
          "gauge": "e.g. 22 sts x 30 rows = 4 in stockinette, or null",
          "needle_hook_sizes": "e.g. US 7 (4.5 mm), or null",
          "yarn_weight_yardage": "e.g. Worsted; 800 yd, or null",
          "techniques": "comma-separated skills, or null",
          "yarn_links": [{"brand_name": "Brand name", "official_url": "https://... or null", "store_url": "https://... or null"}],
          "instructions": [{"section": "Toe", "start_row": 0, "end_row": 0, "instruction": "full text", "stitch_count": null, "note": null}],
          "cleaned_content": "the relevant pattern content only — OUTPUT THIS FIELD LAST"
        }

        YARN_LINKS: For fiber crafts use yarn brand names. For other crafts use supplier/brand names. Max 8 entries.

        INSTRUCTIONS: Extract every individual working instruction, organized by construction section with row/round numbers.
        Each instruction object:
        - "section": The construction section name (1-4 words). Use the pattern's own headings when present. Capitalize naturally. If row/round numbering restarts within a single named section (e.g., two separate "Row 1" entries under "Heel"), split into descriptive sub-sections (e.g., "Heel Short Rows" and "Heel Closing").
        - "start_row"/"end_row": Row or round numbers from the text. Single row: both equal. Range: use the range. For unnumbered instructions: both 0. NEVER invent row numbers not in the source text.
        - "instruction": The COMPLETE instruction text exactly as written. Do NOT summarize, paraphrase, or truncate. Preserve all size variations, stitch abbreviations, and details.
        - "stitch_count": If the instruction explicitly states a resulting count, extract the smallest size as integer. Otherwise null.
        - "note": Important side information not in the instruction itself. Otherwise null.
        - Each distinct row, round, or standalone instruction is its own entry.
        - Do NOT include materials, gauge, abbreviations, sizing charts, or designer commentary as instructions.
        - If no real instructions exist, return [].
        - Instructions must be in working order.
        \(chartSection)

        TITLE RULES: Create a cute, memorable name — NOT the webpage title. Keep it short (2-5 words). Use the garment/item type and a descriptive or whimsical word. Never include "FREE", "pattern", website names, colons, or ellipses.

        Tags should include: craft type, garment type, technique, season/occasion if applicable. Max 6 tags.

        VIDEO_URL: If "Video URLs found on page" is provided, pick the pattern tutorial. Otherwise null.

        CLEANED_CONTENT RULES:
        Start: Include from the first substantive pattern section. Omit long intro paragraphs.
        Keep: Materials, Gauge, Sizing tables (preserve ALL rows/columns with | separators), Construction notes, Abbreviations.
        End: STOP at the last actual instruction. Omit social/promo/nav content.
        Remove throughout: Nav links, menus, ads, affiliate disclosures, cookie notices, SEO filler, author bios, "You may also like".
        Use \\n\\n for paragraph breaks and \\n- for bullet items. Be THOROUGH. Do NOT summarize instructions.

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
        let parsedStepsJSON = encodeInstructionsJSON(json["instructions"]) ?? encodeStepsJSON(json["steps"])

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

    /// Attempts to repair truncated JSON by scanning for unmatched braces/brackets
    /// and closing them in LIFO order. This lets us salvage metadata fields (title, tags, gauge, etc.)
    /// even when cleaned_content was cut off mid-string.
    private static func repairTruncatedJSON(_ text: String) -> [String: Any]? {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences if present
        if json.hasPrefix("```") {
            json = json.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            json = json.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try as-is first
        if let result = tryParseJSON(json) { return result }

        // Track nesting by scanning character by character
        var stack: [Character] = []
        var inString = false
        var prevChar: Character = " "

        for char in json {
            if inString {
                if char == "\"" && prevChar != "\\" {
                    inString = false
                }
            } else {
                switch char {
                case "\"": inString = true
                case "{": stack.append("}")
                case "[": stack.append("]")
                case "}", "]":
                    if !stack.isEmpty { stack.removeLast() }
                default: break
                }
            }
            prevChar = char
        }

        // If we're inside a string, close it
        if inString { json += "\"" }

        // Remove trailing comma before closing
        json = json.replacingOccurrences(of: #",\s*$"#, with: "", options: .regularExpression)

        // Close all open structures in reverse (LIFO) order
        let closers = String(stack.reversed())
        json += closers

        if let result = tryParseJSON(json) { return result }

        // Aggressive fallback: find last complete key-value pair, truncate, re-close
        let lastCommaPatterns = ["\",", "null,", "true,", "false,", "],"]
        for pattern in lastCommaPatterns {
            if let lastRange = json.range(of: pattern, options: .backwards) {
                var truncated = String(json[json.startIndex..<lastRange.upperBound])
                truncated = truncated.replacingOccurrences(of: #",\s*$"#, with: "", options: .regularExpression)

                // Re-scan for open structures on the truncated string
                var fallbackStack: [Character] = []
                var fbInString = false
                var fbPrev: Character = " "
                for char in truncated {
                    if fbInString {
                        if char == "\"" && fbPrev != "\\" { fbInString = false }
                    } else {
                        switch char {
                        case "\"": fbInString = true
                        case "{": fallbackStack.append("}")
                        case "[": fallbackStack.append("]")
                        case "}", "]":
                            if !fallbackStack.isEmpty { fallbackStack.removeLast() }
                        default: break
                        }
                    }
                    fbPrev = char
                }
                if fbInString { truncated += "\"" }
                truncated += String(fallbackStack.reversed())

                if let result = tryParseJSON(truncated) { return result }
            }
        }

        return nil
    }

    private static func tryParseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Encodes v2 instruction-level format for DB storage. Preserves chart fields when present.
    private static func encodeInstructionsJSON(_ value: Any?) -> String? {
        guard let arr = value as? [[String: Any]], !arr.isEmpty else { return nil }
        guard let first = arr.first, first["section"] != nil, first["instruction"] != nil else { return nil }
        let instructions: [[String: Any]] = arr.compactMap { item in
            guard let section = item["section"] as? String, !section.isEmpty,
                  let instruction = item["instruction"] as? String, !instruction.isEmpty else { return nil }
            var obj: [String: Any] = [
                "section": section,
                "start_row": (item["start_row"] as? Int) ?? 0,
                "end_row": (item["end_row"] as? Int) ?? 0,
                "instruction": instruction
            ]
            if let sc = item["stitch_count"] as? Int { obj["stitch_count"] = sc }
            if let note = item["note"] as? String, !note.isEmpty { obj["note"] = note }
            if let chartIdx = item["chart_image_index"] as? Int { obj["chart_image_index"] = chartIdx }
            if let chartLabel = item["chart_label"] as? String, !chartLabel.isEmpty { obj["chart_label"] = chartLabel }
            if let chartCrop = item["chart_crop"] as? [String: Any] { obj["chart_crop"] = chartCrop }
            if let chartUrl = item["chart_image_url"] as? String, !chartUrl.isEmpty { obj["chart_image_url"] = chartUrl }
            return obj
        }
        guard !instructions.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: instructions),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    /// Encodes v1 step format (legacy fallback when AI returns old-style steps).
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
