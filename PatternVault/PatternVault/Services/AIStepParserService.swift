//
//  AIStepParserService.swift
//  PatternVault
//
//  On-demand AI API caller for parsing pattern content into structured steps.
//  Uses Gemini 2.0 Flash (GEMINI_API_KEY in Config/Info.plist).
//  Used in the main app when a pattern has no AI-parsed steps (e.g. imported before this feature).
//

import Foundation

enum AIStepParserError: Error, LocalizedError {
    case noApiKey
    case emptyContent
    case apiError(String)
    case parseFailed
    /// AI disabled via app_config kill switch (cost cap).
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

    private static var geminiApiKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        guard let key, !key.isEmpty, key != "placeholder" else { return nil }
        return key
    }

    /// True when Gemini API key is set (so the wand can run). Used by Settings to show a hint when not configured.
    static var isAIStepAnalysisAvailable: Bool {
        geminiApiKey != nil
    }

    static func parseSteps(from content: String) async throws -> [ParsedStep] {
        if !AIKillSwitchService.isAIEnabled {
            throw AIStepParserError.aiTemporarilyUnavailable
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIStepParserError.emptyContent }

        let maxChars = 8000
        let inputContent = trimmed.count > maxChars ? String(trimmed.prefix(maxChars)) : trimmed

        guard let key = geminiApiKey else { throw AIStepParserError.noApiKey }
        return try await parseStepsWithGemini(content: inputContent, apiKey: key)
    }

    private static func parseStepsWithGemini(content: String, apiKey: String) async throws -> [ParsedStep] {
        let systemPrompt = "You are a craft pattern analyzer. Given pattern content (knitting, crochet, sewing, etc.), break it into logical construction steps. Respond ONLY with a valid JSON array, no markdown fences. Steps are major construction phases (e.g. Base, Body, Handles, Finishing), not individual rows or rounds. Do NOT create steps for reference sections (Materials, Gauge, Sizes, Notes, PATTERN as a container, or technique subsections like SLIP STITCHES). Optionally emit one step titled \"Pattern details\" or \"Materials & gauge\" first with body containing materials/gauge/sizes/notes; then only construction steps."
        let userPrompt = buildStepParserUserPrompt(content: content)
        let fullPrompt = systemPrompt + "\n\n" + userPrompt
        let generationConfig: [String: Any] = [
            "responseMimeType": "application/json",
            "maxOutputTokens": 2048
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
        request.timeoutInterval = 30

        #if DEBUG
        print("[AIStepParser] Sending \(content.count) chars to Gemini API...")
        #endif
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            print("[AIStepParser] Gemini API error: HTTP \(code)")
            if let body = String(data: data, encoding: .utf8) { print("[AIStepParser] Response: \(body.prefix(200))") }
            #endif
            throw AIStepParserError.apiError(userMessageForHTTPStatus(code))
        }
        #if DEBUG
        print("[AIStepParser] Got 200 OK from Gemini")
        #endif

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let contentObj = first["content"] as? [String: Any],
              let parts = contentObj["parts"] as? [[String: Any]],
              let textPart = parts.first,
              var text = textPart["text"] as? String else {
            #if DEBUG
            print("[AIStepParser] Could not extract text from Gemini response")
            #endif
            throw AIStepParserError.parseFailed
        }

        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let jsonData = text.data(using: .utf8) else { throw AIStepParserError.parseFailed }
        return try JSONDecoder().decode([ParsedStep].self, from: jsonData)
    }

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

    private static func buildStepParserUserPrompt(content: String) -> String {
        """
        Break this craft pattern into 3-15 section-level construction steps in order. Return a JSON array:
        [{"title": "short step name (2-5 words)", "body": "full instructions for this phase (no length limit)"}]

        Rules:
        - Optional first step: One step titled "Pattern details" or "Materials & gauge" with body containing ONLY materials, gauge, sizes, and notes. Do NOT include the PATTERN heading or construction instructions (e.g. Base, Body) in Pattern details. Then only construction-phase steps.
        - Do NOT create separate steps for Materials, Gauge, Sizes, Notes, PATTERN (as a section header), or technique subsections (e.g. SLIP STITCHES).
        - Each step is one major phase (e.g. Base, Body, First Handle, Finishing). Do NOT create one step per "Row N" or "Round N"—group rows under the section they belong to.
        - title: Short section name (2-5 words). Use section headings from the text when present; otherwise a concise phase name. Do not use the full first line of an instruction as the title.
        - body: May contain full instructions for that phase (no length or summary-only requirement). Keep clarity; avoid truncating critical instructions. Use ALL CAPS for section labels, NOTE: for notes, - for bullets, and blank lines between sections.
        - If the content has no actual pattern instructions, return [].

        Pattern content:
        \(content)
        """
    }
}
