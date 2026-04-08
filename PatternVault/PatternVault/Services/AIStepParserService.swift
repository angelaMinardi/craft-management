//
//  AIStepParserService.swift
//  PatternVault
//
//  On-demand AI caller that parses pattern content into structured, row-aware instructions.
//  Uses Gemini 2.5 Flash. Produces ParsedInstruction (v2) format.
//  Supports multimodal input (text + images) for automatic chart detection.
//  Detected charts are returned as DetectedChart metadata for creating ChartHighlight objects.
//

import Foundation

enum AIStepParserError: Error, LocalizedError {
    case noApiKey
    case emptyContent
    case apiError(String)
    case parseFailed
    case aiTemporarilyUnavailable

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "AI API key not configured."
        case .emptyContent: return "No pattern content to analyze."
        case .apiError(let msg): return "AI error: \(msg)"
        case .parseFailed: return "Could not parse AI response."
        case .aiTemporarilyUnavailable: return "Step analysis is temporarily unavailable. Try again next month."
        }
    }
}

enum AIStepParserService {
    private static func debugLog(_ message: String) {
        #if DEBUG
        print(message)
        #endif
    }

    private static var geminiApiKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        guard let key, !key.isEmpty, key != "placeholder" else { return nil }
        return key
    }

    static var isAIStepAnalysisAvailable: Bool {
        geminiApiKey != nil
    }

    // MARK: - Public API

    /// Parses pattern content into structured instructions (text-only, no chart detection).
    static func parseInstructions(from content: String) async throws -> [ParsedInstruction] {
        if !AIKillSwitchService.isAIEnabled {
            throw AIStepParserError.aiTemporarilyUnavailable
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIStepParserError.emptyContent }

        let maxChars = 100_000
        let inputContent = trimmed.count > maxChars ? String(trimmed.prefix(maxChars)) : trimmed

        guard let key = geminiApiKey else { throw AIStepParserError.noApiKey }
        let prompt = buildInstructionPrompt(content: inputContent, hasImages: false)
        let requestBody = GeminiMultimodalRequest.buildTextOnlyRequestBody(prompt: prompt, maxOutputTokens: 8192)
        let rawInstructions: [ChartImageProcessor.RawInstruction] = try await callGemini(requestBody: requestBody, apiKey: key)
        return ChartImageProcessor.rawToInstructions(rawInstructions)
    }

    /// Result of parsing instructions with images — includes both the instructions and any detected chart metadata.
    struct ParseResult: Sendable {
        let instructions: [ParsedInstruction]
        let detectedCharts: [DetectedChart]
    }

    /// Parses pattern content with images for chart detection.
    /// Returns instructions and chart metadata separately — charts are handled via ChartHighlight, not URLs.
    static func parseInstructionsWithCharts(
        from content: String,
        images: [Data]
    ) async throws -> ParseResult {
        if !AIKillSwitchService.isAIEnabled {
            throw AIStepParserError.aiTemporarilyUnavailable
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIStepParserError.emptyContent }
        guard let key = geminiApiKey else { throw AIStepParserError.noApiKey }

        let maxChars = 100_000
        let inputContent = trimmed.count > maxChars ? String(trimmed.prefix(maxChars)) : trimmed

        let hasImages = !images.isEmpty
        let prompt = buildInstructionPrompt(content: inputContent, hasImages: hasImages, imageCount: images.count)

        let requestBody: [String: Any]
        if hasImages {
            let imageInputs = GeminiMultimodalRequest.imageInputs(from: images)
            requestBody = GeminiMultimodalRequest.buildRequestBody(prompt: prompt, images: imageInputs, maxOutputTokens: 8192)
            debugLog("[AIStepParser] Multimodal request with \(images.count) images")
        } else {
            requestBody = GeminiMultimodalRequest.buildTextOnlyRequestBody(prompt: prompt, maxOutputTokens: 4096)
        }

        let rawInstructions: [ChartImageProcessor.RawInstruction] = try await callGemini(requestBody: requestBody, apiKey: key)
        let instructions = ChartImageProcessor.rawToInstructions(rawInstructions)
        let charts = extractChartMetadata(from: rawInstructions, imageCount: images.count)

        return ParseResult(instructions: instructions, detectedCharts: charts)
    }

    /// Chart-detection-only pass: takes page images and section names, identifies charts,
    /// and returns structured metadata for creating ChartHighlight objects.
    static func detectCharts(
        sectionNames: [String],
        images: [Data]
    ) async throws -> [DetectedChart] {
        guard !images.isEmpty else { return [] }
        guard let key = geminiApiKey else { throw AIStepParserError.noApiKey }

        let prompt = buildChartDetectionPrompt(sectionNames: sectionNames, imageCount: images.count)
        let imageInputs = GeminiMultimodalRequest.imageInputs(from: images)
        let requestBody = GeminiMultimodalRequest.buildRequestBody(prompt: prompt, images: imageInputs, maxOutputTokens: 4096)

        debugLog("[ChartDetect] Sending chart detection request with \(images.count) images, \(sectionNames.count) sections")
        let mappings: [ChartMapping] = try await callGemini(requestBody: requestBody, apiKey: key)
        debugLog("[ChartDetect] Got \(mappings.count) chart mapping(s)")

        return mappings.compactMap { mapping in
            guard mapping.chartImageIndex >= 0, mapping.chartImageIndex < images.count else { return nil }
            let crop = mapping.chartCrop ?? ChartImageProcessor.ChartCropRect(x: 0, y: 0, w: 1, h: 1)
            if let cc = mapping.chartCrop {
                let gbStr: String
                if let gb = mapping.gridBoundary {
                    gbStr = "(x:\(String(format:"%.3f",gb.x)), y:\(String(format:"%.3f",gb.y)), w:\(String(format:"%.3f",gb.w)), h:\(String(format:"%.3f",gb.h)))"
                } else {
                    gbStr = "nil"
                }
                debugLog("[ChartDetect] \(mapping.chartLabel): crop=(x:\(String(format:"%.3f",cc.x)), y:\(String(format:"%.3f",cc.y)), w:\(String(format:"%.3f",cc.w)), h:\(String(format:"%.3f",cc.h))), grid_boundary=\(gbStr)")
            }
            return DetectedChart(
                chartImageIndex: mapping.chartImageIndex,
                chartLabel: mapping.chartLabel,
                chartCrop: crop,
                gridBoundary: mapping.gridBoundary,
                chartRows: mapping.chartRows ?? 1,
                chartColumns: mapping.chartColumns ?? 1,
                matchingSection: mapping.matchingSection,
                rowNumberPosition: mapping.rowNumberPosition,
                colNumberPosition: mapping.colNumberPosition,
                hasLegend: mapping.hasLegend ?? false,
                legendPosition: mapping.legendPosition,
                sizeVariants: mapping.sizeVariants
            )
        }
    }

    /// Extracts DetectedChart metadata from RawInstruction chart references (wand-button path).
    static func extractChartMetadata(from rawInstructions: [ChartImageProcessor.RawInstruction], imageCount: Int) -> [DetectedChart] {
        var seen = Set<String>()
        var results: [DetectedChart] = []
        for raw in rawInstructions {
            guard let idx = raw.chartImageIndex, idx >= 0, idx < imageCount else { continue }
            let label = raw.chartLabel ?? raw.section
            let key = "\(idx)-\(label)"
            guard seen.insert(key).inserted else { continue }
            let crop = raw.chartCrop ?? ChartImageProcessor.ChartCropRect(x: 0, y: 0, w: 1, h: 1)
            results.append(DetectedChart(
                chartImageIndex: idx,
                chartLabel: label,
                chartCrop: crop,
                gridBoundary: raw.gridBoundary,
                chartRows: raw.chartRows ?? 1,
                chartColumns: raw.chartColumns ?? 1,
                matchingSection: raw.section,
                rowNumberPosition: raw.rowNumberPosition,
                colNumberPosition: raw.colNumberPosition,
                hasLegend: raw.hasLegend ?? false,
                legendPosition: raw.legendPosition,
                sizeVariants: nil
            ))
        }
        return results
    }

    /// Legacy wrapper that converts v2 instructions to v1 ParsedStep.
    static func parseSteps(from content: String) async throws -> [ParsedStep] {
        let instructions = try await parseInstructions(from: content)
        return instructions.map { inst in
            ParsedStep(title: inst.toPatternStep().title, body: inst.toPatternStep().body)
        }
    }

    // MARK: - Gemini API Call

    private static func callGemini<T: Decodable>(requestBody: [String: Any], apiKey: String) async throws -> [T] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent") else {
            throw AIStepParserError.parseFailed
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AIStepParserError.parseFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 90

        debugLog("[AIStepParser] Sending request to Gemini (\(bodyData.count) bytes)...")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            debugLog("[AIStepParser] Gemini API error: HTTP \(code), bytes=\(data.count)")
            throw AIStepParserError.apiError(userMessageForHTTPStatus(code))
        }
        debugLog("[AIStepParser] Got 200 OK from Gemini")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let contentObj = first["content"] as? [String: Any],
              let parts = contentObj["parts"] as? [[String: Any]] else {
            debugLog("[AIStepParser] Could not extract parts from Gemini response")
            throw AIStepParserError.parseFailed
        }

        let outputPart = parts.last(where: { ($0["thought"] as? Bool) != true && $0["text"] != nil })
        guard var text = outputPart?["text"] as? String else {
            debugLog("[AIStepParser] Could not extract text from Gemini response parts")
            throw AIStepParserError.parseFailed
        }

        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let jsonData = text.data(using: .utf8) else { throw AIStepParserError.parseFailed }

        do {
            let results = try JSONDecoder().decode([T].self, from: jsonData)
            debugLog("[AIStepParser] Decoded \(results.count) items from Gemini response")
            return results
        } catch {
            debugLog("[AIStepParser] JSON decode failed: \(error)")
            debugLog("[AIStepParser] Raw text (first 500 chars): \(String(text.prefix(500)))")
            throw AIStepParserError.parseFailed
        }
    }

    // MARK: - Prompt

    private static func buildInstructionPrompt(content: String, hasImages: Bool, imageCount: Int = 0) -> String {
        let chartPromptSection: String
        if hasImages {
            chartPromptSection = """

            CHART DETECTION (images are provided):
            I have also provided \(imageCount) page images from this pattern document (numbered starting at 0).
            Examine EVERY image carefully, especially the LAST few pages — craft patterns commonly place charts at the end.

            What to look for:
            - Stitch charts: grids where each cell represents a stitch, with symbols or colored squares
            - Colorwork charts: grids of colored cells showing a knitting/crochet color pattern
            - Construction diagrams: schematic drawings showing shaping or assembly

            For each instruction that references or requires a chart, include these additional fields:
            - "chart_image_index": the 0-based index of the image containing the chart
            - "chart_label": a short descriptive name for the chart (e.g., "Skull Sampler Toe Chart")
            - "chart_crop": {"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0} — normalized bounding box (0.0 to 1.0) of the ENTIRE chart region (including row/column numbers and legend). Be generous with margins.
            - "chart_rows": number of grid rows (count actual grid cells, not row labels)
            - "chart_columns": number of grid columns (count actual grid cells, not column labels)
            - "grid_boundary": {"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0} — normalized bounding box of ONLY the grid cells, excluding row/column numbers and legend/key. Must be STRICTLY INSIDE chart_crop and meaningfully smaller. COMMON MISTAKE: if grid_boundary is nearly identical to chart_crop, you have NOT excluded the numbers/legend — grid_boundary.w should be noticeably smaller when a legend or row numbers are present.
            - "row_number_position": where row numbers appear — "left", "right", "both", or "none"
            - "col_number_position": where column numbers appear — "top", "bottom", "both", or "none"
            - "has_legend": true if the chart has a Key/Legend area
            - "legend_position": "right", "bottom", "left", "top", or null
            If an instruction does not reference a chart, omit all chart fields entirely.
            Do NOT reference the same chart image for instructions that don't actually use that chart.
            """
        } else {
            chartPromptSection = ""
        }

        return """
        You are an expert craft pattern parser. Extract every individual working instruction from this pattern content.

        Return ONLY a valid JSON array of instruction objects. No markdown fences, no wrapper object.

        Each object:
        {
          "section": "Section Name",
          "start_row": 0,
          "end_row": 0,
          "instruction": "Full instruction text exactly as written",
          "stitch_count": null,
          "note": null
        }

        SECTION RULES:
        - Group instructions under the construction section they belong to.
        - Use the pattern's own section headings when present (e.g., "Toe", "Heel Flap", "Heel Turn", "Gusset", "Foot", "Leg", "Cuff").
        - When no headings exist, infer logical sections from context (e.g., "Cast On", "Body", "Shaping", "Finishing").
        - Keep section names short (1-4 words). Capitalize naturally: "Heel Flap" not "HEEL FLAP".
        - If row/round numbering restarts within a single named section (e.g., two separate "Row 1" entries under "Heel"), split into descriptive sub-sections so each phase has a unique name (e.g., "Heel Short Rows" and "Heel Closing").
        - Do NOT create sections for reference material (Materials, Gauge, Abbreviations, Notes). Skip those entirely.

        ROW/ROUND NUMBER RULES:
        - Extract row or round numbers ONLY when explicitly stated in the text.
        - "Row 1: K across" → start_row: 1, end_row: 1
        - "Rnd 3 (increase): ..." → start_row: 3, end_row: 3
        - "Rows 18-39: Work chart" → start_row: 18, end_row: 39
        - "Rounds 1-11: ..." → start_row: 1, end_row: 11
        - When instructions have row labels like "Rnd 1", "Rnd 2" but the numbering resets per section, use the numbers as written (they restart at 1 for each section).
        - For setup, cast-on, "repeat until", transitions, or finishing instructions with no explicit row number: start_row: 0, end_row: 0.
        - NEVER invent or infer row numbers that aren't explicitly in the text.

        INSTRUCTION TEXT RULES:
        - Copy the COMPLETE instruction text. Do NOT summarize, paraphrase, abbreviate, or truncate.
        - Preserve all size variations in parentheses exactly: "CO 14 (16, 18) sts"
        - Preserve all stitch abbreviations exactly: k, p, kfb, ssk, k2tog, yo, sl1, etc.
        - Include the full row/round label as part of the instruction.
        - Each distinct row, round, or standalone instruction is its own entry.
        - "Repeat Rows 3 & 4 until..." is ONE instruction, not split across rows.
        - Multi-row instructions like "Work 14 rounds in stockinette stitch" are ONE instruction.

        STITCH COUNT RULES:
        - If the instruction explicitly states a resulting stitch count (e.g., "(56 sts)", "28 (32, 36) sts total"), extract the smallest size as an integer.
        - Otherwise null.

        NOTE RULES:
        - Use for important side information: "4 sts increased", "switch to larger needles", "do not cut yarn".
        - Only include notes that are separate from the instruction itself.
        - Otherwise null.

        WHAT TO EXCLUDE:
        - Materials, yarn requirements, gauge swatches
        - Abbreviation glossaries and stitch definitions
        - Sizing charts and measurement tables
        - Designer commentary, blog content, tips sections
        - Website navigation, ads, social media prompts

        ORDERING:
        - Instructions must appear in the order they should be worked.
        - Within each section, maintain the original sequence.
        \(chartPromptSection)

        Pattern content:
        \(content)
        """
    }

    // MARK: - Chart Detection

    struct DetectedChart: Sendable {
        let chartImageIndex: Int
        let chartLabel: String
        let chartCrop: ChartImageProcessor.ChartCropRect
        let gridBoundary: ChartImageProcessor.ChartCropRect?
        let chartRows: Int
        let chartColumns: Int
        let matchingSection: String
        let rowNumberPosition: String?
        let colNumberPosition: String?
        let hasLegend: Bool
        let legendPosition: String?
        let sizeVariants: [SizeVariant]?
    }

    struct SizeVariant: Codable, Sendable {
        let sizeLabel: String
        let borderColor: String
        let startRow: Int
        let endRow: Int
        let startCol: Int
        let endCol: Int

        enum CodingKeys: String, CodingKey {
            case sizeLabel = "size_label"
            case borderColor = "border_color"
            case startRow = "start_row"
            case endRow = "end_row"
            case startCol = "start_col"
            case endCol = "end_col"
        }
    }

    private struct ChartMapping: Codable {
        let chartImageIndex: Int
        let chartLabel: String
        let chartCrop: ChartImageProcessor.ChartCropRect?
        let gridBoundary: ChartImageProcessor.ChartCropRect?
        let chartRows: Int?
        let chartColumns: Int?
        let matchingSection: String
        let rowNumberPosition: String?
        let colNumberPosition: String?
        let hasLegend: Bool?
        let legendPosition: String?
        let sizeVariants: [SizeVariant]?

        enum CodingKeys: String, CodingKey {
            case chartImageIndex = "chart_image_index"
            case chartLabel = "chart_label"
            case chartCrop = "chart_crop"
            case gridBoundary = "grid_boundary"
            case chartRows = "chart_rows"
            case chartColumns = "chart_columns"
            case matchingSection = "matching_section"
            case rowNumberPosition = "row_number_position"
            case colNumberPosition = "col_number_position"
            case hasLegend = "has_legend"
            case legendPosition = "legend_position"
            case sizeVariants = "size_variants"
        }
    }

    private static func buildChartDetectionPrompt(sectionNames: [String], imageCount: Int) -> String {
        let sectionList = sectionNames.isEmpty
            ? "(No named sections available — infer a descriptive label from chart content)"
            : sectionNames.map { "- \($0)" }.joined(separator: "\n")
        return """
        You are analyzing page images from a craft pattern PDF. I am providing \(imageCount) page images \
        (numbered 0 to \(imageCount - 1), representing consecutive pages of the document).

        YOUR TASK: Examine EVERY image carefully. Identify all stitch charts, colorwork charts, and \
        construction diagrams present in ANY image.

        WHAT CHARTS LOOK LIKE:
        - Stitch charts: grids/tables where each cell represents a stitch, often with symbols (X, O, /, \\, etc.)
        - Colorwork charts: grids of colored squares showing a color pattern to knit or crochet
        - Construction diagrams: schematic drawings showing shaping, measurements, or assembly
        - Charts are very commonly on the LAST page(s) of the pattern — examine those extra carefully

        For each chart found, return a JSON object with chart location, grid dimensions, and grid boundary.

        PRECISION IS CRITICAL: Report ALL coordinate values to 3 decimal places (e.g. 0.123, not 0.1).

        Return a JSON array:
        [
          {
            "chart_image_index": 5,
            "chart_label": "Skull Sampler Toe Chart",
            "chart_crop": {"x": 0.050, "y": 0.020, "w": 0.900, "h": 0.450},
            "chart_rows": 11,
            "chart_columns": 8,
            "grid_boundary": {"x": 0.150, "y": 0.080, "w": 0.600, "h": 0.380},
            "matching_section": "Skull Sampler Toe Colourwork Section",
            "row_number_position": "right",
            "col_number_position": "bottom",
            "has_legend": true,
            "legend_position": "right",
            "size_variants": null
          }
        ]

        FIELDS:
        - "chart_image_index": 0-based index of the page image containing this chart
        - "chart_label": descriptive name for the chart (from the pattern text or inferred)
        - "chart_crop": normalized bounding box (0.0–1.0) of the ENTIRE chart region within the page image, \
        including row numbers, column numbers, and any legend/key. Be generous — include a margin around the chart. \
        If the chart fills the full page, use {"x": 0, "y": 0, "w": 1, "h": 1}. \
        If multiple charts are on one page, define each one separately.
        - "chart_rows": number of grid rows in the chart (count the actual grid cells, not the row labels)
        - "chart_columns": number of grid columns in the chart (count the actual grid cells, not column labels)
        - "grid_boundary": normalized bounding box (0.0–1.0) of ONLY the grid cells within the page image. \
        Align to the OUTER EDGES of the outermost grid cells — if the grid has visible border lines, align to \
        the outside of those border lines. \
        This MUST EXCLUDE: (1) row numbers printed on the left or right side, (2) column numbers printed on \
        the top or bottom, (3) the entire Key/Legend area (e.g. "Key", color swatches, stitch symbol definitions), \
        (4) chart title text, (5) any notes or labels outside the grid. \
        The grid_boundary MUST be STRICTLY INSIDE the chart_crop — it should tightly wrap ONLY the rectangular \
        grid of stitch cells. If the chart has a Key/Legend on the right side, grid_boundary.w must be small \
        enough that the right edge stops before the Key area begins. This is critical for overlaying an \
        interactive grid precisely on the stitch cells. \
        COMMON MISTAKE: grid_boundary MUST be meaningfully SMALLER than chart_crop. If your \
        grid_boundary has nearly the same x, y, w, h as chart_crop, you have NOT properly \
        excluded the row numbers, column numbers, title, or legend. \
        Example: if chart_crop = {"x": 0.05, "y": 0.05, "w": 0.90, "h": 0.90} and the chart \
        has row numbers on the right (~5% width) and a Key/Legend (~25% width), \
        then grid_boundary.w should be roughly 0.60, NOT 0.90.
        - "matching_section": the section name from the list below that references or uses this chart. \
        Pick the BEST match. If a chart is referenced by name in the instructions (e.g., "work the Toe Chart"), \
        match it to the section that references it. If no sections are provided, use a descriptive label.
        - "row_number_position": where row numbers appear — "left", "right", "both", or "none"
        - "col_number_position": where column numbers appear — "top", "bottom", "both", or "none"
        - "has_legend": true if the chart has a Key/Legend area showing color/symbol definitions
        - "legend_position": position of the Key/Legend — "right", "bottom", "left", "top", or null if none
        - "size_variants": For charts with colored borders or outlines indicating different garment sizes \
        (e.g. Small in red, Medium in green, Large in blue), return an array of objects: \
        [{"size_label": "Small", "border_color": "red", "start_row": 1, "end_row": 30, "start_col": 4, "end_col": 32}]. \
        Row/column numbers are 1-based. Return null if no size variants exist.

        If NO charts are found in ANY image, return an empty array: []

        Instruction sections in this pattern:
        \(sectionList)
        """
    }

    /// Computes grid insets from chart_crop and grid_boundary (both in page coordinates).
    static func computeGridInsets(chartCrop: ChartImageProcessor.ChartCropRect, gridBoundary: ChartImageProcessor.ChartCropRect?) -> (left: Double, top: Double, right: Double, bottom: Double) {
        guard let gb = gridBoundary, chartCrop.w > 0, chartCrop.h > 0 else {
            return (0, 0, 0, 0)
        }
        let left = max(0, (gb.x - chartCrop.x) / chartCrop.w)
        let top = max(0, (gb.y - chartCrop.y) / chartCrop.h)
        let right = max(0, 1.0 - (gb.x + gb.w - chartCrop.x) / chartCrop.w)
        let bottom = max(0, 1.0 - (gb.y + gb.h - chartCrop.y) / chartCrop.h)
        return (min(left, 0.85), min(top, 0.85), min(right, 0.85), min(bottom, 0.85))
    }

    /// Validates that grid_boundary is (a) inside chart_crop and (b) meaningfully smaller.
    static func isGridBoundaryValid(
        chartCrop: ChartImageProcessor.ChartCropRect,
        gridBoundary: ChartImageProcessor.ChartCropRect
    ) -> Bool {
        let contained = gridBoundary.x >= chartCrop.x - 0.01
            && gridBoundary.y >= chartCrop.y - 0.01
            && (gridBoundary.x + gridBoundary.w) <= (chartCrop.x + chartCrop.w) + 0.01
            && (gridBoundary.y + gridBoundary.h) <= (chartCrop.y + chartCrop.h) + 0.01
        let meaningfullySmaller = (gridBoundary.w / max(chartCrop.w, 0.001)) < 0.98
            || (gridBoundary.h / max(chartCrop.h, 0.001)) < 0.98
        if !contained || !meaningfullySmaller {
            debugLog("[ChartDetect] grid_boundary invalid: contained=\(contained), meaningfullySmaller=\(meaningfullySmaller)")
        }
        return contained && meaningfullySmaller
    }

    // MARK: - Helpers

    private static func userMessageForHTTPStatus(_ code: Int) -> String {
        switch code {
        case 429:
            return "Rate limit exceeded. Please try again in a few minutes."
        case 401:
            return "Invalid API key. Check your config."
        case 503:
            return "AI service is temporarily unavailable. Try again later."
        default:
            return "HTTP \(code). Try again later."
        }
    }
}
