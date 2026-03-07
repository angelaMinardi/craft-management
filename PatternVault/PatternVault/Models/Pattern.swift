//
//  Pattern.swift
//  PatternVault
//

import Foundation

struct Pattern: Identifiable, Codable, Sendable {
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
