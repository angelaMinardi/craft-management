//
//  ChartImageProcessor.swift
//  PatternVault
//
//  Decodes raw Gemini AI instruction output and provides image-cropping utilities.
//  Chart images are now handled via ChartHighlight objects rather than URL uploads.
//

import Foundation
import UIKit

enum ChartImageProcessor {

    /// Intermediate instruction decoded from Gemini response (includes chart_image_index for post-processing).
    struct RawInstruction: Codable {
        let section: String
        var startRow: Int
        var endRow: Int
        let instruction: String
        let stitchCount: Int?
        let note: String?
        let chartImageIndex: Int?
        let chartLabel: String?
        let chartCrop: ChartCropRect?
        let chartRows: Int?
        let chartColumns: Int?
        let gridBoundary: ChartCropRect?
        let rowNumberPosition: String?
        let colNumberPosition: String?
        let hasLegend: Bool?
        let legendPosition: String?

        // Repeat metadata (flat fields matching AI JSON output)
        let repeatType: String?
        let referencedStartRow: Int?
        let referencedEndRow: Int?
        let fixedRepeatCount: Int?
        let targetStitchCounts: [Int]?
        let targetMeasurement: String?
        let stitchesPerCycle: Int?
        let asteriskBody: String?

        enum CodingKeys: String, CodingKey {
            case section
            case startRow = "start_row"
            case endRow = "end_row"
            case instruction
            case stitchCount = "stitch_count"
            case note
            case chartImageIndex = "chart_image_index"
            case chartLabel = "chart_label"
            case chartCrop = "chart_crop"
            case chartRows = "chart_rows"
            case chartColumns = "chart_columns"
            case gridBoundary = "grid_boundary"
            case rowNumberPosition = "row_number_position"
            case colNumberPosition = "col_number_position"
            case hasLegend = "has_legend"
            case legendPosition = "legend_position"
            case repeatType = "repeat_type"
            case referencedStartRow = "referenced_start_row"
            case referencedEndRow = "referenced_end_row"
            case fixedRepeatCount = "fixed_repeat_count"
            case targetStitchCounts = "target_stitch_counts"
            case targetMeasurement = "target_measurement"
            case stitchesPerCycle = "stitches_per_cycle"
            case asteriskBody = "asterisk_body"
        }
    }

    /// Normalized bounding box within an image (0.0-1.0 coordinates).
    struct ChartCropRect: Codable, Sendable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }

    /// Converts raw instructions to ParsedInstructions (chart fields are not populated — charts are
    /// handled separately via ChartHighlight objects).
    static func rawToInstructions(_ rawInstructions: [RawInstruction]) -> [ParsedInstruction] {
        rawInstructions.map { raw in
            // Map flat repeat fields to nested RepeatInfo
            let repeatInfo: RepeatInfo? = {
                guard let typeStr = raw.repeatType,
                      let type = RepeatInfo.RepeatType(rawValue: typeStr) else { return nil }
                return RepeatInfo(
                    type: type,
                    referencedStartRow: raw.referencedStartRow,
                    referencedEndRow: raw.referencedEndRow,
                    fixedRepeatCount: raw.fixedRepeatCount,
                    targetStitchCounts: raw.targetStitchCounts,
                    targetMeasurement: raw.targetMeasurement,
                    stitchesPerCycle: raw.stitchesPerCycle,
                    asteriskBody: raw.asteriskBody
                )
            }()

            return ParsedInstruction(
                section: raw.section,
                startRow: raw.startRow,
                endRow: raw.endRow,
                instruction: raw.instruction,
                stitchCount: raw.stitchCount,
                note: raw.note,
                chartImageUrl: nil,
                chartLabel: nil,
                repeatInfo: repeatInfo
            )
        }
    }

    // MARK: - Image Cropping

    static func isCropFullImage(_ crop: ChartCropRect) -> Bool {
        crop.x <= 0.01 && crop.y <= 0.01 && crop.w >= 0.98 && crop.h >= 0.98
    }

    private static func isFullImage(_ crop: ChartCropRect) -> Bool {
        isCropFullImage(crop)
    }

    /// Crops a JPEG image to the normalized bounding box with 5% padding.
    static func cropImagePublic(data: Data, rect: ChartCropRect) -> Data? {
        cropImage(data: data, rect: rect)
    }

    /// Crops a JPEG image to the exact normalized bounding box (no extra padding).
    static func cropImageExact(data: Data, rect: ChartCropRect) -> Data? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        let x = max(0, CGFloat(rect.x)) * imgW
        let y = max(0, CGFloat(rect.y)) * imgH
        let w = min(imgW - x, CGFloat(rect.w) * imgW)
        let h = min(imgH - y, CGFloat(rect.h) * imgH)

        let cropRect = CGRect(x: x, y: y, width: max(1, w), height: max(1, h))
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped).pngData()
    }

    private static func cropImage(data: Data, rect: ChartCropRect) -> Data? {
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

        return UIImage(cgImage: cropped).pngData()
    }
}
