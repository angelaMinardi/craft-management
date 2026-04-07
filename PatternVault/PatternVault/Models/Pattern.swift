//
//  Pattern.swift
//  PatternVault
//

import Foundation

// MARK: - V1 format (legacy, kept for backward compatibility)

struct ParsedStep: Codable, Identifiable, Sendable, Equatable {
    var id: String { title + body.prefix(20) }
    let title: String
    let body: String
}

struct ParsedRow: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    let instruction: String
    let stitchCount: Int?
    let isRepeatStart: Bool
    let repeatCount: Int?
    let note: String?
}

// MARK: - V2 format (instruction-level, row-aware)

/// Individual pattern instruction with row/round range and section grouping.
/// Stored as JSON array in `parsed_steps` column. Detected by presence of `section` key.
struct ParsedInstruction: Codable, Identifiable, Sendable, Equatable {
    let section: String
    let startRow: Int
    let endRow: Int
    let instruction: String
    let stitchCount: Int?
    let note: String?
    let chartImageUrl: String?
    let chartLabel: String?

    var id: String {
        "\(section)-\(startRow)-\(endRow)-\(instruction.prefix(30))"
    }

    enum CodingKeys: String, CodingKey {
        case section
        case startRow = "start_row"
        case endRow = "end_row"
        case instruction
        case stitchCount = "stitch_count"
        case note
        case chartImageUrl = "chart_image_url"
        case chartLabel = "chart_label"
    }

    /// Formatted row range for display (e.g., "Row 5", "Rows 1-10", or empty for non-numbered).
    var rowRangeLabel: String {
        if startRow == 0 && endRow == 0 { return "" }
        if startRow == endRow { return "Row \(startRow)" }
        return "Rows \(startRow)–\(endRow)"
    }

    /// Converts to a PatternStep for backward-compatible display.
    func toPatternStep() -> PatternStep {
        let title: String
        if !rowRangeLabel.isEmpty {
            title = "\(section): \(rowRangeLabel)"
        } else {
            title = section
        }
        var body = instruction
        if let note, !note.isEmpty {
            body += "\n\nNOTE: \(note)"
        }
        if let stitchCount {
            body += "\n(\(stitchCount) sts)"
        }
        return PatternStep(title: title, body: body, chartImageUrl: chartImageUrl, chartLabel: chartLabel)
    }
}

struct Pattern: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var title: String
    var patternDescription: String?
    var sourceUrl: String
    var sourcePlatform: String?
    var status: PatternStatus
    var thumbnailUrl: String?
    var difficulty: String?
    var materials: String?
    var craftType: String?
    var sourceContent: String?
    var pdfUrl: String?
    var videoUrl: String?
    var gauge: String?
    var needleHookSizes: String?
    var yarnWeightYardage: String?
    var techniques: String?
    var parsedSteps: String?
    var parsedRows: String?
    var enrichmentStatus: String?
    var enrichmentError: String?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case patternDescription = "description"
        case sourceUrl = "source_url"
        case sourcePlatform = "source_platform"
        case status
        case thumbnailUrl = "thumbnail_url"
        case difficulty
        case materials
        case craftType = "craft_type"
        case sourceContent = "source_content"
        case pdfUrl = "pdf_url"
        case videoUrl = "video_url"
        case gauge
        case needleHookSizes = "needle_hook_sizes"
        case yarnWeightYardage = "yarn_weight_yardage"
        case techniques
        case parsedSteps = "parsed_steps"
        case parsedRows = "parsed_rows"
        case enrichmentStatus = "enrichment_status"
        case enrichmentError = "enrichment_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// True when the pattern is still being enriched by the server-side AI pipeline.
    var isEnriching: Bool {
        let s = enrichmentStatus ?? "complete"
        return s == "pending" || s == "processing"
    }

    /// True when server-side enrichment failed (user can retry).
    var enrichmentFailed: Bool {
        enrichmentStatus == "failed"
    }

    /// Decode v2 instruction format (preferred). Returns nil if not v2 or if empty.
    var decodedParsedInstructions: [ParsedInstruction]? {
        guard let json = parsedSteps, let data = json.data(using: .utf8) else { return nil }
        let instructions = try? JSONDecoder().decode([ParsedInstruction].self, from: data)
        guard let instructions, !instructions.isEmpty else { return nil }
        // Validate it's actually v2 by checking first item has a non-empty section
        guard !instructions[0].section.isEmpty else { return nil }
        return instructions
    }

    /// Decode v1 step format (legacy fallback).
    var decodedParsedSteps: [ParsedStep]? {
        guard let json = parsedSteps, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([ParsedStep].self, from: data)
    }

    var decodedParsedRows: [ParsedRow]? {
        guard let json = parsedRows, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([ParsedRow].self, from: data)
    }
}

enum PatternStatus: String, Codable, CaseIterable, Sendable {
    case wantToMake = "want_to_make"
    case inProgress = "in_progress"
    case completed = "completed"

    var displayName: String {
        switch self {
        case .wantToMake: return "Want to Make"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        }
    }
}
