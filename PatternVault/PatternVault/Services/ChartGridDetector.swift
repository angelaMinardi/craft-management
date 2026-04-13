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

        let rowHint = expectedRows.map { "The grid is expected to have approximately \($0) rows. " } ?? ""
        let colHint = expectedCols.map { "The grid is expected to have approximately \($0) columns. " } ?? ""

        let prompt = """
        You are analyzing a cropped image from a knitting/crochet pattern PDF that contains a stitch chart.

        STRUCTURE OF A KNITTING CHART:
        A knitting chart has these distinct regions:
        1. THE GRID: A rectangular block of colored/filled squares (cells) arranged in rows and columns. \
        Each cell represents one stitch. In colorwork charts, cells are filled with solid colors. \
        In stitch charts, cells contain symbols. The grid has visible borders/gridlines.
        2. ROW NUMBERS: Small text numbers (1, 2, 3...) printed OUTSIDE the grid, running vertically \
        along the LEFT and/or RIGHT edge. These label which row is which. They are NOT part of the grid.
        3. COLUMN NUMBERS: Small text numbers (1, 2, 3...) printed OUTSIDE the grid, running horizontally \
        along the TOP and/or BOTTOM edge. These label which column is which. They are NOT part of the grid.
        4. TITLE: Text above the chart naming it (e.g. "Skull Sampler Leg").
        5. KEY/LEGEND: Color swatches with labels (e.g. "K with MC", "K with C1") usually to the right.

        \(rowHint)\(colHint)

        YOUR TASK: Return the bounding box of ONLY region #1 (the grid of colored cells). \
        The boundary must be at the OUTERMOST EDGE of the outermost grid cells — where the \
        grid cell borders are, NOT where the numbers begin.

        Look carefully at each edge:
        - TOP EDGE: Find the top border of the topmost row of cells. Numbers above this line are EXCLUDED.
        - BOTTOM EDGE: Find the bottom border of the bottommost row of cells. Numbers below this line are EXCLUDED.
        - LEFT EDGE: Find the left border of the leftmost column of cells. Numbers to the left are EXCLUDED.
        - RIGHT EDGE: Find the right border of the rightmost column of cells. Numbers to the right are EXCLUDED.

        Return a single JSON object with normalized coordinates (0.0 to 1.0):
        {"x_min": 0.05, "y_min": 0.15, "x_max": 0.65, "y_max": 0.95}

        Where x_min is the left edge, y_min is the top edge, x_max is the right edge, y_max is the bottom edge, \
        all as fractions of image width/height.

        CRITICAL: Row/column numbers are often printed DIRECTLY adjacent to the grid with very little gap. \
        You must still exclude them. The grid boundary is where the actual colored/filled stitch cells end, \
        not where the numbers begin. Look for the gridline or cell border, not the gap.
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

            // Refine AI boundary with pixel analysis.
            // The AI gets us in the right neighborhood (~85-90%); pixel analysis
            // finds the exact grid edge within a narrow search zone around each AI edge.
            let refined = refineWithPixels(
                image: image,
                aiBBox: (xMin: bbox.xMin, yMin: bbox.yMin, xMax: bbox.xMax, yMax: bbox.yMax)
            )
            let leftInset = max(0, refined.xMin)
            let topInset = max(0, refined.yMin)
            let rightInset = max(0, 1.0 - refined.xMax)
            let bottomInset = max(0, 1.0 - refined.yMax)

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

    /// Re-runs AI grid detection with user feedback about which edges are wrong.
    /// The feedback is injected into the prompt so the AI can correct specific edges.
    static func refineWithFeedback(
        image: UIImage,
        currentInsets: (left: Double, top: Double, right: Double, bottom: Double),
        feedback: String,
        expectedRows: Int? = nil,
        expectedCols: Int? = nil
    ) async -> DetectedBoundary? {
        guard let imageData = image.pngData() ?? image.jpegData(compressionQuality: 0.9),
              let apiKey = geminiApiKey else { return nil }

        let rowHint = expectedRows.map { "The grid has \($0) rows. " } ?? ""
        let colHint = expectedCols.map { "The grid has \($0) columns. " } ?? ""

        let prompt = """
        This image is a cropped chart from a knitting pattern. \(rowHint)\(colHint)\
        A previous attempt to detect the grid boundary produced these normalized insets:
        - left: \(String(format:"%.3f",currentInsets.left)) (grid starts \(String(format:"%.1f",currentInsets.left*100))% from left edge)
        - top: \(String(format:"%.3f",currentInsets.top)) (grid starts \(String(format:"%.1f",currentInsets.top*100))% from top edge)
        - right: \(String(format:"%.3f",currentInsets.right)) (grid ends \(String(format:"%.1f",(1-currentInsets.right)*100))% from left edge)
        - bottom: \(String(format:"%.3f",currentInsets.bottom)) (grid ends \(String(format:"%.1f",(1-currentInsets.bottom)*100))% from top edge)

        The user reports these issues with the current boundary:
        \(feedback)

        Please return CORRECTED coordinates. Return a single JSON object:
        {"x_min": 0.05, "y_min": 0.15, "x_max": 0.65, "y_max": 0.95}

        Where x_min/y_min is the top-left corner and x_max/y_max is the bottom-right corner \
        of ONLY the stitch grid cells. Exclude all row numbers, column numbers, titles, and Key/Legend areas.
        """

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
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"),
                  let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.timeoutInterval = 60

            #if DEBUG
            print("[GridDetector] Refine with feedback: \(feedback.prefix(100))...")
            #endif

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let contentObj = first["content"] as? [String: Any],
                  let parts = contentObj["parts"] as? [[String: Any]] else { return nil }

            let outputPart = parts.last(where: { ($0["thought"] as? Bool) != true && $0["text"] != nil })
            guard var text = outputPart?["text"] as? String else { return nil }

            if text.hasPrefix("```") {
                text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let jsonData = text.data(using: .utf8) else { return nil }
            let bbox: BBoxResponse
            if let single = try? JSONDecoder().decode(BBoxResponse.self, from: jsonData) {
                bbox = single
            } else if let legacy = try? JSONDecoder().decode(LegacyBBoxResponse.self, from: jsonData) {
                bbox = BBoxResponse(xMin: legacy.left, yMin: legacy.top, xMax: legacy.right, yMax: legacy.bottom)
            } else { return nil }

            guard bbox.xMin < bbox.xMax, bbox.yMin < bbox.yMax else { return nil }

            // Use AI values directly — no pixel refinement here.
            // The user's feedback gives the AI enough context to correct specific edges.
            // Pixel refinement would undo the corrections (its threshold doesn't adapt).
            #if DEBUG
            print("[GridDetector] Feedback result: (\(String(format:"%.3f",bbox.xMin)),\(String(format:"%.3f",bbox.yMin)))–(\(String(format:"%.3f",bbox.xMax)),\(String(format:"%.3f",bbox.yMax)))")
            #endif

            return DetectedBoundary(
                left: max(0, bbox.xMin), top: max(0, bbox.yMin),
                right: max(0, 1.0 - bbox.xMax), bottom: max(0, 1.0 - bbox.yMax),
                confidence: 0.85
            )
        } catch { return nil }
    }

    // MARK: - Pixel Refinement

    private struct RefinedBBox {
        let xMin: Double, yMin: Double, xMax: Double, yMax: Double
    }

    /// Refines each edge of the AI's bounding box using pixel density analysis.
    /// Searches a narrow zone (±10% of image dimension) around each AI edge to find
    /// the exact transition between dense grid content and sparse labels/whitespace.
    private static func refineWithPixels(
        image: UIImage,
        aiBBox: (xMin: Double, yMin: Double, xMax: Double, yMax: Double)
    ) -> RefinedBBox {
        guard let cgImage = image.cgImage else {
            return RefinedBBox(xMin: aiBBox.xMin, yMin: aiBBox.yMin, xMax: aiBBox.xMax, yMax: aiBBox.yMax)
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 40, height > 40 else {
            return RefinedBBox(xMin: aiBBox.xMin, yMin: aiBBox.yMin, xMax: aiBBox.xMax, yMax: aiBBox.yMax)
        }

        // Render to pixel buffer
        let bpp = 4
        let bytesPerRow = width * bpp
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return RefinedBBox(xMin: aiBBox.xMin, yMin: aiBBox.yMin, xMax: aiBBox.xMax, yMax: aiBBox.yMax)
        }
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Compute projection profiles
        var hProj = [Double](repeating: 0, count: height)  // per row
        var vProj = [Double](repeating: 0, count: width)   // per column

        // Only compute projections within the AI bbox ± margin to avoid legend/title influence
        let margin = 0.10
        let xLo = max(0, Int((aiBBox.xMin - margin) * Double(width)))
        let xHi = min(width, Int((aiBBox.xMax + margin) * Double(width)))
        let yLo = max(0, Int((aiBBox.yMin - margin) * Double(height)))
        let yHi = min(height, Int((aiBBox.yMax + margin) * Double(height)))

        // For projections, use the INNER 60% of the AI bbox on the cross-axis.
        // This excludes row numbers (contaminate hProj) and column numbers (contaminate vProj).
        let aiXLo = max(0, Int(aiBBox.xMin * Double(width)))
        let aiXHi = min(width, Int(aiBBox.xMax * Double(width)))
        let aiYLo = max(0, Int(aiBBox.yMin * Double(height)))
        let aiYHi = min(height, Int(aiBBox.yMax * Double(height)))

        let xSpan = aiXHi - aiXLo
        let ySpan = aiYHi - aiYLo
        let hProjXLo = aiXLo + xSpan / 5    // inner 60% of x-range
        let hProjXHi = aiXHi - xSpan / 5
        let vProjYLo = aiYLo + ySpan / 5    // inner 60% of y-range
        let vProjYHi = aiYHi - ySpan / 5

        // Horizontal projection: sum across inner columns only (exclude row numbers at edges)
        for y in yLo..<yHi {
            var sum = 0.0
            let rowOff = y * bytesPerRow
            for x in hProjXLo..<hProjXHi {
                let off = rowOff + x * bpp
                let lum = 0.299 * Double(pixels[off]) + 0.587 * Double(pixels[off+1]) + 0.114 * Double(pixels[off+2])
                sum += 1.0 - lum / 255.0
            }
            hProj[y] = sum / max(1, Double(hProjXHi - hProjXLo))
        }

        // Vertical projection: sum across inner rows only (exclude column number rows)
        for x in xLo..<xHi {
            var sum = 0.0
            for y in vProjYLo..<vProjYHi {
                let off = y * bytesPerRow + x * bpp
                let lum = 0.299 * Double(pixels[off]) + 0.587 * Double(pixels[off+1]) + 0.114 * Double(pixels[off+2])
                sum += 1.0 - lum / 255.0
            }
            vProj[x] = sum / max(1, Double(vProjYHi - vProjYLo))
        }

        // Also compute color-coverage profiles: fraction of pixels that are NOT white/near-white.
        // Grid cells (both colored and dark) have high coverage; row/column numbers are sparse text.
        // This helps distinguish grid edges from numbered labels on colorwork charts.
        var hCoverage = [Double](repeating: 0, count: height)
        var vCoverage = [Double](repeating: 0, count: width)
        let whiteThreshold = 230.0  // pixels brighter than this are "background"

        for y in yLo..<yHi {
            var nonWhite = 0
            let rowOff = y * bytesPerRow
            for x in hProjXLo..<hProjXHi {
                let off = rowOff + x * bpp
                let r = Double(pixels[off])
                let g = Double(pixels[off+1])
                let b = Double(pixels[off+2])
                if r < whiteThreshold || g < whiteThreshold || b < whiteThreshold {
                    nonWhite += 1
                }
            }
            hCoverage[y] = Double(nonWhite) / max(1, Double(hProjXHi - hProjXLo))
        }

        for x in xLo..<xHi {
            var nonWhite = 0
            for y in vProjYLo..<vProjYHi {
                let off = y * bytesPerRow + x * bpp
                let r = Double(pixels[off])
                let g = Double(pixels[off+1])
                let b = Double(pixels[off+2])
                if r < whiteThreshold || g < whiteThreshold || b < whiteThreshold {
                    nonWhite += 1
                }
            }
            vCoverage[x] = Double(nonWhite) / max(1, Double(vProjYHi - vProjYLo))
        }

        // Refine each edge by scanning from the grid CENTER outward.
        // Use coverage profiles — grid cells have high, continuous coverage (>0.6),
        // while text labels have low, sparse coverage (<0.3).
        let centerY = Int((aiBBox.yMin + aiBBox.yMax) / 2.0 * Double(height))
        let centerX = Int((aiBBox.xMin + aiBBox.xMax) / 2.0 * Double(width))
        let searchH = max(10, Int(0.12 * Double(height)))
        let searchW = max(10, Int(0.12 * Double(width)))

        // Use both luminance density and coverage for edge detection.
        // The more restrictive (inner) result wins — prevents grid from expanding into labels.
        let refinedTopLum = scanOutward(
            profile: hProj, from: centerY,
            toward: max(0, Int(aiBBox.yMin * Double(height)) - searchH), direction: -1
        )
        let refinedTopCov = scanOutward(
            profile: hCoverage, from: centerY,
            toward: max(0, Int(aiBBox.yMin * Double(height)) - searchH), direction: -1
        )
        let refinedTop = max(refinedTopLum, refinedTopCov)  // innermost wins

        let refinedBottomLum = scanOutward(
            profile: hProj, from: centerY,
            toward: min(height - 1, Int(aiBBox.yMax * Double(height)) + searchH), direction: 1
        )
        let refinedBottomCov = scanOutward(
            profile: hCoverage, from: centerY,
            toward: min(height - 1, Int(aiBBox.yMax * Double(height)) + searchH), direction: 1
        )
        let refinedBottom = min(refinedBottomLum, refinedBottomCov)  // innermost wins

        let refinedLeftLum = scanOutward(
            profile: vProj, from: centerX,
            toward: max(0, Int(aiBBox.xMin * Double(width)) - searchW), direction: -1
        )
        let refinedLeftCov = scanOutward(
            profile: vCoverage, from: centerX,
            toward: max(0, Int(aiBBox.xMin * Double(width)) - searchW), direction: -1
        )
        let refinedLeft = max(refinedLeftLum, refinedLeftCov)

        let refinedRightLum = scanOutward(
            profile: vProj, from: centerX,
            toward: min(width - 1, Int(aiBBox.xMax * Double(width)) + searchW), direction: 1
        )
        let refinedRightCov = scanOutward(
            profile: vCoverage, from: centerX,
            toward: min(width - 1, Int(aiBBox.xMax * Double(width)) + searchW), direction: 1
        )
        let refinedRight = min(refinedRightLum, refinedRightCov)

        let densityResult = RefinedBBox(
            xMin: Double(refinedLeft) / Double(width),
            yMin: Double(refinedTop) / Double(height),
            xMax: Double(refinedRight) / Double(width),
            yMax: Double(refinedBottom) / Double(height)
        )

        // Try contiguous border line detection — more accurate for charts with grid borders.
        // Grid borders are continuous lines spanning the full width/height; numbers are broken.
        if let borderResult = detectBorderLines(image: image, aiBBox: aiBBox) {
            // Validate: border detection result should be reasonable
            let bw = borderResult.xMax - borderResult.xMin
            let bh = borderResult.yMax - borderResult.yMin
            let aiW = aiBBox.xMax - aiBBox.xMin
            let aiH = aiBBox.yMax - aiBBox.yMin
            // Border result should be at least 50% of AI bbox (not too small)
            // and not larger than AI bbox + 5% (not wildly expanding)
            if bw > aiW * 0.50 && bh > aiH * 0.50 &&
               bw < aiW * 1.05 && bh < aiH * 1.05 {
                #if DEBUG
                print("""
                [GridDetector] Using BORDER LINE detection (preferred):
                  AI bbox  = (\(String(format:"%.3f",aiBBox.xMin)), \(String(format:"%.3f",aiBBox.yMin))) – (\(String(format:"%.3f",aiBBox.xMax)), \(String(format:"%.3f",aiBBox.yMax)))
                  Density  = (\(String(format:"%.3f",densityResult.xMin)), \(String(format:"%.3f",densityResult.yMin))) – (\(String(format:"%.3f",densityResult.xMax)), \(String(format:"%.3f",densityResult.yMax)))
                  Border   = (\(String(format:"%.3f",borderResult.xMin)), \(String(format:"%.3f",borderResult.yMin))) – (\(String(format:"%.3f",borderResult.xMax)), \(String(format:"%.3f",borderResult.yMax)))
                """)
                #endif
                return borderResult
            }
        }

        #if DEBUG
        print("""
        [GridDetector] Using DENSITY refinement (border detection failed or invalid):
          AI bbox = (\(String(format:"%.3f",aiBBox.xMin)), \(String(format:"%.3f",aiBBox.yMin))) – (\(String(format:"%.3f",aiBBox.xMax)), \(String(format:"%.3f",aiBBox.yMax)))
          Refined = (\(String(format:"%.3f",densityResult.xMin)), \(String(format:"%.3f",densityResult.yMin))) – (\(String(format:"%.3f",densityResult.xMax)), \(String(format:"%.3f",densityResult.yMax)))
        """)
        #endif

        return densityResult
    }

    /// Scans outward from the grid center toward an edge, finding where
    /// density drops below a threshold. This naturally finds the grid's true
    /// boundary because it starts from inside the dense grid and walks out.
    /// `direction`: -1 for scanning toward top/left, +1 for scanning toward bottom/right.
    private static func scanOutward(
        profile: [Double],
        from center: Int,
        toward limit: Int,
        direction: Int
    ) -> Int {
        let count = profile.count
        guard center >= 0, center < count else { return max(0, min(count - 1, center)) }

        // Compute the average density in the center region (known grid area)
        let sampleRadius = max(5, abs(limit - center) / 8)
        let sLo = max(0, center - sampleRadius)
        let sHi = min(count - 1, center + sampleRadius)
        let gridDensity = profile[sLo...sHi].reduce(0, +) / Double(sHi - sLo + 1)

        // The edge is where density drops below 40% of the grid's average density.
        // This threshold is generous enough to handle rows with mixed light/dark cells
        // but catches the transition to text labels and whitespace.
        let dropThreshold = gridDensity * 0.40

        // Smooth the profile for stable edge detection
        let sr = max(2, abs(limit - center) / 20)

        // Scan outward from center
        var lastAbove = center
        let range: [Int] = direction > 0
            ? Array(center...min(count - 1, limit))
            : Array(stride(from: center, through: max(0, limit), by: -1))

        for i in range {
            let lo = max(0, i - sr)
            let hi = min(count - 1, i + sr)
            let smoothed = profile[lo...hi].reduce(0, +) / Double(hi - lo + 1)

            if smoothed >= dropThreshold {
                lastAbove = i
            } else {
                // Density dropped — the grid ended at lastAbove
                break
            }
        }

        return lastAbove
    }

    // MARK: - Contiguous Line Border Detection

    /// Detects the grid boundary by finding contiguous border lines.
    /// Knitting chart grids have continuous horizontal/vertical lines (gridlines)
    /// that span the full grid width/height. Row/column numbers, by contrast, are
    /// discrete characters with gaps between them.
    ///
    /// Algorithm: scan each pixel row/column and find the longest continuous run
    /// of non-white pixels. Grid border rows have runs ≥ 60% of the AI-estimated
    /// grid width. Number rows have short runs (individual digits ~10-20px with gaps).
    private static func detectBorderLines(
        image: UIImage,
        aiBBox: (xMin: Double, yMin: Double, xMax: Double, yMax: Double)
    ) -> RefinedBBox? {
        guard let cgImage = image.cgImage,
              let context = CGContext(
                  data: nil,
                  width: cgImage.width,
                  height: cgImage.height,
                  bitsPerComponent: 8,
                  bytesPerRow: cgImage.width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let bytesPerRow = context.bytesPerRow
        let bpp = 4

        // Threshold: pixel is "ink" (not white background) if any channel < this value
        let inkThreshold: UInt8 = 220
        // Minimum gap to break a "continuous" run — allows for 1-2px anti-aliasing gaps
        let gapTolerance = max(2, width / 200)

        // Estimated grid width in pixels from AI bbox (used as reference for "full width" runs)
        let aiGridWidthPx = Int((aiBBox.xMax - aiBBox.xMin) * Double(width))
        let aiGridHeightPx = Int((aiBBox.yMax - aiBBox.yMin) * Double(height))
        // A "grid border" run must be ≥ 60% of AI-estimated grid dimension
        let hRunThreshold = max(20, Int(Double(aiGridWidthPx) * 0.60))
        let vRunThreshold = max(20, Int(Double(aiGridHeightPx) * 0.60))

        // Search zone: AI bbox ± 15% margin
        let margin = 0.15
        let ySearchLo = max(0, Int((aiBBox.yMin - margin) * Double(height)))
        let ySearchHi = min(height - 1, Int((aiBBox.yMax + margin) * Double(height)))
        let xSearchLo = max(0, Int((aiBBox.xMin - margin) * Double(width)))
        let xSearchHi = min(width - 1, Int((aiBBox.xMax + margin) * Double(width)))

        // --- Horizontal scan: find rows with long continuous runs ---
        // For each row, find the longest continuous run of ink pixels
        var rowsWithBorderLines: [(row: Int, runStart: Int, runEnd: Int)] = []

        for y in ySearchLo...ySearchHi {
            var longestStart = 0
            var longestLen = 0
            var currentStart = -1
            var currentLen = 0
            var gapCount = 0

            for x in xSearchLo...xSearchHi {
                let off = y * bytesPerRow + x * bpp
                let r = pixels[off]
                let g = pixels[off + 1]
                let b = pixels[off + 2]
                let isInk = r < inkThreshold || g < inkThreshold || b < inkThreshold

                if isInk {
                    if currentStart == -1 {
                        currentStart = x
                        currentLen = 1
                    } else {
                        currentLen += gapCount + 1
                        gapCount = 0
                    }
                } else {
                    if currentStart != -1 {
                        gapCount += 1
                        if gapCount > gapTolerance {
                            // Run ended
                            if currentLen > longestLen {
                                longestLen = currentLen
                                longestStart = currentStart
                            }
                            currentStart = -1
                            currentLen = 0
                            gapCount = 0
                        }
                    }
                }
            }
            // Close final run
            if currentLen > longestLen {
                longestLen = currentLen
                longestStart = currentStart
            }

            if longestLen >= hRunThreshold {
                rowsWithBorderLines.append((y, longestStart, longestStart + longestLen))
            }
        }

        // --- Vertical scan: find columns with long continuous runs ---
        var colsWithBorderLines: [(col: Int, runStart: Int, runEnd: Int)] = []

        for x in xSearchLo...xSearchHi {
            var longestStart = 0
            var longestLen = 0
            var currentStart = -1
            var currentLen = 0
            var gapCount = 0

            for y in ySearchLo...ySearchHi {
                let off = y * bytesPerRow + x * bpp
                let r = pixels[off]
                let g = pixels[off + 1]
                let b = pixels[off + 2]
                let isInk = r < inkThreshold || g < inkThreshold || b < inkThreshold

                if isInk {
                    if currentStart == -1 {
                        currentStart = y
                        currentLen = 1
                    } else {
                        currentLen += gapCount + 1
                        gapCount = 0
                    }
                } else {
                    if currentStart != -1 {
                        gapCount += 1
                        if gapCount > gapTolerance {
                            if currentLen > longestLen {
                                longestLen = currentLen
                                longestStart = currentStart
                            }
                            currentStart = -1
                            currentLen = 0
                            gapCount = 0
                        }
                    }
                }
            }
            if currentLen > longestLen {
                longestLen = currentLen
                longestStart = currentStart
            }

            if longestLen >= vRunThreshold {
                colsWithBorderLines.append((x, longestStart, longestStart + longestLen))
            }
        }

        guard !rowsWithBorderLines.isEmpty, !colsWithBorderLines.isEmpty else {
            #if DEBUG
            print("[GridDetector] Border detection: no border lines found (hRows=\(rowsWithBorderLines.count), vCols=\(colsWithBorderLines.count))")
            #endif
            return nil
        }

        // Find the top/bottom grid borders: first and last rows with full-width runs
        let topBorder = rowsWithBorderLines.first!.row
        let bottomBorder = rowsWithBorderLines.last!.row
        let leftBorder = colsWithBorderLines.first!.col
        let rightBorder = colsWithBorderLines.last!.col

        let result = RefinedBBox(
            xMin: Double(leftBorder) / Double(width),
            yMin: Double(topBorder) / Double(height),
            xMax: Double(rightBorder) / Double(width),
            yMax: Double(bottomBorder) / Double(height)
        )

        #if DEBUG
        print("""
        [GridDetector] Border line detection:
          hRows with border lines: \(rowsWithBorderLines.count), vCols: \(colsWithBorderLines.count)
          Top border: row \(topBorder), Bottom: row \(bottomBorder)
          Left border: col \(leftBorder), Right: col \(rightBorder)
          Result: (\(String(format:"%.3f",result.xMin)), \(String(format:"%.3f",result.yMin))) – (\(String(format:"%.3f",result.xMax)), \(String(format:"%.3f",result.yMax)))
        """)
        #endif

        return result
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
