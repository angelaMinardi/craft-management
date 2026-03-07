//
//  PatternImage.swift
//  PatternVault
//

import Foundation

struct PatternImage: Identifiable, Codable, Sendable {
    let id: UUID
    let patternId: UUID
    var imageUrl: String
    var displayOrder: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case patternId = "pattern_id"
        case imageUrl = "image_url"
        case displayOrder = "display_order"
        case createdAt = "created_at"
    }
}
