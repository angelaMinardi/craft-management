//
//  ExtensionChartProcessor.swift
//  SaveToPatternVault
//
//  Processes AI-returned chart references (image index + crop region) from the
//  instructions JSON, crops chart regions from rendered page images, uploads
//  them to Supabase Storage, and returns updated JSON with chart_image_url.
//

import Foundation
import UIKit

enum ExtensionChartProcessor {

    struct ChartCrop: Codable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }

    /// Processes chart references in an instructions JSON string.
    /// For each instruction with `chart_image_index` + `chart_crop`, crops the region
    /// from the source image, uploads it, and replaces with `chart_image_url`.
    /// Returns the updated JSON string (or the original if no charts found / processing fails).
    static func processChartReferences(
        instructionsJSON: String,
        images: [Data],
        patternId: String,
        upload: @escaping (Data, String) async throws -> String
    ) async -> String {
        guard !images.isEmpty,
              let jsonData = instructionsJSON.data(using: .utf8),
              var instructions = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return instructionsJSON
        }

        let hasChartRefs = instructions.contains { ($0["chart_image_index"] as? Int) != nil }
        guard hasChartRefs else { return instructionsJSON }

        var chartUrlCache: [String: String] = [:]

        for i in 0..<instructions.count {
            guard let idx = instructions[i]["chart_image_index"] as? Int,
                  idx >= 0, idx < images.count else { continue }

            let crop = parseCrop(instructions[i]["chart_crop"])
            let cacheKey = "\(idx)-\(crop?.x ?? 0)-\(crop?.y ?? 0)-\(crop?.w ?? 1)-\(crop?.h ?? 1)"

            if let cachedUrl = chartUrlCache[cacheKey] {
                instructions[i]["chart_image_url"] = cachedUrl
            } else {
                let chartData: Data = autoreleasepool {
                    let source = images[idx]
                    if let crop, !isFullImage(crop) {
                        return cropImage(data: source, rect: crop) ?? source
                    }
                    return source
                }

                let storagePath = "\(patternId)/chart_\(UUID().uuidString.lowercased()).jpg"
                do {
                    let url = try await upload(chartData, storagePath)
                    instructions[i]["chart_image_url"] = url
                    chartUrlCache[cacheKey] = url
                } catch {
                    #if DEBUG
                    print("[ExtensionChartProcessor] Upload failed for image \(idx): \(error.localizedDescription)")
                    #endif
                }
            }

            instructions[i].removeValue(forKey: "chart_image_index")
            instructions[i].removeValue(forKey: "chart_crop")
        }

        guard let updatedData = try? JSONSerialization.data(withJSONObject: instructions),
              let updatedJSON = String(data: updatedData, encoding: .utf8) else {
            return instructionsJSON
        }
        return updatedJSON
    }

    // MARK: - Helpers

    private static func parseCrop(_ value: Any?) -> ChartCrop? {
        guard let dict = value as? [String: Any],
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double else { return nil }
        return ChartCrop(x: x, y: y, w: w, h: h)
    }

    private static func isFullImage(_ crop: ChartCrop) -> Bool {
        crop.x <= 0.01 && crop.y <= 0.01 && crop.w >= 0.98 && crop.h >= 0.98
    }

    private static func cropImage(data: Data, rect: ChartCrop) -> Data? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let padding = 0.05

        let x = max(0, CGFloat(rect.x - padding)) * imgW
        let y = max(0, CGFloat(rect.y - padding)) * imgH
        let w = min(imgW - x, CGFloat(rect.w + padding * 2) * imgW)
        let h = min(imgH - y, CGFloat(rect.h + padding * 2) * imgH)

        let cropRect = CGRect(x: x, y: y, width: max(1, w), height: max(1, h))
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.85)
    }
}
