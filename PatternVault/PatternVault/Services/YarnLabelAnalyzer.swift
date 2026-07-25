//
//  YarnLabelAnalyzer.swift
//  PatternVault
//
//  Reads a photo of a yarn label with Gemini 2.5 Flash and extracts structured
//  fields (brand, color, weight, fiber, yardage, dye lot) to auto-fill the stash
//  form. Far more reliable than barcode lookup for yarn, since the info is always
//  printed on the band even when no barcode resolves in any public database.
//

import Foundation
import UIKit

enum YarnLabelAnalyzerError: Error, LocalizedError {
    case noApiKey
    case aiDisabled
    case apiError(String)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "AI is not configured."
        case .aiDisabled: return "Label scanning is temporarily unavailable. Try again later."
        case .apiError(let msg): return msg
        case .parseFailed: return "Couldn't read the label. Try a clearer, straight-on photo."
        }
    }
}

/// Structured result of reading a yarn label. All fields optional — the model
/// returns null for anything not legible on the label.
struct YarnLabelInfo: Decodable, Sendable {
    let brand: String?
    let productName: String?
    let colorName: String?
    let weight: String?
    let fiberContent: String?
    let yardagePerSkein: Int?
    let dyeLot: String?

    enum CodingKeys: String, CodingKey {
        case brand
        case productName = "product_name"
        case colorName = "color_name"
        case weight
        case fiberContent = "fiber_content"
        case yardagePerSkein = "yardage_per_skein"
        case dyeLot = "dye_lot"
    }

    /// Combined "Brand + line name" for the stash item's brand/name field.
    var displayBrand: String? {
        let parts = [brand, productName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    var isEmpty: Bool {
        displayBrand == nil
            && (colorName?.isEmpty ?? true)
            && (weight?.isEmpty ?? true)
            && (fiberContent?.isEmpty ?? true)
            && yardagePerSkein == nil
            && (dyeLot?.isEmpty ?? true)
    }
}

enum YarnLabelAnalyzer {

    private static var geminiApiKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        guard let key, !key.isEmpty, key != "placeholder" else { return nil }
        return key
    }

    static var isAvailable: Bool { geminiApiKey != nil }

    /// Analyze a yarn-label photo and extract structured fields.
    static func analyze(imageData: Data) async throws -> YarnLabelInfo {
        guard AIKillSwitchService.isAIEnabled else { throw YarnLabelAnalyzerError.aiDisabled }
        guard let key = geminiApiKey else { throw YarnLabelAnalyzerError.noApiKey }

        let prepared = downscaledJPEG(from: imageData) ?? imageData
        let images = GeminiMultimodalRequest.imageInputs(from: [prepared])
        let requestBody = GeminiMultimodalRequest.buildRequestBody(
            prompt: prompt,
            images: images,
            maxOutputTokens: 1024,
            thinkingBudget: 0,
            temperature: 0.0
        )
        return try await callGemini(requestBody: requestBody, apiKey: key)
    }

    // MARK: - Gemini call

    private static func callGemini(requestBody: [String: Any], apiKey: String) async throws -> YarnLabelInfo {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"),
              let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw YarnLabelAnalyzerError.parseFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            #if DEBUG
            print("[YarnLabelAnalyzer] Gemini HTTP \(code)")
            #endif
            throw YarnLabelAnalyzerError.apiError(userMessageForHTTPStatus(code))
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let contentObj = first["content"] as? [String: Any],
              let parts = contentObj["parts"] as? [[String: Any]] else {
            throw YarnLabelAnalyzerError.parseFailed
        }

        let outputPart = parts.last(where: { ($0["thought"] as? Bool) != true && $0["text"] != nil })
        guard var text = outputPart?["text"] as? String else {
            throw YarnLabelAnalyzerError.parseFailed
        }

        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let jsonData = text.data(using: .utf8) else { throw YarnLabelAnalyzerError.parseFailed }

        do {
            // Sanitize through JSONSerialization first (last-value-wins on duplicate keys)
            // to avoid JSONDecoder crashes — same guard used in AIStepParserService.
            let sanitized = try JSONSerialization.jsonObject(with: jsonData, options: .fragmentsAllowed)
            let cleanData = try JSONSerialization.data(withJSONObject: sanitized)
            return try JSONDecoder().decode(YarnLabelInfo.self, from: cleanData)
        } catch {
            #if DEBUG
            print("[YarnLabelAnalyzer] decode failed: \(error); raw: \(String(text.prefix(400)))")
            #endif
            throw YarnLabelAnalyzerError.parseFailed
        }
    }

    // MARK: - Image prep

    /// Downscale and JPEG-compress so the inline image payload stays small.
    private static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maxDimension / longest)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }

    // MARK: - Prompt

    private static let prompt = """
    You are reading a photo of a YARN LABEL / ball band. Extract the product details \
    printed on the label. Return ONLY a single JSON object (no markdown fences, no array) \
    with exactly these keys:

    {
      "brand": "manufacturer/brand name, e.g. Hobbii, Lion Brand, Malabrigo — or null",
      "product_name": "the yarn line/range name, e.g. Friends Cotton, Wool-Ease, Rios — or null",
      "color_name": "the colour name or colour number shown, e.g. Lavender or 39 — or null",
      "weight": "yarn weight category if shown, e.g. DK, Worsted, Aran, Fingering, 4-ply — or null",
      "fiber_content": "fiber composition, e.g. 100% Cotton or 80% Wool, 20% Nylon — or null",
      "yardage_per_skein": yards per ball/skein as an integer, or null,
      "dye_lot": "the dye lot / lot number if shown, e.g. 35501 — or null"
    }

    RULES:
    - Only report what is actually legible on the label. Use null for anything you cannot read. Do NOT guess or invent.
    - "color_name": if only a colour NUMBER is printed (e.g. "COLOR: 39"), return that number as a string ("39").
    - "yardage_per_skein": labels often print length in METERS. If only meters are shown, convert to yards \
    (yards = meters × 1.0936) and round to the nearest whole number. If both are shown, prefer the yards value. \
    Return just the number, no units.
    - "dye_lot": look for "Lot", "Dye Lot", "Batch", or similar.
    - Ignore certifications (e.g. OEKO-TEX), care symbols, websites, and barcodes — they are not requested fields.
    """

    private static func userMessageForHTTPStatus(_ code: Int) -> String {
        switch code {
        case 429: return "Rate limit reached. Try again in a few minutes."
        case 401: return "Invalid AI key. Check your config."
        case 503: return "AI service is temporarily unavailable. Try again later."
        default: return "Label read failed (HTTP \(code)). Try again."
        }
    }
}
