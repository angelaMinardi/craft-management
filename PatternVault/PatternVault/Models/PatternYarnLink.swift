//
//  PatternYarnLink.swift
//  PatternVault
//

import Foundation

struct PatternYarnLink: Identifiable, Codable, Sendable {
    let id: UUID
    let patternId: UUID
    let userId: UUID
    let brandName: String
    let officialUrl: String?
    let storeUrl: String?
    let displayOrder: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case patternId = "pattern_id"
        case userId = "user_id"
        case brandName = "brand_name"
        case officialUrl = "official_url"
        case storeUrl = "store_url"
        case displayOrder = "display_order"
        case createdAt = "created_at"
    }
}
