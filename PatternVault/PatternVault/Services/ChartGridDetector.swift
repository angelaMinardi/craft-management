//
//  ChartGridDetector.swift
//  PatternVault
//
//  Focused AI second-pass for precise grid boundary detection.
//  Takes a cropped chart image and asks Gemini to identify exactly where
//  the grid cells are, excluding labels, numbers, legends, and titles.
//
//  This replaces pixel-based approaches which couldn't reliably distinguish
//  grid cells from adjacent text labels at similar density.
//

import UIKit

struct ChartGridDetector {

    struct DetectedBoundary {
        let left: Double
        let top: Double
        let right: Double
        let bottom: Double
        let confidence: Double
    }

    /// Sends the cropped chart image to Gemini with a focused prompt asking
    /// specifically for the grid cell boundary within the image.
    static func detectGridBoundary(
        image: UIImage,
        expectedRows: Int? = nil,
        expectedCols: Int? = nil
    ) async -> DetectedBoundary? {
        #if DEBUG
        print("[GridDetector] Starting AI second-pass for \(Int(image.size.width))x\(Int(image.size.height)) image")
        #endif
        guard let imageData = image.pngData() ?? image.jpegData(compressionQuality: 0.9) else {
            #if DEBUG
            print("[GridDetector] Failed to encode image as PNG/JPEG")
            #endif
            return nil
        }
        #if DEBUG
        print("[GridDetector] Image encoded: \(imageData.count) bytes")
        #endif
        guard let apiKey = geminiApiKey else {
            #if DEBUG
            print("[GridDetector] No Gemini API key available")
            #endif
            return nil
        }

        let rowHint = expectedRows.map { "The grid has \($0) rows. " } ?? ""
        let colHint = expectedCols.map { "The grid has \($0) columns. " } ?? ""

        let prompt = """
        This image is a cropped region from a knitting/crochet pattern PDF containing a stitch chart. \
        \(rowHint)\(colHint)\
        The image includes the chart grid (the rectangular block of colored cells/squares representing stitches) \
        and may also include: a chart title above, column numbers along the top and/or bottom, \
        row numbers along the left and/or right, and a Key/Legend area showing color or symbol definitions.

        YOUR TASK: Return the PRECISE bounding box of ONLY the rectangular grid of stitch cells. \
        This must EXCLUDE all labels, numbers, titles, legends, and whitespace.

        Return a single JSON object with normalized coordinates (0.0 to 1.0):
        {"x_min": 0.05, "y_min": 0.15, "x_max": 0.65, "y_max": 0.95}

        Where:
        - "x_min": left edge of the grid as a fraction of image width (0.0 = left edge of image)
        - "y_min": top edge of the grid as a fraction of image height (0.0 = top edge of image)
        - "x_max": right edge of the grid as a fraction of image width (1.0 = right edge of image)
        - "y_max": bottom edge of the grid as a fraction of image height (1.0 = bottom edge of image)

        x_min < x_max and y_min < y_max. The grid area is the rectangle from (x_min, y_min) to (x_max, y_max).

        Example: a chart where the grid cells start at 5% from the left, 15% from the top, \
        end at 65% from the left, and 95% from the top: \
        {"x_min": 0.05, "y_min": 0.15, "x_max": 0.65, "y_max": 0.95}

        CRITICAL RULES:
        - The bounding box must tightly wrap ONLY the colored stitch cells/squares
        - EXCLUDE row numbers printed to the left or right of the grid
        - EXCLUDE column numbers printed above or below the grid
        - EXCLUDE the chart title text
        - EXCLUDE any Key/Legend area (color swatches, symbol definitions)
        - EXCLUDE whitespace margins
        - Values should be precise to 3 decimal places
        - All four values must be > 0 (there is always SOME non-grid content around the edges)
        """

        // Build request body directly — don't use shared helper which sets thinkingBudget:0
        // that may conflict with the small output token budget needed here.
        let base64Image = imageData.base64EncodedString()
        let mimeType = imageData.count >= 4 && imageData[0] == 0x89 && imageData[1] == 0x50 ? "image/png" : "image/jpeg"

        let requestBody: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": mimeType, "data": base64Image]]
                ]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "maxOutputTokens": 2048,
                "thinkingConfig": ["thinkingBudget": 0]
            ]
        ]

        do {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent") else { return nil }
            guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
                #if DEBUG
                print("[GridDetector] Failed to serialize request body")
                #endif
                return nil
            }

            #if DEBUG
            print("[GridDetector] Sending \(bodyData.count) byte request to Gemini...")
            #endif

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.timeoutInterval = 60

            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            print("[GridDetector] Gemini responded: HTTP \(code), \(data.count) bytes")
            #endif

            guard (200...299).contains(code) else {
                #if DEBUG
                if let errorText = String(data: data.prefix(500), encoding: .utf8) {
                    print("[GridDetector] Error response: \(errorText)")
                }
                #endif
                return nil
            }

            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                print("[GridDetector] Failed to parse response as JSON")
                #endif
                return nil
            }
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let contentObj = first["content"] as? [String: Any],
                  let parts = contentObj["parts"] as? [[String: Any]] else {
                #if DEBUG
                print("[GridDetector] Could not extract parts from response. Keys: \(json.keys.sorted())")
                if let candidates = json["candidates"] as? [[String: Any]], let first = candidates.first {
                    print("[GridDetector] First candidate keys: \(first.keys.sorted())")
                }
                #endif
                return nil
            }

            let outputPart = parts.last(where: { ($0["thought"] as? Bool) != true && $0["text"] != nil })
            guard var text = outputPart?["text"] as? String else {
                #if DEBUG
                print("[GridDetector] No text part found. Parts count: \(parts.count), types: \(parts.map { $0.keys.sorted() })")
                #endif
                return nil
            }

            // Strip markdown fences if present
            if text.hasPrefix("```") {
                text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            #if DEBUG
            print("[GridDetector] Raw AI response text: \(text.prefix(300))")
            #endif

            guard let jsonData = text.data(using: .utf8) else { return nil }

            // Try parsing as x_min/y_min/x_max/y_max (preferred), then as left/top/right/bottom (legacy)
            let bbox: BBoxResponse
            if let single = try? JSONDecoder().decode(BBoxResponse.self, from: jsonData) {
                bbox = single
            } else if let array = try? JSONDecoder().decode([BBoxResponse].self, from: jsonData),
                      let first = array.first {
                bbox = first
            } else if let legacy = try? JSONDecoder().decode(LegacyBBoxResponse.self, from: jsonData) {
                // AI may use left/top/right/bottom as coordinates despite prompt asking for x_min/x_max
                bbox = BBoxResponse(xMin: legacy.left, yMin: legacy.top, xMax: legacy.right, yMax: legacy.bottom)
            } else if let legacyArr = try? JSONDecoder().decode([LegacyBBoxResponse].self, from: jsonData),
                      let first = legacyArr.first {
                bbox = BBoxResponse(xMin: first.left, yMin: first.top, xMax: first.right, yMax: first.bottom)
            } else {
                #if DEBUG
                print("[GridDetector] Failed to decode response JSON")
                #endif
                return nil
            }

            // Validate: x_min < x_max, y_min < y_max, all in 0-1 range
            guard bbox.xMin >= 0, bbox.yMin >= 0, bbox.xMax <= 1.01, bbox.yMax <= 1.01,
                  bbox.xMin < bbox.xMax, bbox.yMin < bbox.yMax,
                  (bbox.xMax - bbox.xMin) > 0.05, (bbox.yMax - bbox.yMin) > 0.05 else {
                #if DEBUG
                print("[GridDetector] Invalid bbox: xMin=\(bbox.xMin) yMin=\(bbox.yMin) xMax=\(bbox.xMax) yMax=\(bbox.yMax)")
                #endif
                return nil
            }

            // Convert from coordinates to insets
            let leftInset = bbox.xMin
            let topInset = bbox.yMin
            let rightInset = max(0, 1.0 - bbox.xMax)
            let bottomInset = max(0, 1.0 - bbox.yMax)

            #if DEBUG
            print("""
            [GridDetector] AI second-pass boundary:
              bbox = (\(String(format:"%.3f",bbox.xMin)), \(String(format:"%.3f",bbox.yMin))) – (\(String(format:"%.3f",bbox.xMax)), \(String(format:"%.3f",bbox.yMax)))
              insets = (L:\(String(format:"%.3f",leftInset)), T:\(String(format:"%.3f",topInset)), R:\(String(format:"%.3f",rightInset)), B:\(String(format:"%.3f",bottomInset)))
            """)
            #endif

            return DetectedBoundary(
                left: leftInset,
                top: topInset,
                right: rightInset,
                bottom: bottomInset,
                confidence: 0.8
            )

        } catch {
            #if DEBUG
            print("[GridDetector] Error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Refines grid boundary within a user-selected region by running AI detection
    /// on a cropped sub-image. Returns insets normalized to the FULL image.
    static func refineWithinRegion(
        image: UIImage,
        regionLeft: Double,
        regionTop: Double,
        regionRight: Double,
        regionBottom: Double,
        expectedRows: Int? = nil,
        expectedCols: Int? = nil
    ) async -> DetectedBoundary? {
        guard let cgImage = image.cgImage else { return nil }
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)

        // Crop to the user's selection
        let cropRect = CGRect(
            x: regionLeft * w,
            y: regionTop * h,
            width: (1.0 - regionLeft - regionRight) * w,
            height: (1.0 - regionTop - regionBottom) * h
        )
        guard cropRect.width > 20, cropRect.height > 20,
              let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let subImage = UIImage(cgImage: cropped)

        // Run AI detection on the sub-image
        guard let subResult = await detectGridBoundary(
            image: subImage,
            expectedRows: expectedRows,
            expectedCols: expectedCols
        ) else { return nil }

        // Convert sub-image insets back to full-image insets
        let subW = 1.0 - regionLeft - regionRight
        let subH = 1.0 - regionTop - regionBottom
        let fullLeft = regionLeft + subResult.left * subW
        let fullTop = regionTop + subResult.top * subH
        let fullRight = regionRight + subResult.right * subW
        let fullBottom = regionBottom + subResult.bottom * subH

        return DetectedBoundary(
            left: fullLeft, top: fullTop,
            right: fullRight, bottom: fullBottom,
            confidence: subResult.confidence
        )
    }

    // MARK: - Private

    private struct BBoxResponse: Decodable {
        let xMin: Double
        let yMin: Double
        let xMax: Double
        let yMax: Double

        enum CodingKeys: String, CodingKey {
            case xMin = "x_min"
            case yMin = "y_min"
            case xMax = "x_max"
            case yMax = "y_max"
        }

        init(xMin: Double, yMin: Double, xMax: Double, yMax: Double) {
            self.xMin = xMin; self.yMin = yMin; self.xMax = xMax; self.yMax = yMax
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            xMin = try c.decode(Double.self, forKey: .xMin)
            yMin = try c.decode(Double.self, forKey: .yMin)
            xMax = try c.decode(Double.self, forKey: .xMax)
            yMax = try c.decode(Double.self, forKey: .yMax)
        }
    }

    /// Fallback decoder for when AI returns left/top/right/bottom instead of x_min/y_min/x_max/y_max
    private struct LegacyBBoxResponse: Decodable {
        let left: Double
        let top: Double
        let right: Double
        let bottom: Double
    }

    private static var geminiApiKey: String? {
        let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        guard let key, !key.isEmpty, key != "placeholder" else { return nil }
        return key
    }
}
