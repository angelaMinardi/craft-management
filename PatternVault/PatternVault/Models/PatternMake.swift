//
//  PatternMake.swift
//  PatternVault
//

import Foundation

struct PatternMake: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let patternId: UUID
    let userId: UUID
    var name: String
    var sizeName: String?
    var yardageUsed: Int?
    var sizeMeasurements: String?
    var sizeIndex: Int?           // 0-based index into multi-size arrays (0=smallest)
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case patternId = "pattern_id"
        case userId = "user_id"
        case name
        case sizeName = "size_name"
        case yardageUsed = "yardage_used"
        case sizeMeasurements = "size_measurements"
        case sizeIndex = "size_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayName: String {
        if let size = sizeName, !size.isEmpty { return "\(name) (\(size))" }
        return name
    }
}
