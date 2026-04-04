//
//  ProjectNote.swift
//  PatternVault
//

import Foundation

struct ProjectNote: Identifiable, Codable, Sendable {
    let id: UUID
    let patternId: UUID
    var noteType: ProjectNoteType
    var content: String
    var photoUrl: String?
    var durationMinutes: Int?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case patternId = "pattern_id"
        case noteType = "note_type"
        case content
        case photoUrl = "photo_url"
        case durationMinutes = "duration_minutes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum ProjectNoteType: String, Codable, CaseIterable, Sendable {
    case general
    case yarnInfo = "yarn_info"
    case modifications
    case progressUpdate = "progress_update"

    var displayName: String {
        switch self {
        case .general: return "General"
        case .yarnInfo: return "Materials / supplies"
        case .modifications: return "Modifications"
        case .progressUpdate: return "Progress Update"
        }
    }
}
